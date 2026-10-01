import { z } from "zod";
import { randomId } from "@/lib/random-id";
import { type Begun, beginPublishing, finishSending, thisPage } from "./coordination";

// Listening progress is reported as "local sessions": one record per listening session with cumulative totals and a
// client-chosen id. What is not confirmed is sent again later, after a reload, an outage or a new sign-in, in the
// versions coordination.ts allows. The server only applies progress whose updatedAt is not older than what it
// already has, so reports are dated in server time.

export const listeningReportSchema = z.object({
  id: z.string(),
  libraryItemId: z.string(),
  episodeId: z.string().nullable(),
  libraryId: z.string(),
  mediaType: z.enum(["book", "podcast"]),
  displayTitle: z.string(),
  displayAuthor: z.string(),
  duration: z.number(),
  startTime: z.number(),
  currentTime: z.number(),
  timeListening: z.number(),
  startedAt: z.number(),
  updatedAt: z.number(),
  date: z.string(),
  dayOfWeek: z.string(),
  playMethod: z.number(),
  mediaPlayer: z.string(),
});
export type ListeningReport = z.infer<typeof listeningReportSchema>;

export type ReportIdentity = Pick<
  ListeningReport,
  | "id"
  | "libraryItemId"
  | "episodeId"
  | "libraryId"
  | "mediaType"
  | "displayTitle"
  | "displayAuthor"
  | "duration"
  | "startTime"
  | "startedAt"
>;

const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function localDate(ms: number) {
  const date = new Date(ms);
  const pad = (value: number) => String(value).padStart(2, "0");
  return {
    date: `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`,
    dayOfWeek: days[date.getDay()] as string,
  };
}

export function createListeningReport(
  identity: ReportIdentity,
  now: { currentTime: number; timeListening: number; localNow: number; serverOffset: number },
  previous?: ListeningReport,
): ListeningReport {
  const serverNow = now.localNow + now.serverOffset;
  const updatedAt = previous ? Math.max(serverNow, previous.updatedAt + 1) : serverNow;
  return {
    ...identity,
    currentTime: now.currentTime,
    timeListening: Math.round(now.timeListening * 1000) / 1000,
    updatedAt,
    ...localDate(updatedAt),
    // 0 = direct play; the browser only reports what it played itself.
    playMethod: 0,
    mediaPlayer: "html5",
  };
}

export interface OutboxStorage {
  read: (key: string) => string | null;
  write: (key: string, value: string) => void;
  remove: (key: string) => void;
  keys: (prefix: string) => string[];
}

/** Tells, across tabs, which holds still have a live owner, however long their work takes. */
export interface HoldOwners {
  /** Marks the hold as owned until the returned release is called or the tab goes away. */
  claim: (holdId: string) => () => void;
  /** The holds whose owner is alive, or null where the browser cannot tell. */
  live: () => Promise<Set<string> | null>;
}

const noOwners: HoldOwners = { claim: () => () => {}, live: async () => null };

/** Records what is being sent, across tabs, so a discard can account for it (see coordination.ts). */
export interface Deliveries {
  begin: (connectionId: string, candidates: () => ListeningReport[]) => Promise<Begun>;
  finish: (sendingKey: string, outcome: "answered" | "failed") => Promise<void>;
}

const pageDeliveries: Deliveries = {
  begin: (connectionId, candidates) => beginPublishing(connectionId, candidates, thisPage),
  finish: finishSending,
};

/** A discard in progress: its listening stays queued until the delete of `progressId` is confirmed. */
export interface Hold {
  id: string;
  libraryItemId: string;
  episodeId: string | null;
  progressId: string;
}

export interface DeliveryResult {
  id: string;
  success: boolean;
  error?: string | null;
}

export type FlushResult =
  | { kind: "idle" }
  | { kind: "sent"; delivered: number }
  | { kind: "failed"; error: unknown };

const queueSchema = z.array(listeningReportSchema);
const holdSchema = z.object({
  libraryItemId: z.string(),
  episodeId: z.string().nullable(),
  progressId: z.string(),
  /** Listening for it that another tab sent, or that failed without an answer, is not confirmed (see sync.ts). */
  unconfirmed: z.boolean().default(false),
  heartbeat: z.number(),
  abandoned: z.boolean(),
});
/** Where owners cannot be told apart, one silent this long is taken for gone, and another tab tries to finish it. */
const SILENT_MS = 5 * 60_000;
const HEARTBEAT_MS = 60_000;

