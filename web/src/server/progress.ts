import "server-only";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { type MediaProgress, mediaProgressSchema } from "@/lib/abs/schemas";
import { type Account, DomainError, findAccount } from "./accounts";
import { historyItemFor, itemFor } from "./catalog";
import { database, progressGeneration, transaction } from "./data";

const seconds = z.number().finite().min(0).max(1e9);
const timestamp = z.number().finite().min(0).max(8.64e15);
const identifier = z.string().min(1).max(256);
const reportSeconds = z.union([
  seconds,
  z
    .string()
    .max(64)
    .regex(/^\d+(?:\.\d+)?$/)
    .transform(Number)
    .pipe(seconds),
]);
export const reportSchema = z.looseObject({
  id: identifier,
  libraryItemId: identifier,
  episodeId: identifier.nullish(),
  currentTime: reportSeconds,
  timeListening: reportSeconds,
  duration: reportSeconds,
  startedAt: timestamp,
  updatedAt: timestamp,
  startTime: seconds.default(0),
  revision: z.number().int().nonnegative().optional(),
  progressGeneration: z.number().int().nonnegative().optional(),
});
export const localReportsSchema = z.object({
  sessions: z.array(z.unknown()).max(100),
  deviceInfo: z.record(z.string(), z.unknown()).optional(),
});
export const progressPatchSchema = z
  .object({
    currentTime: seconds.optional(),
    duration: seconds.optional(),
    progress: z.number().finite().min(0).max(1).optional(),
    isFinished: z.boolean().optional(),
    hideFromContinueListening: z.boolean().optional(),
    ebookLocation: z.string().max(8192).nullable().optional(),
    ebookProgress: z.number().finite().min(0).max(1).nullable().optional(),
    updatedAt: timestamp.optional(),
    lastUpdate: timestamp.optional(),
    startedAt: timestamp.optional(),
    finishedAt: timestamp.nullable().optional(),
    progressGeneration: z.number().int().nonnegative().optional(),
  })
  .strict()
  .superRefine((value, context) => {
    if (
      value.updatedAt !== undefined &&
      value.lastUpdate !== undefined &&
      value.updatedAt !== value.lastUpdate
    )
      context.addIssue({ code: "custom", message: "Conflicting progress timestamps", path: ["lastUpdate"] });
  })
  .transform(({ duration: _duration, progress: _progress, lastUpdate, ...intent }) => ({
    ...intent,
    updatedAt: intent.updatedAt ?? lastUpdate,
  }));
