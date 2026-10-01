import { z } from "zod";
import { randomId } from "@/lib/random-id";

// Listening progress is reported as "local sessions": one record per listening session with cumulative totals and a
// client-chosen id. Re-sending the same record is harmless, so anything not confirmed is simply sent again later,
// after a reload, an outage or a new sign-in. The server only applies progress whose updatedAt is not older than
// what it already has, so reports are dated in server time.

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
  live: () => Promise<Set<string>>;
}

const noOwners: HoldOwners = { claim: () => () => {}, live: async () => new Set() };

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
  until: z.number(),
});
/** Where owners cannot be told apart, a hold lasts this long after its owner last renewed it. */
const HOLD_MS = 5 * 60_000;
const RENEW_MS = 60_000;

export function createOutbox(connectionId: string, storage: OutboxStorage, owners: HoldOwners = noOwners) {
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
  /** Holds still in force; one whose owner is gone and whose time has run out is cleared away. */
  const liveHolds = async () => {
    const owned = await owners.live();
    return storage.keys(holdPrefix).flatMap((holdKey) => {
      let hold: z.infer<typeof holdSchema> | null = null;
      try {
        const parsed = holdSchema.safeParse(JSON.parse(storage.read(holdKey) ?? "null"));
        if (parsed.success) hold = parsed.data;
      } catch {}
      if (hold && (owned.has(holdKey.slice(holdPrefix.length)) || hold.until > Date.now())) return [hold];
      storage.remove(holdKey);
      return [];
    });
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
     * Keeps a book's or episode's listening queued, in every tab, until the returned release is called. Used while
     * its progress is being deleted, so listening recorded meanwhile is not deleted with it.
     */
    hold(libraryItemId: string, episodeId: string | null) {
      const id = randomId();
      const holdKey = `${holdPrefix}${id}`;
      const renew = () =>
        storage.write(holdKey, JSON.stringify({ libraryItemId, episodeId, until: Date.now() + HOLD_MS }));
      renew();
      const disown = owners.claim(id);
      const renewal = setInterval(renew, RENEW_MS);
      return () => {
        clearInterval(renewal);
        disown();
        storage.remove(holdKey);
        for (const listener of listeners) listener();
      };
    },
    async flush(send: (sessions: ListeningReport[]) => Promise<DeliveryResult[]>): Promise<FlushResult> {
      const holds = await liveHolds();
      const sending = load().filter(
        (entry) =>
          !holds.some(
            (hold) => hold.libraryItemId === entry.libraryItemId && hold.episodeId === entry.episodeId,
          ),
      );
      if (sending.length === 0) return { kind: "idle" };
      let results: DeliveryResult[];
      try {
        results = await send(sending);
      } catch (error) {
        return { kind: "failed", error };
      }
      // A rejected report (for example an item deleted on the server) will never succeed; keeping it would only
      // block reports behind it.
      const settled = new Map(sending.map((report) => [report.id, report.updatedAt]));
      const answered = new Set(results.map((result) => result.id));
      save(load().filter((entry) => !(answered.has(entry.id) && settled.get(entry.id) === entry.updatedAt)));
      return { kind: "sent", delivered: results.filter((result) => result.success).length };
    },
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
}
export type Outbox = ReturnType<typeof createOutbox>;