export function createOutbox(
  connectionId: string,
  storage: OutboxStorage,
  owners: HoldOwners = noOwners,
  deliveries: Deliveries = pageDeliveries,
) {
  const key = `abs-web:v1:outbox:${connectionId}`;
  // One key per hold, so tabs taking and releasing holds at once never overwrite each other's.
  const holdPrefix = `abs-web:v1:outbox-hold:${connectionId}:`;
  const listeners = new Set<() => void>();

  const load = (): ListeningReport[] => {
    try {
      const parsed = queueSchema.safeParse(JSON.parse(storage.read(key) ?? "[]"));
      return parsed.success ? parsed.data : [];
    } catch {
      return [];
    }
  };
  const save = (queue: ListeningReport[]) => {
    storage.write(key, JSON.stringify(queue));
    for (const listener of listeners) listener();
  };
  const readHolds = () =>
    storage.keys(holdPrefix).flatMap((holdKey) => {
      try {
        const parsed = holdSchema.safeParse(JSON.parse(storage.read(holdKey) ?? "null"));
        if (parsed.success) return [{ ...parsed.data, id: holdKey.slice(holdPrefix.length) }];
      } catch {}
      return [];
    });
  const holdsFor = (libraryItemId: string, episodeId: string | null) =>
    readHolds().filter((hold) => hold.libraryItemId === libraryItemId && hold.episodeId === episodeId);
  const isHeld = (libraryItemId: string, episodeId: string | null) =>
    holdsFor(libraryItemId, episodeId).length > 0;
  /** Rewrites an existing hold's fields; one another tab has finished stays gone. */
  const update = (holdId: string, fields: Partial<z.infer<typeof holdSchema>>) => {
    const current = readHolds().find((hold) => hold.id === holdId);
    if (!current) return;
    const { id: _, ...stored } = current;
    storage.write(`${holdPrefix}${holdId}`, JSON.stringify({ ...stored, ...fields }));
  };
  const asHold = ({ id, libraryItemId, episodeId, progressId }: Hold): Hold => ({
    id,
    libraryItemId,
    episodeId,
    progressId,
  });
  const notify = () => {
    for (const listener of listeners) listener();
  };

  return {
    pending: load,
    record(report: ListeningReport) {
      save([...load().filter((entry) => entry.id !== report.id), report]);
    },
    forget(libraryItemId: string, episodeId: string | null) {
      save(load().filter((entry) => entry.libraryItemId !== libraryItemId || entry.episodeId !== episodeId));
    },
    /**
     * Keeps a book's or episode's listening queued, in every tab, while its progress is deleted, so listening recorded
     * meanwhile is not deleted with it. The hold ends when the delete is confirmed or the user keeps the progress: by
     * its owner (`settle`) or, once the owner has given up (`abandon`) or is gone, by whichever tab finishes it.
     * Sending it again is safe because it names the old progress row, which no later listening can be saved in.
     */
    hold(libraryItemId: string, episodeId: string | null, progressId: string) {
      const id = randomId();
      const holdKey = `${holdPrefix}${id}`;
      storage.write(
        holdKey,
        JSON.stringify({ libraryItemId, episodeId, progressId, heartbeat: Date.now(), abandoned: false }),
      );
      notify();
      const disown = owners.claim(id);
      // Only while it still exists: another tab may already have finished it.
      const renewal = setInterval(() => update(id, { heartbeat: Date.now() }), HEARTBEAT_MS);
      const stop = () => {
        clearInterval(renewal);
        disown();
      };
      return {
        id,
        settle() {
          stop();
          storage.remove(holdKey);
          notify();
        },
        abandon() {
          stop();
          update(id, { abandoned: true });
          notify();
        },
      };
    },
    isHeld,
    holdsFor: (libraryItemId: string, episodeId: string | null) =>
      holdsFor(libraryItemId, episodeId).map(asHold),
    /** Where this account's discard of the book or episode stands, if one is under way. */
    discardState(libraryItemId: string, episodeId: string | null): "pending" | "unconfirmed" | null {
      const holds = holdsFor(libraryItemId, episodeId);
      if (holds.length === 0) return null;
      return holds.some((hold) => hold.unconfirmed) ? "unconfirmed" : "pending";
    },
    markUnconfirmed(holdId: string, unconfirmed: boolean) {
      update(holdId, { unconfirmed });
      notify();
    },
    /** Holds no live tab is finishing, which another tab finishes (see finishDiscard). */
    async orphaned(): Promise<Hold[]> {
      const live = await owners.live();
      return readHolds()
        .filter(
          (hold) => hold.abandoned || (live ? !live.has(hold.id) : Date.now() - hold.heartbeat > SILENT_MS),
        )
        .map(asHold);
    },
    /** Ends a hold whose delete another tab has had confirmed. */
    settled(holdId: string) {
      storage.remove(`${holdPrefix}${holdId}`);
      notify();
    },
    async flush(send: (sessions: ListeningReport[]) => Promise<DeliveryResult[]>): Promise<FlushResult> {
      let begun: Begun;
      try {
        begun = await deliveries.begin(connectionId, () =>
          load().filter((entry) => !isHeld(entry.libraryItemId, entry.episodeId)),
        );
      } catch (error) {
        // Unrecorded, a delivery could not be waited for by a discard in another tab.
        return { kind: "failed", error };
      }
      // Exactly what was recorded is sent, so the record says what may still reach the server.
      const { sendingKey, issued, again } = begun;
      const sending = [...issued, ...again];
      // A record the browser fails to update stays as it was: still being sent, which only keeps discards waiting.
      const finish = (outcome: "answered" | "failed") =>
        deliveries.finish(sendingKey, outcome).catch(() => {});
      if (sending.length === 0) {
        await finish("answered");
        return { kind: "idle" };
      }
      let results: DeliveryResult[];
      try {
        results = await send(sending.map((publication) => publication.report));
      } catch (error) {
        await finish("failed");
        return { kind: "failed", error };
      }
      await finish("answered");
      // A rejected report (for example an item deleted on the server) will never succeed; keeping it would only
      // block reports behind it.
      const answered = new Set(results.map((result) => result.id));
      const delivered = new Set(
        sending
          .filter((publication) => answered.has(publication.report.id))
          .map((publication) => `${publication.stream}@${publication.updatedAt}`),
      );
      const queue = load();
      const left = queue.filter((entry) => !delivered.has(`${entry.id}@${entry.updatedAt}`));
      if (left.length !== queue.length) save(left);
      return { kind: "sent", delivered: results.filter((result) => result.success).length };
    },
    /** Whether this outbox keeps its queue or holds under the storage key. */
    stores: (storageKey: string) => storageKey === key || storageKey.startsWith(holdPrefix),
    /** Tells listeners that another tab changed this outbox. */
    changed: notify,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
}
export type Outbox = ReturnType<typeof createOutbox>;
