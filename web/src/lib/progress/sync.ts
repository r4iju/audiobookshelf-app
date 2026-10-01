import { type AbsClient, AbsError } from "@/lib/abs/client";
import { localSyncResultSchema } from "@/lib/abs/schemas";
import { deviceInfo } from "@/lib/device";
import { randomId } from "@/lib/random-id";
import {
  beginChange,
  block,
  claimDelete,
  deliveryChange,
  disregard,
  finishDelete,
  finishSending,
  isSending,
  keep,
  type ProgressChange,
  inFlight as recordedDeliveries,
  releaseUnreadableBlocks,
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
        if (event.key === null || created.stores(event.key)) created.changed();
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
  // Whether an unknown phase's delete was issued is unknown, so only the user's choice deletes again.
  if (phase === "unknown" && !force) return "unconfirmed";
  if (phase !== "deleting") {
    if (force)
      for (const entry of await recordedDeliveries(connectionId, hold)) await disregard(connectionId, entry);
    for (;;) {
      const open = await recordedDeliveries(connectionId, hold);
      if (open.some((entry) => entry.failed || entry.page !== thisPage)) return "unconfirmed";
      if (open.length === 0) {
        const claimed = await claimDelete(connectionId, hold.id, hold);
        if (claimed === "finished" || claimed === "kept") return ended(claimed);
        if (claimed === "deleting") break;
      } else await deliveryChange(WAIT_MS);
    }
    outboxFor(connectionId).markUnconfirmed(hold.id, false);
  }
  await client.command("DELETE", `/api/me/progress/${hold.progressId}`);
  await finishDelete(connectionId, hold.id, hold);
  return "done";
}

/**
 * Gives up this account's discard of the book or episode, so nothing is deleted and its held listening is sent. One
 * whose delete has been issued goes on, shown as pending; one whose delete may have been issued stays unconfirmed.
 */
export async function keepProgress(client: AbsClient, itemId: string, episodeId: string | null) {
  const connectionId = client.connection.id;
  const outbox = outboxFor(connectionId);
  for (const hold of outbox.holdsFor(itemId, episodeId)) {
    const phase = await keep(connectionId, hold.id);
    if (phase === "kept" || phase === "finished") outbox.settled(hold.id);
    else outbox.markUnconfirmed(hold.id, phase === "unknown");
  }
}

/** Finishes this account's discard of the book or episode without waiting for unconfirmed deliveries. */
export async function discardAnyway(client: AbsClient, itemId: string, episodeId: string | null) {
  const outbox = outboxFor(client.connection.id);
  for (const hold of outbox.holdsFor(itemId, episodeId)) {
    if ((await finishDiscard(client, hold, { force: true })) !== "unconfirmed") outbox.settled(hold.id);
  }
}

/** A change to progress as the user made it, to send with `sendChange`. */
export interface IssuedChange {
  target: Target;
  item: ProgressChange;
  begun: ReturnType<typeof beginChange>;
}

/**
 * Takes a change to the account's progress on a book or episode (finished, reader place) when the user makes it,
 * recording it as being sent, like listening, so a discard accounts for it even while it waits its turn. One made
 * during a discard waits for the discard instead.
 */
export function issueChange(
  client: AbsClient,
  target: Target,
  change: ProgressChange["change"],
): IssuedChange {
  const item: ProgressChange = {
    id: randomId(),
    libraryItemId: target.libraryItemId,
    episodeId: target.episodeId,
    change,
  };
  const begun = beginChange(client.connection.id, item, thisPage, null);
  // Seen by sendChange; until then a failure would only be reported as unhandled.
  begun.catch(() => {});
  return { target, item, begun };
}

/** Sends a change to progress, once any discard it waits for allows, and only if that discard is kept. */
export async function sendChange(client: AbsClient, issued: IssuedChange) {
  const connectionId = client.connection.id;
  const { target, item } = issued;
  const recorded = await issued.begun;
  let begun = recorded;
  // A change issued during a discard may have waited its turn while that discard ended, so it looks again first.
  while (begun !== "dropped" && "blockedBy" in begun) {
    const next = await beginChange(connectionId, item, thisPage, begun);
    if (next !== "dropped" && "blockedBy" in next) await deliveryChange(WAIT_MS);
    begun = next;
  }
  if (begun === "dropped") return;
  const { sendingKey } = begun;
  // Recorded when it was made, it may have waited its turn while the user discarded anyway.
  if (begun === recorded && !(await isSending(sendingKey))) return;
  const episode = target.episodeId ? `/${target.episodeId}` : "";
  try {
    await client.command("PATCH", `/api/me/progress/${target.libraryItemId}${episode}`, item.change);
  } catch (error) {
    await finishSending(sendingKey, "failed").catch(() => {});
    throw error;
  }
  await finishSending(sendingKey, "answered").catch(() => {});
}

export const changeProgress = (client: AbsClient, target: Target, change: ProgressChange["change"]) =>
  sendChange(client, issueChange(client, target, change));

/** Sends queued listening reports; an unauthorized answer is surfaced so the shell can ask for a new sign-in. */
export async function flushReports(client: AbsClient, onUnauthorized: () => void) {
  if (inFlight) return inFlight;
  const outbox = outboxFor(client.connection.id);
  inFlight = (async () => {
    await releaseUnreadableBlocks(
      client.connection.id,
      outbox.holds().map((hold) => hold.id),
    ).catch(() => {});
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
