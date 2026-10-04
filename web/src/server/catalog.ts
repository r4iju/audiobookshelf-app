import "server-only";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { lstat, open, readdir, realpath } from "node:fs/promises";
import { basename, delimiter, extname, isAbsolute, relative, resolve, sep } from "node:path";
import { z } from "zod";
import {
  type Library,
  type LibraryItem,
  libraryItemSchema,
  librarySchema,
  mediaProgressSchema,
} from "@/lib/abs/schemas";
import { type Account, canReadLibrary, canReadMedia, DomainError, requireAdministrator } from "./accounts";
import { database, transaction } from "./data";
export const createLibrarySchema = z.object({
  name: z.string().trim().min(1).max(256),
  mediaType: z.enum(["book", "podcast"]).default("book"),
  folders: z
    .array(z.object({ fullPath: z.string().min(1).max(4096) }))
    .min(1)
    .max(32),
});
const audio: Record<string, string> = {
  ".mp3": "audio/mpeg",
  ".m4b": "audio/mp4",
  ".m4a": "audio/mp4",
  ".flac": "audio/flac",
  ".ogg": "audio/ogg",
  ".opus": "audio/ogg",
  ".wav": "audio/wav",
  ".aac": "audio/aac",
};
const documents = new Set([".epub", ".pdf", ".mobi", ".azw3", ".cbz", ".cbr"]);
export function within(root: string, path: string) {
  const tail = relative(root, path);
  return tail === "" || (!tail.startsWith(`..${sep}`) && tail !== ".." && !isAbsolute(tail));
}
export async function mountedPath(path: string) {
  if (!isAbsolute(path)) throw new DomainError(400, "An absolute mounted folder is required");
  try {
    const canonical = await realpath(path);
    const roots = await Promise.all(
      (process.env.LEAFWAKE_MEDIA_ROOTS || "/media")
        .split(delimiter)
        .filter(Boolean)
        .map((path) => realpath(path)),
    );
    if (!roots.some((root) => within(root, canonical)))
      throw new DomainError(400, "Folder is outside configured media roots");
    if (!(await lstat(canonical)).isDirectory())
      throw new DomainError(400, "A mounted directory is required");
    return canonical;
  } catch (error) {
    if (error instanceof DomainError) throw error;
    throw new DomainError(400, "Mounted folder is unavailable");
  }
}
export async function createLibrary(actor: Account, input: z.infer<typeof createLibrarySchema>) {
  requireAdministrator(actor);
  const folders = await Promise.all(
    input.folders.map(async (folder) => ({ id: randomUUID(), fullPath: await mountedPath(folder.fullPath) })),
  );
  for (const [index, folder] of folders.entries()) {
    if (
      folders
        .slice(0, index)
        .some((other) => within(other.fullPath, folder.fullPath) || within(folder.fullPath, other.fullPath))
    )
      throw new DomainError(400, "Library folders cannot overlap");
  }
  return transaction((db) => {
    requireAdministrator(actor);
    const library = librarySchema.parse({
      id: randomUUID(),
      name: input.name,
      mediaType: input.mediaType,
      folders,
      displayOrder: db.prepare("SELECT COUNT(*) AS total FROM libraries").get()?.total,
      settings: { coverAspectRatio: 1 },
    });
    db.prepare("INSERT INTO libraries VALUES (?, ?)").run(library.id, JSON.stringify(library));
    return library;
  });
}
export function findLibrary(id: string) {
  const row = database().prepare("SELECT content FROM libraries WHERE id = ?").get(id);
  if (!row) throw new DomainError(404, "Not found");
  return librarySchema.parse(JSON.parse(z.string().parse(row.content)));
}
export function librariesFor(actor: Account) {
  return database()
    .prepare("SELECT content FROM libraries")
    .all()
    .map((row) => librarySchema.parse(JSON.parse(z.string().parse(row.content))))
    .filter((library) => canReadLibrary(actor, library.id));
}
function itemRow(row: unknown) {
  return libraryItemSchema.parse(JSON.parse(z.object({ content: z.string() }).parse(row).content));
}
function allowed(actor: Account, item: LibraryItem) {
  return canReadMedia(actor, {
    libraryId: item.libraryId,
    explicit: Boolean(item.media.metadata.explicit),
    tags: item.media.tags,
  });
}
export function itemFor(actor: Account, id: string) {
  const row = database().prepare("SELECT content FROM catalog_items WHERE id = ?").get(id);
  if (!row) throw new DomainError(404, "Not found");
  const item = itemRow(row);
  if (!allowed(actor, item)) throw new DomainError(404, "Not found");
  return item;
}
export function itemsFor(actor: Account, id: string) {
  findLibrary(id);
  if (!canReadLibrary(actor, id)) throw new DomainError(404, "Not found");
  return database()
    .prepare("SELECT content FROM catalog_items WHERE library_id = ?")
    .all(id)
    .map(itemRow)
    .filter((item) => allowed(actor, item));
}
export function pagedItems(actor: Account, id: string, params: URLSearchParams) {
  const limit = z.coerce
    .number()
    .int()
    .min(1)
    .max(200)
    .parse(params.get("limit") ?? 50);
  const page = z.coerce
    .number()
    .int()
    .min(0)
    .max(100000)
    .parse(params.get("page") ?? 0);
  let items = itemsFor(actor, id);
  const progress = new Map(
    database()
      .prepare("SELECT item_id, content FROM media_progress WHERE user_id = ? AND episode_id = ''")
      .all(actor.id)
      .map((row) => [
        z.string().parse(row.item_id),
        mediaProgressSchema.parse(JSON.parse(z.string().parse(row.content))),
      ]),
  );
  const filter = params.get("filter");
  if (filter) {
    const dot = filter.indexOf(".");
    if (dot < 1) throw new DomainError(400, "Invalid item filter");
    const group = filter.slice(0, dot);
    const value = Buffer.from(decodeURIComponent(filter.slice(dot + 1)), "base64").toString("utf8");
    items = items.filter((item) => {
      const metadata = item.media.metadata;
      switch (group) {
        case "authors":
          return metadata.authors?.some((author) => author.id === value) ?? false;
        case "series":
          return metadata.series?.some((series) => series.id === value) ?? false;
        case "tags":
          return item.media.tags.includes(value);
        case "genres":
          return metadata.genres.includes(value);
        case "narrators":
          return metadata.narrators?.includes(value) ?? false;
        case "languages":
          return metadata.language === value;
        case "progress": {
          const record = progress.get(item.id);
          switch (value) {
            case "finished":
              return Boolean(record?.isFinished);
            case "in-progress":
              return !record?.isFinished && (record?.progress ?? 0) > 0;
            case "not-started":
              return !record || (!record.startedAt && record.progress === 0);
            case "not-finished":
              return !record?.isFinished;
            default:
              throw new DomainError(400, "Unsupported progress filter");
          }
        }
        case "ebooks":
          return value === "ebook"
            ? Boolean(item.media.ebookFile)
            : value === "supplementary"
              ? Boolean(item.libraryFiles?.some((file) => file.fileType === "ebook" && file.isSupplementary))
              : false;
        case "missing":
          return Boolean(item.isMissing);
        case "issues":
          return Boolean(item.isMissing || item.isInvalid);
        default:
          throw new DomainError(400, "Unsupported item filter");
      }
    });
  }
  const sort = params.get("sort") ?? "addedAt";
  const value = (item: LibraryItem): string | number => {
    switch (sort) {
      case "media.metadata.title":
        return item.media.metadata.title;
      case "media.metadata.authorName":
        return item.media.metadata.authorName ?? "";
      case "media.metadata.authorNameLF":
        return (
          item.media.metadata.authors
            ?.map((author) => {
              const words = author.name.trim().split(/\s+/);
              const last = words.pop() ?? "";
              return words.length ? `${last}, ${words.join(" ")}` : last;
            })
            .join(", ") ?? ""
        );
      case "media.metadata.publishedYear":
        return item.media.metadata.publishedYear ?? "";
      case "media.duration":
        return item.media.duration ?? 0;
      case "media.numTracks":
        return item.media.numTracks ?? 0;
      case "size":
        return item.libraryFiles?.reduce((sum, file) => sum + (file.metadata.size ?? 0), 0) ?? 0;
      case "addedAt":
        return item.addedAt ?? 0;
      case "birthtimeMs":
        return z.number().parse(item.birthtimeMs ?? 0);
      case "mtimeMs":
        return z.number().parse(item.mtimeMs ?? 0);
      case "progress":
        return progress.get(item.id)?.progress ?? 0;
      case "progress.createdAt":
        return progress.get(item.id)?.startedAt ?? 0;
      case "progress.finishedAt":
        return progress.get(item.id)?.finishedAt ?? 0;
      case "random":
        return item.id;
      default:
        throw new DomainError(400, "Unsupported item sort");
    }
  };
  items.sort((a, b) => {
    const left = value(a);
    const right = value(b);
    return (
      (typeof left === "number" && typeof right === "number"
        ? left - right
        : String(left).localeCompare(String(right), undefined, { numeric: true })) || a.id.localeCompare(b.id)
    );
  });
  if (params.get("desc") === "1") items.reverse();
  return { results: items.slice(page * limit, (page + 1) * limit), total: items.length, page, limit };
}
const probeSchema = z.object({
  format: z.object({
    duration: z.coerce.number().finite().nonnegative(),
    tags: z.record(z.string(), z.string()).optional(),
  }),
  chapters: z
    .array(
      z.object({
        start_time: z.coerce.number().finite().nonnegative(),
        end_time: z.coerce.number().finite().nonnegative(),
        tags: z.object({ title: z.string().optional() }).optional(),
      }),
    )
    .default([]),
});
let probes = 0;
async function probe(path: string) {
  if (probes >= 4) throw new Error("Media probe capacity exceeded");
  probes++;
  try {
    return probeSchema.parse(
      JSON.parse(
        await new Promise<string>((resolve, reject) =>
          execFile(
            "ffprobe",
            ["-v", "error", "-show_format", "-show_chapters", "-of", "json", path],
            { timeout: 30000, maxBuffer: 2 * 1024 * 1024 },
            (error, stdout) => (error ? reject(error) : resolve(stdout)),
          ),
        ),
      ),
    );
  } finally {
    probes--;
  }
}
const metadataSchema = z.object({
  title: z.string().optional(),
  subtitle: z.string().optional(),
  description: z.string().optional(),
  explicit: z.boolean().default(false),
  tags: z.array(z.string()).default([]),
  authors: z.array(z.string()).default([]),
  narrators: z.array(z.string()).default([]),
  genres: z.array(z.string()).default([]),
});
const errorSchema = z.object({ path: z.string(), message: z.string() });
export const scanReportSchema = z.object({
  id: z.string(),
  status: z.enum(["running", "complete", "failed", "interrupted"]),
  scanned: z.number(),
  errors: z.array(errorSchema),
});
type ScanError = z.infer<typeof errorSchema>;
type ScannedFile = {
  id: string;
  itemId: string;
  path: string;
  content: {
    ino: string;
    fileType: string;
    metadata: { filename: string; ext: string; size: number };
    mimeType: string;
    index: number;
    duration: number;
    startOffset: number;
  };
};
async function readMetadata(folder: string, path: string) {
  const entry = await lstat(path);
  if (entry.isSymbolicLink()) throw new Error("Metadata symlink skipped");
  if (!entry.isFile()) throw new Error("Metadata is not a regular file");
  const canonical = await realpath(path);
  if (!within(folder, canonical)) throw new Error("Metadata escaped its mounted folder");
  const handle = await open(canonical, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    const opened =
      process.platform === "linux" ? await realpath(`/proc/self/fd/${handle.fd}`) : await realpath(canonical);
    if (!within(folder, opened) || !stat.isFile()) throw new Error("Metadata escaped its mounted folder");
    if (stat.size > 262144) throw new Error("Metadata exceeds 256 KiB");
    const bytes = Buffer.alloc(262145);
    let total = 0;
    while (total < bytes.length) {
      const read = await handle.read(bytes, total, bytes.length - total, total);
      if (!read.bytesRead) break;
      total += read.bytesRead;
    }
    if (total > 262144) throw new Error("Metadata exceeds 256 KiB");
    return JSON.parse(bytes.subarray(0, total).toString("utf8"));
  } finally {
    await handle.close();
  }
}
async function scanFolder(library: Library, folder: string, errors: ScanError[]) {
  const groups = new Map<string, string[]>();
  let count = 0;
  async function walk(directory: string, depth: number) {
    if (!within(folder, await realpath(directory)) || (await lstat(directory)).isSymbolicLink())
      throw new Error("Scan directory escaped its mounted folder");
    if (depth > 32) throw new Error("Folder nesting exceeds scan limit");
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (++count > 20000) throw new Error("Folder entry count exceeds scan limit");
      const path = resolve(directory, entry.name);
      if (entry.isSymbolicLink()) {
        errors.push({ path, message: "Symlink skipped" });
        continue;
      }
      if (entry.isDirectory()) {
        await walk(path, depth + 1);
        continue;
      }
      const ext = extname(entry.name).toLowerCase();
      if (entry.isFile() && (audio[ext] || documents.has(ext))) {
        const group = groups.get(directory) ?? [];
        group.push(path);
        groups.set(directory, group);
      }
    }
  }
  await walk(folder, 0);
  const records: { item: LibraryItem; path: string; files: ScannedFile[] }[] = [];
  for (const [directory, paths] of groups) {
    try {
      const previous = database()
        .prepare("SELECT id, content FROM catalog_items WHERE library_id = ? AND source_path = ?")
        .get(library.id, directory);
      const id = previous ? z.string().parse(previous.id) : randomUUID();
      let metadata = metadataSchema.parse({});
      try {
        metadata = metadataSchema.parse(await readMetadata(folder, resolve(directory, "metadata.json")));
      } catch (error) {
        if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
      }
      const files: ScannedFile[] = [];
      const tracks: NonNullable<LibraryItem["media"]["tracks"]> = [];
      const chapters: NonNullable<LibraryItem["media"]["chapters"]> = [];
      let duration = 0;
      let embedded: Record<string, string> = {};
      for (const path of paths.sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))) {
        if (!within(folder, await realpath(path)) || !(await lstat(path)).isFile())
          throw new Error("Media path escaped its mounted folder");
        const stat = await lstat(path);
        const ext = extname(path).toLowerCase();
        const old = database()
          .prepare("SELECT id FROM media_files WHERE item_id = ? AND source_path = ?")
          .get(id, path);
        const ino = old ? z.string().parse(old.id) : randomUUID();
        const measured = audio[ext] ? await probe(path) : null;
        if (measured && !Object.keys(embedded).length) embedded = measured.format.tags ?? {};
        const file: ScannedFile["content"] = {
          ino,
          fileType: measured ? "audio" : "ebook",
          metadata: { filename: basename(path), ext: ext.slice(1), size: stat.size },
          mimeType: audio[ext] ?? (ext === ".pdf" ? "application/pdf" : "application/octet-stream"),
          index: tracks.length + 1,
          duration: measured?.format.duration ?? 0,
          startOffset: duration,
        };
        files.push({ id: ino, itemId: id, path, content: file });
        if (measured) {
          tracks.push({
            index: file.index,
            startOffset: duration,
            duration: file.duration,
            title: basename(path),
            contentUrl: `/api/items/${id}/file/${ino}`,
            mimeType: file.mimeType,
          });
          if (measured.chapters.length)
            for (const chapter of measured.chapters)
              chapters.push({
                id: chapters.length,
                start: duration + chapter.start_time,
                end: duration + chapter.end_time,
                title: chapter.tags?.title ?? `Chapter ${chapters.length + 1}`,
              });
          else
            chapters.push({
              id: chapters.length,
              start: duration,
              end: duration + file.duration,
              title: basename(path, ext),
            });
          duration += file.duration;
        }
      }
      const ebook = files.find((file) => file.content.fileType === "ebook");
      const authors = metadata.authors.length ? metadata.authors : embedded.artist ? [embedded.artist] : [];
      const prior = previous ? itemRow(previous) : null;
      const directoryStat = await lstat(directory);
      const item = libraryItemSchema.parse({
        id,
        libraryId: library.id,
        mediaType: library.mediaType,
        birthtimeMs: directoryStat.birthtimeMs,
        mtimeMs: directoryStat.mtimeMs,
        addedAt: prior?.addedAt ?? Date.now(),
        updatedAt: Date.now(),
        isMissing: false,
        isInvalid: false,
        media: {
          id,
          metadata: {
            ...metadata,
            title: metadata.title ?? embedded.album ?? embedded.title ?? basename(directory),
            authors: authors.map((name) => ({ id: name, name })),
            authorName: authors.join(", "),
            narrators: metadata.narrators,
            genres: metadata.genres.length ? metadata.genres : embedded.genre ? [embedded.genre] : [],
          },
          tags: metadata.tags,
          duration,
          numTracks: tracks.length,
          numChapters: chapters.length,
          tracks,
          chapters,
          ebookFormat: ebook?.content.metadata.ext ?? null,
          ebookFile: ebook ? { ...ebook.content, ebookFormat: ebook.content.metadata.ext } : null,
        },
        libraryFiles: files.map((file) => file.content),
      });
      records.push({ item, path: directory, files });
    } catch (error) {
      errors.push({
        path: directory,
        message: error instanceof Error ? error.message : "Could not scan media",
      });
    }
  }
  return records;
}
export async function scanLibrary(actor: Account, id: string) {
  requireAdministrator(actor);
  const library = findLibrary(id);
  const scanId = randomUUID();
  transaction((db) => {
    if (db.prepare("SELECT id FROM scan_runs WHERE library_id = ? AND status = 'running'").get(id))
      throw new DomainError(409, "A scan is already running");
    db.prepare("INSERT INTO scan_runs VALUES (?, ?, 'running', ?, NULL, NULL)").run(scanId, id, Date.now());
  });
  const errors: ScanError[] = [];
  try {
    const records: Awaited<ReturnType<typeof scanFolder>> = [];
    for (const folder of library.folders)
      records.push(...(await scanFolder(library, await mountedPath(folder.fullPath), errors)));
    const report = scanReportSchema.parse({
      id: scanId,
      status: "complete",
      scanned: records.length,
      errors,
    });
    transaction((db) => {
      requireAdministrator(actor);
      const seen = new Set(records.map((record) => record.item.id));
      // Probe errors preserve previous records; unavailable roots abort before this transaction.
      for (const row of db
        .prepare("SELECT id, source_path, content FROM catalog_items WHERE library_id = ?")
        .all(id)) {
        const item = itemRow(row);
        if (!seen.has(item.id) && !errors.some((error) => error.path === row.source_path))
          db.prepare("UPDATE catalog_items SET content = ? WHERE id = ?").run(
            JSON.stringify({ ...item, isMissing: true }),
            item.id,
          );
      }
      for (const record of records) {
        db.prepare(
          "INSERT INTO catalog_items VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET content = excluded.content",
        ).run(record.item.id, id, record.path, JSON.stringify(record.item));
        for (const file of record.files)
          db.prepare(
            "INSERT INTO media_files VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET content = excluded.content",
          ).run(file.id, file.itemId, file.path, JSON.stringify(file.content));
      }
      db.prepare("UPDATE scan_runs SET status = 'complete', completed_at = ?, report = ? WHERE id = ?").run(
        Date.now(),
        JSON.stringify(report),
        scanId,
      );
    });
    return report;
  } catch (error) {
    const report = scanReportSchema.parse({
      id: scanId,
      status: "failed",
      scanned: 0,
      errors: [
        ...errors,
        {
          path: library.name,
          message: error instanceof DomainError ? error.message : "The scan could not complete",
        },
      ],
    });
    database()
      .prepare("UPDATE scan_runs SET status = 'failed', completed_at = ?, report = ? WHERE id = ?")
      .run(Date.now(), JSON.stringify(report), scanId);
    return report;
  }
}
export function scanHistory(actor: Account, id: string) {
  requireAdministrator(actor);
  findLibrary(id);
  return database()
    .prepare(
      "SELECT id, status, report FROM scan_runs WHERE library_id = ? ORDER BY started_at DESC LIMIT 20",
    )
    .all(id)
    .map((row) =>
      row.report
        ? scanReportSchema.parse(JSON.parse(z.string().parse(row.report)))
        : { id: row.id, status: row.status, scanned: 0, errors: [] },
    );
}

export function filterData(items: LibraryItem[]) {
  const named = (values: { id: string; name: string }[]) => [
    ...new Map(values.map((value) => [value.id, value])).values(),
  ];
  return {
    authors: named(items.flatMap((item) => item.media.metadata.authors ?? [])),
    series: named(items.flatMap((item) => item.media.metadata.series ?? [])),
    genres: [...new Set(items.flatMap((item) => item.media.metadata.genres))],
    tags: [...new Set(items.flatMap((item) => item.media.tags))],
    narrators: [...new Set(items.flatMap((item) => item.media.metadata.narrators ?? []))],
    languages: [
      ...new Set(
        items.flatMap((item) => (item.media.metadata.language ? [item.media.metadata.language] : [])),
      ),
    ],
  };
}
