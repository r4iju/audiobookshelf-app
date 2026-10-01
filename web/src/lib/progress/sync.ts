import { type AbsClient, AbsError, withLock } from "@/lib/abs/client";
import { localSyncResultSchema } from "@/lib/abs/schemas";
import { deviceInfo } from "@/lib/device";
import { createOutbox, type Outbox } from "./outbox";

const outboxes = new Map<string, Outbox>();

const browserStorage = {
  read: (key: string) => localStorage.getItem(key),
  write: (key: string, value: string) => localStorage.setItem(key, value),
};

export function outboxFor(connectionId: string) {
  let outbox = outboxes.get(connectionId);
  if (!outbox) {
    outbox = createOutbox(connectionId, browserStorage);
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
