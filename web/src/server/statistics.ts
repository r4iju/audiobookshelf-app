import "server-only";
import { z } from "zod";
import { type LibraryItem, mediaProgressSchema } from "@/lib/abs/schemas";
import { type Account, DomainError, requireAdministrator } from "./accounts";
import { historyItemFor } from "./catalog";
import { database } from "./data";
import { reportSchema } from "./progress";
export const yearInput = z.coerce.number().int().min(1970).max(9998);
function window(year: number) {
  return { from: Date.UTC(year, 0, 1), to: Date.UTC(year + 1, 0, 1) };
}
function portion(report: z.infer<typeof reportSchema>, from: number, to: number) {
  if (report.updatedAt === report.startedAt)
    return report.updatedAt >= from && report.updatedAt < to ? report.timeListening : 0;
  return (
    (report.timeListening * Math.max(0, Math.min(report.updatedAt, to) - Math.max(report.startedAt, from))) /
    (report.updatedAt - report.startedAt)
  );
}
function historyItem(actor: Account, id: string) {
  try {
    return historyItemFor(actor, id);
  } catch (error) {
    if (error instanceof DomainError && error.status === 404) return null;
    throw error;
  }
}
function* reports(actor: Account, all = false, itemId?: string, episodeId?: string) {
  const filters: string[] = [],
    values: string[] = [];
  if (!all) {
    filters.push("user_id=?");
    values.push(actor.id);
  }
  if (itemId !== undefined) {
    filters.push("item_id=?");
    values.push(itemId);
  }
  if (episodeId !== undefined) {
    filters.push("episode_id=?");
    values.push(episodeId);
  }
  const rows = database()
    .prepare(
      `SELECT content FROM listening_reports${filters.length ? ` WHERE ${filters.join(" AND ")}` : ""} ORDER BY CAST(json_extract(content,'$.updatedAt') AS REAL) DESC,id`,
    )
    .iterate(...values);
  for (const row of rows) {
    const report = reportSchema.parse(JSON.parse(z.string().parse(row.content))),
      item = historyItem(actor, report.libraryItemId);
    if (item) yield { report, item };
  }
}
const ranked = (values: Map<string, number>) =>
  [...values]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 20)
    .map(([name, time]) => ({ name, time }));