function readContent(row: unknown) {
  return row
    ? mediaProgressSchema.parse(JSON.parse(z.object({ content: z.string() }).parse(row).content))
    : null;
}
function readProgress(userId: string, itemId: string, episodeId: string) {
  return readContent(
    database()
      .prepare("SELECT content FROM media_progress WHERE user_id = ? AND item_id = ? AND episode_id = ?")
      .get(userId, itemId, episodeId),
  );
}
export function progressFor(actor: Account, itemId: string, episodeId = "") {
  itemFor(actor, itemId);
  return readProgress(actor.id, itemId, episodeId);
}
export function allProgress(actor: Account) {
  return database()
    .prepare("SELECT item_id,content FROM media_progress WHERE user_id = ?")
    .all(actor.id)
    .flatMap((row) => {
      try {
        itemFor(actor, z.string().parse(row.item_id));
        return [mediaProgressSchema.parse(JSON.parse(z.string().parse(row.content)))];
      } catch (error) {
        if (error instanceof DomainError && error.status === 404) return [];
        throw error;
      }
    });
}
function storeProgress(userId: string, progress: MediaProgress) {
  database()
    .prepare(`INSERT INTO media_progress(id,user_id,item_id,episode_id,content) VALUES(?,?,?,?,?)
    ON CONFLICT(user_id,item_id,episode_id) DO UPDATE SET content=excluded.content`)
    .run(progress.id, userId, progress.libraryItemId, progress.episodeId ?? "", JSON.stringify(progress));
}
function freshProgress(itemId: string, episodeId: string, duration: number, now: number) {
  return mediaProgressSchema.parse({
    id: randomUUID(),
    libraryItemId: itemId,
    episodeId: episodeId || null,
    duration,
    currentTime: 0,
    progress: 0,
    isFinished: false,
    lastUpdate: now,
    startedAt: now,
    finishedAt: null,
  });
}
function durationFor(actor: Account, itemId: string, episodeId: string) {
  const item = itemFor(actor, itemId);
  if (episodeId) {
    const episode = item.media.episodes?.find((episode) => episode.id === episodeId);
    if (!episode) throw new DomainError(404, "Not found");
    return episode.duration ?? 0;
  }
  return item.media.duration ?? 0;
}
export function patchProgress(
  actor: Account,
  itemId: string,
  episodeId: string,
  patch: z.infer<typeof progressPatchSchema>,
) {
  return transaction(
    () => {
      const current = findAccount(actor.id);
      const duration = durationFor(current, itemId, episodeId);
      const previous = readProgress(current.id, itemId, episodeId);
      const now = Date.now();
      if ((patch.progressGeneration ?? 0) !== progressGeneration(current.id, itemId, episodeId))
        throw new DomainError(
          409,
          "This progress intent predates a reset. Choose a new reading place or finish state.",
        );
      if (
        [patch.updatedAt, patch.startedAt, patch.finishedAt].some(
          (value) => value != null && value > now + 300000,
        )
      )
        throw new DomainError(400, "Progress time is in the future");
      if (patch.startedAt !== undefined && patch.startedAt > (patch.updatedAt ?? now))
        throw new DomainError(400, "Invalid progress times");
      if (patch.finishedAt != null && patch.finishedAt < (previous?.startedAt ?? patch.startedAt ?? 0))
        throw new DomainError(400, "Invalid progress times");
      if (
        previous &&
        patch.updatedAt !== undefined &&
        patch.updatedAt < z.number().parse(previous.intentAt ?? previous.lastUpdate)
      )
        return previous;
      const next = {
        ...(previous ?? freshProgress(itemId, episodeId, duration, now)),
        ...patch,
        startedAt: previous?.startedAt ?? patch.startedAt ?? patch.updatedAt ?? now,
        duration,
        lastUpdate: patch.updatedAt ?? Math.max(now, (previous?.lastUpdate ?? 0) + 1),
        intentAt: patch.updatedAt ?? now,
        intentSessionId: null,
      };
      if (patch.currentTime !== undefined) {
        next.currentTime = Math.min(duration, patch.currentTime);
        next.progress = duration ? next.currentTime / duration : 0;
      }
      if (patch.isFinished !== undefined) {
        next.finishedAt = patch.isFinished
          ? (previous?.finishedAt ?? patch.finishedAt ?? patch.updatedAt ?? now)
          : null;
        next.progress = patch.isFinished ? 1 : duration ? next.currentTime / duration : 0;
        if (patch.isFinished) next.currentTime = duration;
      }
      if (!next.isFinished) next.finishedAt = null;
      if (
        next.finishedAt != null &&
        (next.finishedAt < next.startedAt || next.finishedAt > (patch.updatedAt ?? now))
      )
        throw new DomainError(400, "Invalid progress times");
      const parsed = mediaProgressSchema.parse(next);
      storeProgress(current.id, parsed);
      return parsed;
    },
    { userId: actor.id },
  );
}
export function removeProgress(actor: Account, id: string) {
  const itemId = transaction(
    (db) => {
      const current = findAccount(actor.id);
      if (!current.active) throw new DomainError(401, "Sign-in required");
      if (db.prepare("SELECT id FROM deleted_progress WHERE user_id=? AND id=?").get(current.id, id)) return;
      const row = db
        .prepare("SELECT content FROM media_progress WHERE user_id=? AND id=?")
        .get(current.id, id);
      const progress = readContent(row);
      if (!progress) throw new DomainError(404, "Not found");
      itemFor(current, progress.libraryItemId);
      const cutoff = Math.max(Date.now(), progress.lastUpdate);
      db.prepare(`INSERT INTO progress_resets(user_id,item_id,episode_id,cutoff,generation) VALUES(?,?,?,?,1) ON CONFLICT(user_id,item_id,episode_id)
      DO UPDATE SET cutoff=MAX(cutoff,excluded.cutoff),generation=generation+1`).run(
        current.id,
        progress.libraryItemId,
        progress.episodeId ?? "",
        cutoff,
      );
      db.prepare("INSERT INTO deleted_progress VALUES(?,?)").run(current.id, id);
      db.prepare("DELETE FROM media_progress WHERE user_id=? AND id=?").run(current.id, id);
      return progress.libraryItemId;
    },
    { userId: actor.id },
  );
  if (itemId) globalThis.leafwakeRealtimeChanged?.({ userId: actor.id, itemId });
}
export const resetProgressSchema = z.object({ resetId: identifier }).strict();
export function resetProgress(actor: Account, itemId: string, episodeId: string, resetId: string) {
  return transaction(
    (db) => {
      const current = findAccount(actor.id);
      if (!current.active) throw new DomainError(401, "Sign-in required");
      durationFor(current, itemId, episodeId);
      const previous = db
        .prepare("SELECT item_id,episode_id,generation FROM progress_reset_commands WHERE user_id=? AND id=?")
        .get(current.id, resetId);
      if (previous) {
        if (previous.item_id !== itemId || previous.episode_id !== episodeId)
          throw new DomainError(409, "Reset identity changed");
        return {
          libraryItemId: itemId,
          episodeId: episodeId || null,
          progressGeneration: Number(previous.generation),
        };
      }
      const progress = readProgress(current.id, itemId, episodeId);
      db.prepare(`INSERT INTO progress_resets(user_id,item_id,episode_id,cutoff,generation) VALUES(?,?,?,?,1)
      ON CONFLICT(user_id,item_id,episode_id) DO UPDATE SET cutoff=MAX(cutoff,excluded.cutoff),generation=generation+1`).run(
        current.id,
        itemId,
        episodeId,
        Math.max(Date.now(), progress?.lastUpdate ?? 0),
      );
      if (progress) {
        db.prepare("INSERT OR IGNORE INTO deleted_progress VALUES(?,?)").run(current.id, progress.id);
        db.prepare("DELETE FROM media_progress WHERE user_id=? AND id=?").run(current.id, progress.id);
      }
      const generation = progressGeneration(current.id, itemId, episodeId);
      db.prepare("INSERT INTO progress_reset_commands VALUES(?,?,?,?,?)").run(
        current.id,
        resetId,
        itemId,
        episodeId,
        generation,
      );
      return { libraryItemId: itemId, episodeId: episodeId || null, progressGeneration: generation };
    },
    { userId: actor.id, itemId },
  );
}
export function syncLocal(actor: Account, input: z.infer<typeof localReportsSchema>) {
  const results = input.sessions.map((value) => {
    const parsed = reportSchema.safeParse(value);
    const id = parsed.success
      ? parsed.data.id
      : typeof value === "object" && value !== null && "id" in value && typeof value.id === "string"
        ? value.id
        : "";
    try {
      const report = parsed.success ? parsed.data : reportSchema.parse(value);
      const progressSynced = transaction(
        (db) => {
          const current = findAccount(actor.id);
          const episode = report.episodeId ?? "";
          const duration = durationFor(current, report.libraryItemId, episode);
          if (report.updatedAt < report.startedAt || report.updatedAt > Date.now() + 300000)
            throw new DomainError(400, "Invalid listening times");
          const oldRow = db
            .prepare("SELECT content FROM listening_reports WHERE user_id=? AND id=?")
            .get(current.id, report.id);
          const old = oldRow ? reportSchema.parse(JSON.parse(z.string().parse(oldRow.content))) : null;
          if (old && report.updatedAt < old.startedAt) throw new DomainError(400, "Invalid listening times");
          if (
            old &&
            (old.libraryItemId !== report.libraryItemId ||
              (old.episodeId ?? "") !== episode ||
              (old.progressGeneration ?? 0) !== (report.progressGeneration ?? 0))
          )
            throw new DomainError(409, "Listening identity changed");
          const newer =
            !old ||
            (report.revision !== undefined && old.revision !== undefined
              ? report.revision > old.revision
              : report.updatedAt > old.updatedAt ||
                (report.updatedAt === old.updatedAt && report.timeListening > old.timeListening));
          const stored = {
            ...(newer ? report : old),
            duration,
            startedAt: old?.startedAt ?? report.startedAt,
            timeListening: Math.max(old?.timeListening ?? 0, report.timeListening),
            deviceInfo: input.deviceInfo ?? {},
            mediaMetadata: itemFor(current, report.libraryItemId).media.metadata,
          };
          db.prepare(
            `INSERT INTO listening_reports VALUES(?,?,?,?,?) ON CONFLICT(user_id,id) DO UPDATE SET content=excluded.content`,
          ).run(current.id, report.id, report.libraryItemId, episode, JSON.stringify(stored));
          if (
            !newer ||
            (report.progressGeneration ?? 0) !== progressGeneration(current.id, report.libraryItemId, episode)
          )
            return false;
          const previous = readProgress(current.id, report.libraryItemId, episode);
          const intentAt = previous ? z.number().parse(previous.intentAt ?? previous.lastUpdate) : 0;
          const sameSession = previous?.intentSessionId === report.id;
          if (previous && !sameSession && report.updatedAt <= intentAt) return false;
          const currentTime = Math.min(duration, report.currentTime);
          const finished = duration > 0 && currentTime >= Math.max(0, duration - 1);
          const progress = mediaProgressSchema.parse({
            ...(previous ?? freshProgress(report.libraryItemId, episode, duration, report.startedAt)),
            duration,
            currentTime,
            progress: finished ? 1 : duration ? currentTime / duration : 0,
            isFinished: finished || previous?.isFinished === true,
            finishedAt: finished
              ? (previous?.finishedAt ?? report.updatedAt)
              : (previous?.finishedAt ?? null),
            lastUpdate: Math.max(previous?.lastUpdate ?? 0, report.updatedAt),
            progressGeneration: report.progressGeneration ?? 0,
            intentAt: Math.max(intentAt, report.updatedAt),
            intentSessionId: report.id,
          });
          storeProgress(current.id, progress);
          return true;
        },
        { userId: actor.id },
      );
      return { id, success: true, progressSynced };
    } catch (error) {
      if (!(error instanceof DomainError || error instanceof z.ZodError)) throw error;
      return {
        id,
        success: false,
        error: error instanceof DomainError ? error.message : "Invalid listening report",
      };
    }
  });
  return { results };
}
export function listeningStats(actor: Account) {
  const rows = database()
    .prepare("SELECT content FROM listening_reports WHERE user_id=?")
    .all(actor.id)
    .map((row) => reportSchema.parse(JSON.parse(z.string().parse(row.content))))
    .filter((report) => {
      try {
        historyItemFor(actor, report.libraryItemId);
        return true;
      } catch (error) {
        if (error instanceof DomainError && error.status === 404) return false;
        throw error;
      }
    });
  const days: Record<string, number> = {};
  const dayOfWeek: Record<string, number> = {};
  const items: Record<string, { id: string; timeListening: number; mediaMetadata: unknown }> = {};
  let totalTime = 0;
  for (const report of rows) {
    totalTime += report.timeListening;
    const date = new Date(report.updatedAt).toISOString().slice(0, 10);
    const day = String(new Date(report.updatedAt).getUTCDay());
    days[date] = (days[date] ?? 0) + report.timeListening;
    dayOfWeek[day] = (dayOfWeek[day] ?? 0) + report.timeListening;
    const previous = items[report.libraryItemId];
    items[report.libraryItemId] = {
      id: report.libraryItemId,
      timeListening: (previous?.timeListening ?? 0) + report.timeListening,
      mediaMetadata: report.mediaMetadata,
    };
  }
  return {
    totalTime,
    days,
    dayOfWeek,
    items,
    recentSessions: rows.sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 50),
  };
}
