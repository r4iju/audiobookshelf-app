import { type AbsClient, AbsError } from "@/lib/abs/client";
import { localSyncResultSchema } from "@/lib/abs/schemas";
import { deviceInfo } from "@/lib/device";
import {
  block,
  deliveryChange,
  disregard,
  finishBlock,
  inFlight as recordedDeliveries,
  stillBlocked,
  thisPage,
} from "./coordination";
import { createOutbox, type Hold, type HoldOwners, type Outbox } from "./outbox";

const outboxes = new Map<string, Outbox>();

const browserStorage = {
  read: (key: string) => localStorage.getItem(key),
  write: (key: string, value: string) => localStorage.setItem(key, value),
  remove: (key: string) => localStorage.removeItem(key),
  keys: (prefix: string) =>
    Array.from({ length: localStorage.length }, (_, index) => localStorage.key(index) ?? "").filter((key) =>
      key.startsWith(prefix),
    ),
};

const holdLock = "abs-web:outbox-hold:";

/** An owner keeps a Web Lock for each hold it has; the browser lets go of it when the tab goes away. */
const browserOwners: HoldOwners = {
  claim: (holdId) => {
    if (typeof navigator === "undefined" || !navigator.locks) return () => {};
    let release = () => {};
    const released = new Promise<void>((resolve) => {
      release = resolve;
    });
    void navigator.locks.request(`${holdLock}${holdId}`, () => released);
    return release;
  },
  live: async () => {
    if (typeof navigator === "undefined" || !navigator.locks) return null;
    const { held = [], pending = [] } = await navigator.locks.query();
    return new Set(
      [...held, ...pending]
        .map((lock) => lock.name ?? "")
        .filter((name) => name.startsWith(holdLock))
        .map((name) => name.slice(holdLock.length)),
    );
  },
};

export function outboxFor(connectionId: string) {
  let outbox = outboxes.get(connectionId);
  if (!outbox) {
    outbox = createOutbox(connectionId, browserStorage, browserOwners);
    outboxes.set(connectionId, outbox);
  }
  return outbox;
}

let inFlight: Promise<unknown> | null = null;

const WAIT_MS = 5_000;

/**
 * How a discard ended for now. `unconfirmed`: listening for the book is recorded as sent by another tab, or as failed
 * without an answer, so it may still reach the server, or be running there, after a delete and bring the old place
 * back. 2.30.0 shows nothing that says such a request is done (a copy of the report sent again proves nothing about
 * the original, and any tab may send the same report), so the discard waits for that tab's answer or the user's
 * choice: `keepProgress` or `discardAnyway`.
 */
export type DiscardResult = "done" | "unconfirmed";

/**
 * Deletes the progress row a hold names once no listening for it is recorded as on its way. This page's own
 * deliveries are waited for, since it gets their answers. `force` stops counting the recorded deliveries first.
 */
export async function finishDiscard(
  client: AbsClient,
  hold: Hold,
  { force = false }: { force?: boolean },
): Promise<DiscardResult> {
  const connectionId = client.connection.id;
  if (!(await block(connectionId, hold.id, hold))) return "done";
  if (force) for (const entry of await recordedDeliveries(connectionId, hold)) await disregard(entry);
  for (;;) {
    const open = await recordedDeliveries(connectionId, hold);
    if (open.length === 0) break;
    if (open.some((entry) => entry.failed || entry.page !== thisPage)) return "unconfirmed";
    await deliveryChange(WAIT_MS);
  }
  // Kept meanwhile, by the user's choice in any tab.
  if (!(await stillBlocked(connectionId, hold.id))) return "done";
  outboxFor(connectionId).markUnconfirmed(hold.id, false);
  await client.command("DELETE", `/api/me/progress/${hold.progressId}`);
  await finishBlock(connectionId, hold.id);
  return "done";
}

/** Gives up this account's discard of the book or episode: nothing is deleted, and its held listening is sent. */
export async function keepProgress(client: AbsClient, itemId: string, episodeId: string | null) {
  const outbox = outboxFor(client.connection.id);
  for (const hold of outbox.holdsFor(itemId, episodeId)) {
    await finishBlock(client.connection.id, hold.id);
    outbox.settled(hold.id);
  }
}

/** Finishes this account's discard of the book or episode without waiting for unconfirmed listening. */
export async function discardAnyway(client: AbsClient, itemId: string, episodeId: string | null) {
  const outbox = outboxFor(client.connection.id);
  for (const hold of outbox.holdsFor(itemId, episodeId)) {
    if ((await finishDiscard(client, hold, { force: true })) === "done") outbox.settled(hold.id);
  }
}

/** Sends queued listening reports; an unauthorized answer is surfaced so the shell can ask for a new sign-in. */
export async function flushReports(client: AbsClient, onUnauthorized: () => void) {
  if (inFlight) return inFlight;
  const outbox = outboxFor(client.connection.id);
  inFlight = (async () => {
    for (const hold of await outbox.orphaned()) {
      try {
        if ((await finishDiscard(client, hold, {})) === "done") outbox.settled(hold.id);
        else outbox.markUnconfirmed(hold.id, true);
      } catch {
        // Still held; finished with a later delivery.
      }
    }
    return outbox.flush(async (sessions) => {
      const response = await client.send(
        "POST",
        "/api/session/local-all",
        { sessions, deviceInfo: deviceInfo() },
        localSyncResultSchema,
      );
      return response.results;
    });
  })()
    .then((result) => {
      if (
        result.kind === "failed" &&
        result.error instanceof AbsError &&
        result.error.kind === "unauthorized"
      ) {
        onUnauthorized();
      }
      return result;
    })
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}
