import { z } from "zod";

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

export function createOutbox(connectionId: string, storage: OutboxStorage) {
  const key = `abs-web:v1:outbox:${connectionId}`;
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

  return {
    pending: load,
    record(report: ListeningReport) {
      save([...load().filter((entry) => entry.id !== report.id), report]);
    },
    forget(libraryItemId: string, episodeId: string | null) {
      save(load().filter((entry) => entry.libraryItemId !== libraryItemId || entry.episodeId !== episodeId));
    },
    async flush(send: (sessions: ListeningReport[]) => Promise<DeliveryResult[]>): Promise<FlushResult> {
      const sending = load();
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