function add(values: Map<string, number>, names: string[], time: number) {
  for (const name of new Set(names)) values.set(name, (values.get(name) ?? 0) + time);
}
function yearListening(actor: Account, year: number, all = false) {
  const { from, to } = window(year),
    authors = new Map<string, number>(),
    genres = new Map<string, number>(),
    narrators = new Map<string, number>(),
    months = new Map<string, number>(),
    books = new Map<string, LibraryItem>();
  let sessions = 0,
    time = 0,
    bookTime = 0,
    podcastTime = 0;
  for (const { report, item } of reports(actor, all)) {
    const selected = portion(report, from, to);
    if (selected <= 0) continue;
    sessions++;
    time += selected;
    if (item.mediaType === "book") {
      books.set(item.id, item);
      bookTime += selected;
    } else podcastTime += selected;
    const m = item.media.metadata;
    add(authors, m.authors?.map((a) => a.name) ?? (m.author ? [m.author] : []), selected);
    add(genres, m.genres, selected);
    add(narrators, m.narrators ?? [], selected);
    for (let month = 0; month < 12; month++) {
      const share = portion(report, Date.UTC(year, month, 1), Date.UTC(year, month + 1, 1));
      if (share > 0) add(months, [String(month)], share);
    }
  }
  return { sessions, time, bookTime, podcastTime, authors, genres, narrators, months, books };
}
function withCover(item: LibraryItem) {
  return (
    Boolean(item.media.coverPath) &&
    !database().prepare("SELECT item_id FROM retired_items WHERE item_id=?").get(item.id)
  );
}
export function personalYear(actor: Account, year: number) {
  const listened = yearListening(actor, year),
    { from, to } = window(year),
    finished = new Map<string, LibraryItem>();
  let longest: { id: string; title: string; duration: number; finishedAt: number } | null = null;
  for (const row of database()
    .prepare("SELECT item_id,content FROM media_progress WHERE user_id=? AND episode_id=''")
    .iterate(actor.id)) {
    const progress = mediaProgressSchema.parse(JSON.parse(z.string().parse(row.content)));
    if (
      !progress.isFinished ||
      progress.finishedAt == null ||
      progress.finishedAt < from ||
      progress.finishedAt >= to
    )
      continue;
    const item = historyItem(actor, z.string().parse(row.item_id));
    if (item?.mediaType === "book") {
      finished.set(item.id, item);
      const duration = item.media.duration ?? 0;
      if (
        duration > 0 &&
        (!longest || duration > longest.duration || (duration === longest.duration && item.id < longest.id))
      )
        longest = {
          id: item.id,
          title: item.media.metadata.title,
          duration,
          finishedAt: progress.finishedAt,
        };
    }
  }
  const month = ranked(listened.months)[0];
  return {
    totalListeningSessions: listened.sessions,
    totalListeningTime: listened.time,
    totalBookListeningTime: listened.bookTime,
    totalPodcastListeningTime: listened.podcastTime,
    longestAudiobookFinished: longest,
    numBooksFinished: finished.size,
    numBooksListened: listened.books.size,
    topAuthors: ranked(listened.authors),
    topGenres: ranked(listened.genres).map(({ name, time }) => ({ genre: name, time })),
    mostListenedNarrator: ranked(listened.narrators)[0] ?? null,
    mostListenedMonth: month ? { month: Number(month.name), time: month.time } : null,
    booksWithCovers: [...listened.books.values()]
      .filter((item) => !finished.has(item.id) && withCover(item))
      .slice(0, 50)
      .map((i) => i.id),
    finishedBooksWithCovers: [...finished.values()]
      .filter(withCover)
      .slice(0, 50)
      .map((i) => i.id),
  };
}
export function serverYear(actor: Account, year: number) {
  const current = requireAdministrator(actor),
    listened = yearListening(current, year, true),
    { from, to } = window(year);
  let books = 0,
    added = 0,
    totalSize = 0,
    addedSize = 0,
    totalDuration = 0,
    addedDuration = 0;
  const authorFirst = new Map<string, number>(),
    covers: string[] = [],
    archivedAuthors = new Set<string>();
  for (const row of database().prepare("SELECT id FROM catalog_items").iterate()) {
    const item = historyItem(current, z.string().parse(row.id));
    if (item?.mediaType !== "book" || item.historyOnly) continue;
    books++;
    const date = item.addedAt ?? 0,
      isAdded = date >= from && date < to,
      size = (item.libraryFiles ?? []).reduce((n, f) => n + (f.metadata.size ?? 0), 0),
      duration = item.media.duration ?? 0;
    totalSize += size;
    totalDuration += duration;
    if (isAdded) {
      added++;
      addedSize += size;
      addedDuration += duration;
      if (withCover(item) && covers.length < 50) covers.push(item.id);
    }
    for (const author of item.media.metadata.authors ?? [])
      authorFirst.set(author.id, Math.min(authorFirst.get(author.id) ?? Infinity, date));
  }
  for (const row of database()
    .prepare("SELECT row_key,content FROM migration_archive WHERE table_name='authors'")
    .iterate()) {
    const id = z.string().parse(row.row_key);
    if (!authorFirst.has(id)) continue;
    const raw = z.record(z.string(), z.unknown()).parse(JSON.parse(z.string().parse(row.content)));
    if (typeof raw.createdAt === "string") {
      const date = Date.parse(raw.createdAt);
      if (Number.isFinite(date)) {
        authorFirst.set(id, date);
        archivedAuthors.add(id);
      }
    }
  }
  for (const row of database()
    .prepare("SELECT id,created_at FROM identity_creation WHERE kind='authors'")
    .iterate())
    if (authorFirst.has(String(row.id)) && !archivedAuthors.has(String(row.id)))
      authorFirst.set(String(row.id), Number(row.created_at));
  return {
    numListeningSessions: listened.sessions,
    totalListeningTime: listened.time,
    numBooks: books,
    numBooksAdded: added,
    numAuthorsAdded: [...authorFirst.values()].filter((date) => date >= from && date < to).length,
    totalBooksAddedSize: addedSize,
    totalBooksSize: totalSize,
    totalBooksAddedDuration: addedDuration,
    totalBooksDuration: totalDuration,
    booksAddedWithCovers: covers,
    topAuthors: ranked(listened.authors),
    topNarrators: ranked(listened.narrators),
    topGenres: ranked(listened.genres).map(({ name, time }) => ({ genre: name, time })),
  };
}
function sessionPage(actor: Account, limit: number, page: number, itemId?: string, episodeId?: string) {
  let total = 0;
  const sessions = [];
  for (const { report, item } of reports(actor, false, itemId, episodeId)) {
    if (total >= page * limit && sessions.length < limit)
      sessions.push({
        ...report,
        displayTitle: item.media.metadata.title,
        displayAuthor: item.media.metadata.authorName ?? item.media.metadata.author ?? "",
        mediaMetadata: item.media.metadata,
      });
    total++;
  }
  return { total, limit, page, sessions };
}
export function recentSessions(actor: Account, limit: number, page: number) {
  return sessionPage(actor, limit, page);
}
export function itemSessions(
  actor: Account,
  itemId: string,
  limit: number,
  page: number,
  episodeId?: string,
) {
  historyItemFor(actor, itemId);
  const result = sessionPage(actor, limit, page, itemId, episodeId);
  return { ...result, itemsPerPage: limit, numPages: Math.ceil(result.total / limit) };
}
