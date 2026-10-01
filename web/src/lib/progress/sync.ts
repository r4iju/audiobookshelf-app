import { type AbsClient, AbsError, withLock } from "@/lib/abs/client";
import { localSyncResultSchema } from "@/lib/abs/schemas";
import { deviceInfo } from "@/lib/device";
import { createOutbox, type HoldOwners, type Outbox } from "./outbox";

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
    if (typeof navigator === "undefined" || !navigator.locks) return new Set();
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
const deliveryLock = (connectionId: string) => `abs-web:deliver:${connectionId}`;

/** Resolves once deliveries already on their way for this account, from any tab, have been answered. */
export async function deliveriesSettled(connectionId: string) {
  await inFlight?.catch(() => {});
  await withLock(deliveryLock(connectionId), async () => {});
}

/** Sends queued listening reports; an unauthorized answer is surfaced so the shell can ask for a new sign-in. */
export async function flushReports(client: AbsClient, onUnauthorized: () => void) {
  if (inFlight) return inFlight;
  const outbox = outboxFor(client.connection.id);
  inFlight = withLock(deliveryLock(client.connection.id), () =>
    outbox.flush(async (sessions) => {
      const response = await client.send(
        "POST",
        "/api/session/local-all",
        { sessions, deviceInfo: deviceInfo() },
        localSyncResultSchema,
      );
      return response.results;
    }),
  )
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
