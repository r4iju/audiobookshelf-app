import { type AbsClient, AbsError } from "@/lib/abs/client";
import { localSyncResultSchema } from "@/lib/abs/schemas";
import { deviceInfo } from "@/lib/device";
import { randomId } from "@/lib/random-id";
import {
  beginSending,
  block,
  claimDelete,
  deliveryChange,
  disregard,
  finishDelete,
  finishSending,
  keep,
  inFlight as recordedDeliveries,
  type Target,
  thisPage,
} from "./coordination";
import { createOutbox, type Hold, type HoldOwners, type ListeningReport, type Outbox } from "./outbox";

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
    const created = createOutbox(connectionId, browserStorage, browserOwners);
    // Another tab's holds and queue reach this one through storage events, so its discard state stays current here.
    if (typeof window !== "undefined")
      window.addEventListener("storage", (event) => {
        if (
          event.key === null ||
          event.key === `abs-web:v1:outbox:${connectionId}` ||
          event.key.startsWith(`abs-web:v1:outbox-hold:${connectionId}:`)
        )
          created.changed();
      });
    outbox = created;
    outboxes.set(connectionId, outbox);
  }
  return outbox;
}

let inFlight: Promise<unknown> | null = null;

const WAIT_MS = 5_000;

/**
 * How a discard ended for now. `unconfirmed`: something for the book is recorded as sent by another tab, or as failed
 * without an answer, so it may still reach the server, or be running there, after a delete and bring the old place
 * back. 2.30.0 shows nothing that says such a request is done (a copy sent again proves nothing about the original,
 * and any tab may send the same report), so the discard waits for that tab's answer or the user's choice:
 * `keepProgress` or `discardAnyway`. `kept`: the user kept the progress, in any tab.
 */
export type DiscardResult = "done" | "kept" | "unconfirmed";

const ended = (phase: "finished" | "kept"): DiscardResult => (phase === "kept" ? "kept" : "done");

/**
 * Deletes the progress row a hold names once nothing for its book is recorded as on its way. This page's own
 * deliveries are waited for, since it gets their answers. `force` stops counting the recorded deliveries first.
 * `forgotten`: the book's queued reports the discard dropped (see `block`).
 * Once the delete is issued the discard can no longer be kept, and a delete left unanswered is issued again.
 */
export async function finishDiscard(
  client: AbsClient,
  hold: Hold,
  { force = false, forgotten = [] }: { force?: boolean; forgotten?: ListeningReport[] },
): Promise<DiscardResult> {
  const connectionId = client.connection.id;
  const phase = await block(connectionId, hold.id, hold, forgotten);
  if (phase === "finished" || phase === "kept") return ended(phase);
  if (phase === "blocked") {
    if (force) for (const entry of await recordedDeliveries(connectionId, hold)) await disregard(entry);
    for (;;) {
      const open = await recordedDeliveries(connectionId, hold);
      if (open.length === 0) break;
      if (open.some((entry) => entry.failed || entry.page !== thisPage)) return "unconfirmed";
      await deliveryChange(WAIT_MS);
    }
    const claimed = await claimDelete(connectionId, hold.id);
    if (claimed === "finished" || claimed === "kept") return ended(claimed);
    outboxFor(connectionId).markUnconfirmed(hold.id, false);
  }
  await client.command("DELETE", `/api/me/progress/${hold.progressId}`);
  await finishDelete(connectionId, hold.id, hold);
  return "done";
}

/**
 * Gives up this account's discard of the book or episode, so nothing is deleted and its held listening is sent, and
 * says whether it could: not once a delete has been issued.
 */
export async function keepProgress(client: AbsClient, itemId: string, episodeId: string | null) {
  const connectionId = client.connection.id;
  const outbox = outboxFor(connectionId);
  let kept = true;
  for (const hold of outbox.holdsFor(itemId, episodeId)) {
    const phase = await keep(connectionId, hold.id);
    if (phase !== "kept") kept = false;
    if (phase === "kept" || phase === "finished") outbox.settled(hold.id);
    else outbox.markUnconfirmed(hold.id, false);
  }
  return kept;
}

/** Finishes this account's discard of the book or episode without waiting for unconfirmed deliveries. */
export async function discardAnyway(client: AbsClient, itemId: string, episodeId: string | null) {
  const outbox = outboxFor(client.connection.id);
  for (const hold of outbox.holdsFor(itemId, episodeId)) {
    if ((await finishDiscard(client, hold, { force: true })) !== "unconfirmed") outbox.settled(hold.id);
  }
}

/**
 * Changes the account's progress on a book or episode (finished, reader place). It is recorded as being sent, like
 * listening, so a discard accounts for it; during a discard it waits until the discard is done or kept.
 */
export async function changeProgress(client: AbsClient, target: Target, change: object) {
  const connectionId = client.connection.id;
  const item = { id: randomId(), libraryItemId: target.libraryItemId, episodeId: target.episodeId, change };
  let sendingKey = await beginSending(connectionId, item, thisPage);
  while (!sendingKey) {
    await deliveryChange(WAIT_MS);
    sendingKey = await beginSending(connectionId, item, thisPage);
  }
  const episode = target.episodeId ? `/${target.episodeId}` : "";
  try {
    await client.command("PATCH", `/api/me/progress/${target.libraryItemId}${episode}`, change);
  } catch (error) {
    await finishSending(sendingKey, "failed").catch(() => {});
    throw error;
  }
  await finishSending(sendingKey, "answered").catch(() => {});
}

/** Sends queued listening reports; an unauthorized answer is surfaced so the shell can ask for a new sign-in. */
export async function flushReports(client: AbsClient, onUnauthorized: () => void) {
  if (inFlight) return inFlight;
  const outbox = outboxFor(client.connection.id);
  inFlight = (async () => {
    for (const hold of await outbox.orphaned()) {
      try {
        if ((await finishDiscard(client, hold, {})) !== "unconfirmed") outbox.settled(hold.id);
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
