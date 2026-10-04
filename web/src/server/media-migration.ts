import "server-only";
import { createHash, randomUUID } from "node:crypto";
import { lstat, realpath } from "node:fs/promises";
import { basename, extname, isAbsolute, relative, resolve } from "node:path";
import { z } from "zod";
import {
  type MediaImportReport,
  type mediaCommitSchema,
  type mediaInspectSchema,
  mediaImportReportSchema as reportSchema,
} from "@/lib/abs/imports";

export { mediaCommitSchema, mediaInspectSchema } from "@/lib/abs/imports";

import {
  bookMetadataSchema,
  bookmarkSchema,
  chapterSchema,
  libraryItemSchema,
  librarySchema,
  mediaProgressSchema,
  seriesRefSchema,
} from "@/lib/abs/schemas";
import { type Account, DomainError } from "./accounts";
import { mountedPath, within } from "./catalog";
import { catalogChanged, database, transaction } from "./data";
import { sourceCopy } from "./migration";
import { sealArchive } from "./secrets";

type Input = z.infer<typeof mediaInspectSchema>;
const id = z.string().min(1).max(256),
  json = z.string().max(16 * 1024 * 1024),
  seconds = z.number().finite().nonnegative().max(1e9);
const date = z
  .string()
  .refine((value) => Number.isFinite(Date.parse(value)), "Invalid source date")
  .transform((value) => Date.parse(value));
const flag = z.number().int().min(0).max(1).transform(Boolean);
const fileSchema = z.object({
  ino: id,
  metadata: z.object({
    filename: z.string().min(1).max(4096),
    ext: z.string().max(32),
    size: z.number().nonnegative().nullish(),
    path: z.string().optional(),
    relPath: z.string().optional(),
  }),
  ebookFormat: z.string().nullish(),
  fileType: z.string().optional(),
  isSupplementary: z.boolean().nullish(),
  mimeType: z.string().optional(),
  duration: seconds.optional(),
  index: z.number().optional(),
  exclude: z.boolean().optional(),
});
const missingFileSchema = fileSchema.omit({ ino: true }).extend({ ino: id.nullish() });
const publicMetadataSchema = bookMetadataSchema.strip().extend({
  authors: z.array(z.object({ id, name: z.string() })).nullish(),
  series: z
    .union([z.array(seriesRefSchema.strip()), seriesRefSchema.strip().transform((one) => [one])])
    .nullish(),
});
const publicLibrarySettingsSchema = z.object({ coverAspectRatio: z.number().default(1) });
const tableNames = [
  "libraries",
  "libraryFolders",
  "libraryItems",
  "books",
  "podcasts",
  "podcastEpisodes",
  "authors",
  "series",
  "bookAuthors",
  "bookSeries",
  "mediaProgresses",
  "playbackSessions",
  "users",
] as const;
type Table = (typeof tableNames)[number];
const record = z.record(z.string(), z.union([z.string(), z.number().finite(), z.null()]));
const completionSchema = z.object({
  id: z.string().uuid(),
  digest: z.string(),
  scope: z.literal("media"),
  accountCount: z.number(),
  completedAt: z.number(),
  mappingDigest: z.string(),
  report: reportSchema,
});
const jsonArray = (value: unknown) => z.array(z.unknown()).parse(JSON.parse(json.parse(value ?? "[]")));
const jsonObject = (value: unknown) =>
  z.record(z.string(), z.unknown()).parse(JSON.parse(json.parse(value ?? "{}")));
function mapsDigest(input: Input) {
  return createHash("sha256").update(JSON.stringify(input.mappings)).digest("hex");
}
function owner(authorize: () => Account) {
  const actor = authorize();
  if (actor.type !== "root" || !actor.active) throw new DomainError(403, "Owner access required");
  return actor;
}
async function inventory(input: Input, authorize: () => Account) {
  owner(authorize);
  const source = sourceCopy(input.sourcePath);
  try {
    const rows = new Map<Table, z.infer<typeof record>[]>();
    const objects = source.db
      .prepare(
        "SELECT name,type,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND type IN ('table','view','trigger')",
      )
      .all();
    const errors: MediaImportReport["errors"] = [],
      remainingData: MediaImportReport["remainingData"] = [],
      archivedFields: MediaImportReport["archivedFields"] = [];
    const archive: { table: string; key: string; content: string }[] = [];
    for (const object of objects) {
      const name = z
        .string()
        .regex(/^[A-Za-z][A-Za-z0-9_]*$/)
        .parse(object.name);
      if (object.type !== "table") {
        archive.push({
          table: "sqlite_master",
          key: `${object.type}:${name}`,
          content: JSON.stringify(object),
        });
        remainingData.push({ table: `${object.type}:${name}`, rows: 1 });
        continue;
      }
      const count = Number(source.db.prepare(`SELECT COUNT(*) AS n FROM "${name}"`).get()?.n);
      if (count > 100000) throw new DomainError(400, "Source table exceeds the supported import limit");
      const values: z.infer<typeof record>[] = [];
      for (const raw of source.db.prepare(`SELECT * FROM "${name}"`).all()) {
        const parsed = record.safeParse(raw);
        if (
          parsed.success &&
          tableNames.some((table) => table === name) &&
          !id.safeParse(parsed.data.id).success
        )
          errors.push({ table: name, id: String(raw.id), message: "Unsupported source record identifier" });
        else if (parsed.success) values.push(parsed.data);
        else
          errors.push({
            table: name,
            id: String(raw.id ?? values.length),
            message: `Unsupported source fields: ${parsed.error.issues.map((issue) => issue.path.join(".")).join(", ")}`,
          });
      }
      for (const [index, value] of values.entries())
        archive.push({ table: name, key: String(value.id ?? index), content: JSON.stringify(value) });
      const known = tableNames.find((t) => t === name);
      if (known) rows.set(known, values);
      else if (count)
        remainingData.push({
          table: name,
          rows: count,
          recordIds: values.map((value, index) => String(value.id ?? index)),
        });
      if (values.length) archivedFields.push({ table: name, fields: Object.keys(record.parse(values[0])) });
    }
    for (const name of ["users", "libraries", "libraryFolders", "libraryItems", "books"] as const)
      if (!rows.has(name)) errors.push({ table: name, message: "Required source table is missing" });
    const users = rows.get("users") ?? [];
    if (
      !database().prepare("SELECT id FROM migrations WHERE digest=? AND scope='accounts'").get(source.digest)
    )
      errors.push({
        table: "users",
        message: "Use the same consistent snapshot as the completed account import",
      });
    for (const user of users) {
      const current = database().prepare("SELECT username FROM users WHERE id=?").get(id.parse(user.id));
      if (!current || current.username !== user.username)
        errors.push({ table: "users", id: String(user.id), message: "Import matching accounts first" });
    }
    const mappings = await Promise.all(
      input.mappings.map(async (mapping) => {
        if (!isAbsolute(mapping.from)) throw new DomainError(400, "Source mount prefix must be absolute");
        return { from: resolve(mapping.from), to: await mountedPath(mapping.to) };
      }),
    );
    for (const [index, mapping] of mappings.entries())
      if (
        mappings
          .slice(0, index)
          .some((other) => within(other.from, mapping.from) || within(mapping.from, other.from))
      )
        throw new DomainError(400, "Source mount mappings cannot overlap");
    function mapped(path: string) {
      if (!isAbsolute(path)) throw new Error("Source media path must be absolute");
      const match = mappings.find((mapping) => within(mapping.from, resolve(path)));
      if (!match) throw new Error("Media path has no mounted mapping");
      return resolve(match.to, relative(match.from, resolve(path)));
    }
    const folders = new Map<string, { id: string; libraryId: string; fullPath: string }>();
    for (const raw of rows.get("libraryFolders") ?? []) {
      try {
        const folder = z.object({ id, libraryId: id, path: z.string() }).parse(raw);
        folders.set(folder.id, {
          id: folder.id,
          libraryId: folder.libraryId,
          fullPath: await mountedPath(mapped(folder.path)),
        });
      } catch {
        errors.push({
          table: "libraryFolders",
          id: String(raw.id),
          message: "Folder association or mounted mapping is invalid",
        });
      }
    }
    const libraries = [];
    for (const raw of rows.get("libraries") ?? []) {
      try {
        const library = z
          .object({
            id,
            name: z.string(),
            mediaType: z.enum(["book", "podcast"]),
            displayOrder: z.number().int(),
          })
          .parse(raw);
        const associated = [...folders.values()].filter((folder) => folder.libraryId === library.id);
        if (!associated.length) throw Error();
        libraries.push(
          librarySchema.parse({
            ...library,
            folders: associated,
            settings: publicLibrarySettingsSchema.parse(jsonObject(raw.settings)),
          }),
        );
      } catch {
        errors.push({
          table: "libraries",
          id: String(raw.id),
          message: "Library or folder association is unsupported",
        });
      }
    }
    const books = new Map((rows.get("books") ?? []).map((row) => [id.parse(row.id), row]));
    const podcasts = new Map((rows.get("podcasts") ?? []).map((row) => [id.parse(row.id), row]));
    const authors = new Map((rows.get("authors") ?? []).map((row) => [id.parse(row.id), row]));
    const series = new Map((rows.get("series") ?? []).map((row) => [id.parse(row.id), row]));
    const files: { id: string; itemId: string; path: string; content: unknown }[] = [];
    const items: z.infer<typeof libraryItemSchema>[] = [];
    const historical = new Map<string, { userId: string; removedAt: number }>();
    const paths = new Map<string, string>(),
      mediaToItem = new Map<string, { itemId: string; episodeId: string }>();
    for (const raw of rows.get("libraryItems") ?? []) {
      try {
        const item = z
          .object({
            id,
            libraryId: id,
            libraryFolderId: id,
            mediaId: id,
            mediaType: z.enum(["book", "podcast"]),
            path: z.string(),
            isFile: flag,
            isMissing: flag,
            isInvalid: flag,
            libraryFiles: json,
            createdAt: date,
            updatedAt: date,
          })
          .parse(raw);
        const library = libraries.find((l) => l.id === item.libraryId),
          folder = folders.get(item.libraryFolderId);
        if (!library || !folder || folder.libraryId !== library.id || library.mediaType !== item.mediaType)
          throw Error("Invalid library relationship");
        const path = mapped(item.path);
        if (!within(folder.fullPath, path)) throw Error("Item escaped its library folder");
        if (!item.isMissing) {
          if (!(await lstat(path)).isFile() && !(await lstat(path)).isDirectory())
            throw Error("Item path is not regular");
          if ((await realpath(path)) !== path) throw Error("Item links are unsupported");
        }
        function sourceFile(value: unknown) {
          if (!item.isMissing) return fileSchema.parse(value);
          const missing = missingFileSchema.parse(value);
          return fileSchema.parse({
            ...missing,
            ino:
              missing.ino ??
              createHash("sha256")
                .update(
                  `missing:${item.id}:${missing.metadata.path ?? missing.metadata.relPath ?? missing.metadata.filename}`,
                )
                .digest("hex"),
          });
        }
        const sourceFiles = jsonArray(item.libraryFiles).map(sourceFile);
        const media = item.mediaType === "book" ? books.get(item.mediaId) : podcasts.get(item.mediaId);
        if (!media) throw Error("Media identity is missing");
        const mediaFiles = jsonArray(media.audioFiles).map(sourceFile);
        if (media.ebookFile) mediaFiles.push(sourceFile(JSON.parse(json.parse(media.ebookFile))));
        for (const episode of rows.get("podcastEpisodes") ?? [])
          if (episode.podcastId === item.mediaId && episode.audioFile)
            mediaFiles.push(sourceFile(JSON.parse(json.parse(episode.audioFile))));
        const normalized: z.infer<typeof fileSchema>[] = [];
        for (const sourceFile of sourceFiles) {
          const details = mediaFiles.find((value) => value.ino === sourceFile.ino);
          const file = fileSchema.parse({
            ...details,
            ...sourceFile,
            metadata: { ...details?.metadata, ...sourceFile.metadata },
          });
          const original =
            file.metadata.path ??
            resolve(
              item.isFile ? resolve(item.path, "..") : item.path,
              file.metadata.relPath ?? file.metadata.filename,
            );
          const filepath = mapped(original);
          if (!within(folder.fullPath, filepath)) throw Error("File escaped its library folder");
          if (!item.isMissing) {
            const stat = await lstat(filepath);
            if (!stat.isFile() || (await realpath(filepath)) !== filepath || stat.size !== file.metadata.size)
              throw Error("File association changed or is unsupported");
          }
          const ext = extname(file.metadata.filename).slice(1).toLowerCase();
          const content = {
            ...file,
            fileType:
              file.fileType ??
              (file.mimeType?.startsWith("audio/")
                ? "audio"
                : ["pdf", "epub", "mobi", "azw3", "cbz", "cbr"].includes(ext)
                  ? "ebook"
                  : "other"),
            mimeType:
              file.mimeType ??
              (ext === "pdf"
                ? "application/pdf"
                : ext === "epub"
                  ? "application/epub+zip"
                  : "application/octet-stream"),
            metadata: { ...file.metadata, ext, path: filepath, filename: basename(filepath) },
            isSupplementary: file.isSupplementary ?? false,
          };
          normalized.push(content);
          files.push({ id: file.ino, itemId: item.id, path: filepath, content });
        }
        const joinedAuthors = (rows.get("bookAuthors") ?? [])
          .filter((join) => join.bookId === item.mediaId)
          .map((join) => {
            const author = authors.get(id.parse(join.authorId));
            if (!author) throw Error("Author identity is missing");
            return { id: id.parse(author.id), name: z.string().parse(author.name) };
          });
        const joinedSeries = (rows.get("bookSeries") ?? [])
          .filter((join) => join.bookId === item.mediaId)
          .map((join) => {
            const entry = series.get(id.parse(join.seriesId));
            if (!entry) throw Error("Series identity is missing");
            return {
              id: id.parse(entry.id),
              name: z.string().parse(entry.name),
              sequence: join.sequence === null ? null : z.string().parse(join.sequence),
            };
          });
        let offset = 0;
        const tracks = jsonArray(media.audioFiles)
          .map(sourceFile)
          .filter((file) => !file.exclude)
          .map((file) => {
            const stored = normalized.find((f) => f.ino === file.ino);
            if (!stored) throw Error("Audio file has no source association");
            const duration = seconds.parse(file.duration);
            const track = {
              ...file,
              startOffset: offset,
              duration,
              title: file.metadata.filename,
              contentUrl: `/api/items/${item.id}/file/${file.ino}`,
            };
            offset += duration;
            return track;
          });
        const ebook = media.ebookFile ? sourceFile(JSON.parse(json.parse(media.ebookFile))) : null;
        if (ebook && !normalized.some((file) => file.ino === ebook.ino))
          throw Error("Ebook has no source association");
        const episodes = (rows.get("podcastEpisodes") ?? [])
          .filter((row) => row.podcastId === item.mediaId)
          .map((row) => {
            const episodeId = id.parse(row.id),
              audioFile = row.audioFile ? fileSchema.parse(JSON.parse(json.parse(row.audioFile))) : null;
            if (audioFile && !normalized.some((file) => file.ino === audioFile.ino))
              throw Error("Episode has no source file association");
            mediaToItem.set(episodeId, { itemId: item.id, episodeId });
            return {
              index: row.index,
              title: row.title,
              subtitle: row.subtitle,
              description: row.description,
              season: row.season,
              episode: row.episode,
              episodeType: row.episodeType,
              pubDate: row.pubDate,
              podcastId: item.mediaId,
              id: episodeId,
              libraryItemId: item.id,
              audioFile,
              duration: audioFile?.duration ?? 0,
              size: audioFile?.metadata.size ?? 0,
              chapters: jsonArray(row.chapters).map((value) => chapterSchema.strip().parse(value)),
              publishedAt: row.publishedAt ? date.parse(row.publishedAt) : null,
              enclosure: row.enclosure
                ? z
                    .object({
                      url: z.string().url(),
                      type: z.string().optional(),
                      length: z.union([z.number().nonnegative(), z.string()]).optional(),
                    })
                    .parse(JSON.parse(json.parse(row.enclosure)))
                : row.enclosureURL
                  ? { url: z.string().url().parse(row.enclosureURL) }
                  : null,
            };
          });
        const metadata = {
          subtitle: media.subtitle ?? null,
          publishedYear: media.publishedYear ?? null,
          publishedDate: media.publishedDate ?? null,
          publisher: media.publisher ?? null,
          description: media.description ?? null,
          isbn: media.isbn ?? null,
          asin: media.asin ?? null,
          language: media.language ?? null,
          abridged: media.abridged === 1,
          author: media.author ?? null,
          title: z.string().parse(media.title),
          authors: joinedAuthors,
          authorName: joinedAuthors.map((author) => author.name).join(", "),
          series: joinedSeries,
          narrators: jsonArray(media.narrators),
          genres: jsonArray(media.genres),
          explicit: media.explicit === 1,
          feedUrl: media.feedURL ?? null,
        };
        const content = libraryItemSchema.parse({
          ...item,
          path,
          folderId: item.libraryFolderId,
          addedAt: item.createdAt,
          updatedAt: item.updatedAt,
          libraryFiles: normalized,
          media: {
            id: item.mediaId,
            metadata,
            tags: jsonArray(media.tags),
            duration:
              item.mediaType === "book"
                ? seconds.parse(media.duration)
                : episodes.reduce((n, e) => n + (e.duration ?? 0), 0),
            audioFiles: mediaFiles.filter((file) => file.mimeType?.startsWith("audio/")),
            tracks,
            chapters: jsonArray(media.chapters).map((value) => chapterSchema.strip().parse(value)),
            numTracks: tracks.length,
            ebookFile: ebook
              ? {
                  ...ebook,
                  metadata: { ...ebook.metadata, ext: ebook.metadata.ext.replace(/^\./, "") },
                  ebookFormat: ebook.ebookFormat ?? ebook.metadata.ext.replace(/^\./, ""),
                }
              : null,
            episodes,
            autoDownloadEpisodes:
              item.mediaType === "podcast"
                ? z
                    .union([z.boolean(), z.literal(0), z.literal(1)])
                    .nullish()
                    .parse(media.autoDownloadEpisodes) === true || media.autoDownloadEpisodes === 1
                : undefined,
            ebookFormat: ebook?.metadata.ext.replace(/^\./, "") ?? null,
          },
        });
        items.push(content);
        paths.set(item.id, path);
        mediaToItem.set(item.mediaId, { itemId: item.id, episodeId: "" });
      } catch (error) {
        errors.push({
          table: "libraryItems",
          id: String(raw.id),
          message:
            error instanceof z.ZodError
              ? "Unsupported media fields"
              : error instanceof Error
                ? error.message
                : "Unsupported media relationship",
        });
      }
    }
    const progress: {
      userId: string;
      itemId: string;
      episodeId: string;
      content: z.infer<typeof mediaProgressSchema>;
    }[] = [];
    for (const raw of rows.get("mediaProgresses") ?? []) {
      try {
        const value = z
          .object({
            id,
            userId: id,
            mediaItemId: id,
            mediaItemType: z.enum(["book", "podcastEpisode"]),
            duration: seconds,
            currentTime: seconds,
            isFinished: flag,
            createdAt: date,
            updatedAt: date,
          })
          .parse(raw);
        const target = mediaToItem.get(value.mediaItemId);
        if (
          !target ||
          !users.some((user) => user.id === value.userId) ||
          (value.mediaItemType === "podcastEpisode") !== Boolean(target.episodeId)
        )
          throw Error("Invalid progress ownership");
        const extra = jsonObject(raw.extraData);
        if (extra.libraryItemId && extra.libraryItemId !== target.itemId)
          throw Error("Progress item association differs");
        progress.push({
          userId: value.userId,
          ...target,
          content: mediaProgressSchema.parse({
            id: value.id,
            userId: value.userId,
            duration: value.duration,
            currentTime: value.currentTime,
            isFinished: value.isFinished,
            libraryItemId: target.itemId,
            episodeId: target.episodeId || null,
            progress:
              extra.progress === undefined
                ? value.isFinished
                  ? 1
                  : value.duration
                    ? Math.min(1, value.currentTime / value.duration)
                    : 0
                : z.number().finite().min(0).max(1).parse(extra.progress),
            hideFromContinueListening:
              raw.hideFromContinueListening == null ? false : flag.parse(raw.hideFromContinueListening),
            ebookProgress: raw.ebookProgress,
            ebookLocation: raw.ebookLocation,
            startedAt: value.createdAt,
            lastUpdate: value.updatedAt,
            finishedAt: raw.finishedAt ? date.parse(raw.finishedAt) : null,
            progressGeneration: 0,
            intentAt: value.updatedAt,
            intentSessionId: null,
          }),
        });
      } catch {
        errors.push({
          table: "mediaProgresses",
          id: String(raw.id),
          message: "Unsupported progress or account/media association",
        });
      }
    }
    const sessions: {
      userId: string;
      itemId: string;
      episodeId: string;
      content: Record<string, unknown>;
    }[] = [];
    for (const raw of rows.get("playbackSessions") ?? []) {
      try {
        const value = z
          .object({
            id,
            userId: id,
            libraryId: id,
            mediaItemId: id,
            mediaItemType: z.enum(["book", "podcastEpisode"]),
            duration: seconds,
            currentTime: seconds,
            timeListening: seconds.nullable(),
            startTime: seconds,
            createdAt: date,
            updatedAt: date,
          })
          .parse(raw);
        let target = mediaToItem.get(value.mediaItemId);
        const extra = jsonObject(raw.extraData);
        const metadata = publicMetadataSchema.parse(jsonObject(raw.mediaMetadata));
        if (
          !target &&
          value.mediaItemType === "book" &&
          !(rows.get("libraryItems") ?? []).some((item) => item.mediaId === value.mediaItemId)
        ) {
          const originalItemId = id.parse(extra.libraryItemId);
          if (!libraries.some((library) => library.id === value.libraryId && library.mediaType === "book"))
            throw Error();
          const existing = items.find((item) => item.id === originalItemId);
          if (existing && (existing.media.id !== value.mediaItemId || existing.libraryId !== value.libraryId))
            throw Error("Conflicting historical item identity");
          if (!existing) {
            const path = `history:${originalItemId}`;
            items.push(
              libraryItemSchema.parse({
                id: originalItemId,
                libraryId: value.libraryId,
                mediaType: "book",
                path,
                historyOnly: true,
                historicalTagsUnknown: true,
                isMissing: true,
                addedAt: value.createdAt,
                updatedAt: value.updatedAt,
                libraryFiles: [],
                media: {
                  id: value.mediaItemId,
                  metadata: { ...metadata, explicit: true },
                  duration: value.duration,
                  tracks: [],
                  chapters: [],
                  tags: [],
                },
              }),
            );
            paths.set(originalItemId, path);
            historical.set(originalItemId, { userId: value.userId, removedAt: Date.now() });
          }
          target = { itemId: originalItemId, episodeId: "" };
          mediaToItem.set(value.mediaItemId, target);
        }
        if (
          !target ||
          !users.some((user) => user.id === value.userId) ||
          items.find((item) => item.id === target.itemId)?.libraryId !== value.libraryId ||
          (value.mediaItemType === "podcastEpisode") !== Boolean(target.episodeId) ||
          (extra.libraryItemId && extra.libraryItemId !== target.itemId)
        )
          throw Error();
        sessions.push({
          userId: value.userId,
          ...target,
          content: {
            id: value.id,
            userId: value.userId,
            duration: value.duration,
            currentTime: value.currentTime,
            timeListening: value.timeListening ?? 0,
            ...(value.timeListening === null ? { timeListeningUnavailable: true } : {}),
            startTime: value.startTime,
            libraryId: value.libraryId,
            mediaType: value.mediaItemType,
            libraryItemId: target.itemId,
            episodeId: target.episodeId || null,
            startedAt: value.createdAt,
            updatedAt: value.updatedAt,
            progressGeneration: 0,
            mediaMetadata: metadata,
            chapters: jsonArray(raw.chapters).map((value) => chapterSchema.strip().parse(value)),
            legacyArchive: true,
          },
        });
      } catch {
        errors.push({
          table: "playbackSessions",
          id: String(raw.id),
          message: "Unsupported listening history or account/media association",
        });
      }
    }
    const bookmarks: {
      id: string;
      userId: string;
      itemId: string;
      content: z.infer<typeof bookmarkSchema>;
    }[] = [];
    for (const user of users) {
      try {
        for (const [index, value] of jsonArray(user.bookmarks).entries()) {
          const bookmark = bookmarkSchema.strip().parse(value);
          if (
            !items.some((item) => item.id === bookmark.libraryItemId) ||
            !Number.isFinite(bookmark.time) ||
            bookmark.time < 0
          )
            throw Error();
          bookmarks.push({
            id: createHash("sha256").update(`${user.id}:${index}`).digest("hex"),
            userId: id.parse(user.id),
            itemId: bookmark.libraryItemId,
            content: bookmark,
          });
        }
      } catch {
        errors.push({ table: "users", id: String(user.id), message: "Bookmark has invalid media ownership" });
      }
    }
    const consumed = new Map<Table, Set<string>>();
    const remember = (table: Table, values: string[]) => consumed.set(table, new Set(values));
    remember(
      "users",
      users.map((user) => id.parse(user.id)),
    );
    remember(
      "libraries",
      libraries.map((library) => library.id),
    );
    remember(
      "libraryFolders",
      libraries.flatMap((library) => library.folders.map((folder) => folder.id)),
    );
    remember(
      "libraryItems",
      items.map((item) => item.id),
    );
    remember(
      "books",
      items.filter((item) => item.mediaType === "book").map((item) => id.parse(item.media.id)),
    );
    remember(
      "podcasts",
      items.filter((item) => item.mediaType === "podcast").map((item) => id.parse(item.media.id)),
    );
    remember(
      "podcastEpisodes",
      items.flatMap((item) => item.media.episodes?.map((episode) => episode.id) ?? []),
    );
    remember(
      "authors",
      items.flatMap((item) => item.media.metadata.authors?.map((author) => author.id) ?? []),
    );
    remember(
      "series",
      items.flatMap((item) => item.media.metadata.series?.map((series) => series.id) ?? []),
    );
    for (const [table, target, field] of [
      ["bookAuthors", "authors", "authorId"],
      ["bookSeries", "series", "seriesId"],
    ] as const)
      remember(
        table,
        (rows.get(table) ?? [])
          .filter((row) => {
            const book = id.safeParse(row.bookId);
            const related = id.safeParse(row[field]);
            if (!book.success || !related.success) {
              errors.push({ table, id: String(row.id), message: "Invalid relationship identifiers" });
              return false;
            }
            return consumed.get("books")?.has(book.data) && consumed.get(target)?.has(related.data);
          })
          .map((row) => id.parse(row.id)),
      );
    remember(
      "mediaProgresses",
      progress.map((value) => value.content.id),
    );
    remember(
      "playbackSessions",
      sessions.map((value) => id.parse(value.content.id)),
    );
    for (const [table, values] of rows) {
      const unmapped = values.filter((value) => !consumed.get(table)?.has(id.parse(value.id)));
      if (unmapped.length)
        remainingData.push({
          table,
          rows: unmapped.length,
          recordIds: unmapped.map((value) => id.parse(value.id)),
        });
    }
    const counts = {
      libraries: libraries.length,
      items: items.filter((item) => !item.historyOnly).length,
      files: files.length,
      progress: progress.length,
      sessions: sessions.length,
      bookmarks: bookmarks.length,
      listeningSeconds: sessions.reduce((n, s) => n + seconds.parse(s.content.timeListening), 0),
    };
    source.verify();
    owner(authorize);
    const report = reportSchema.parse({
      digest: source.digest,
      scope: "media",
      canImport: errors.length === 0,
      canCutover: false,
      counts,
      errors,
      remainingData,
      archivedFields,
      notices: [
        "All source rows are retained privately in the migration archive. Listed fields include archival values; settings, lists and external-auth behavior need their migration stages.",
        "Keep the original snapshot, media and installation for rollback. Media files are never moved or changed by import.",
        "Missing files without an original inode receive a stable logical identifier; their unknown size remains unknown and they stay unplayable.",
        "Deleted-book listening history retains original identities in unplayable history-only records. Unknown historical tags and the deleted item's authoritative explicit-content policy fail closed under account restrictions; original session metadata remains archived.",
        "A null source listening measurement retains timeListeningUnavailable and contributes zero to measured totals; the original source row remains archived.",
      ],
    });
    return {
      report,
      users,
      libraries,
      items,
      historical,
      files,
      paths,
      progress,
      sessions,
      bookmarks,
      archive,
    };
  } finally {
    source.close();
  }
}
export async function inspectMedia(input: Input, authorize: () => Account) {
  return (await inventory(input, authorize)).report;
}
export async function commitMedia(input: z.infer<typeof mediaCommitSchema>, authorize: () => Account) {
  owner(authorize);
  const mappingDigest = mapsDigest(input);
  const prior = database()
    .prepare("SELECT content FROM migrations WHERE digest=? AND scope='media'")
    .get(input.expectedDigest);
  if (prior) {
    const completed = completionSchema.parse(JSON.parse(z.string().parse(prior.content)));
    if (completed.mappingDigest !== mappingDigest)
      throw new DomainError(409, "Imported mount mapping differs");
    return completed;
  }
  const loaded = await inventory(input, authorize);
  if (loaded.report.digest !== input.expectedDigest)
    throw new DomainError(409, "Source changed. Inspect it again");
  if (!loaded.report.canImport)
    throw new DomainError(409, "Resolve the media inventory errors before import");
  const result = transaction((db) => {
    owner(authorize);
    if (
      db.prepare("SELECT id FROM catalog_items LIMIT 1").get() ||
      db.prepare("SELECT id FROM libraries LIMIT 1").get()
    )
      throw new DomainError(409, "Media import requires an empty destination catalog");
    for (const library of loaded.libraries)
      db.prepare("INSERT INTO libraries VALUES(?,?)").run(library.id, JSON.stringify(library));
    for (const item of loaded.items)
      db.prepare("INSERT INTO catalog_items VALUES(?,?,?,?)").run(
        item.id,
        item.libraryId,
        z.string().parse(loaded.paths.get(item.id)),
        JSON.stringify(item),
      );
    for (const [itemId, value] of loaded.historical)
      db.prepare("INSERT INTO retired_items VALUES(?,?,?)").run(itemId, value.userId, value.removedAt);
    for (const item of loaded.items)
      db.prepare("INSERT INTO metadata_overrides VALUES(?,?)").run(
        item.id,
        JSON.stringify({ metadata: item.media.metadata, tags: item.media.tags }),
      );
    for (const file of loaded.files)
      db.prepare("INSERT INTO media_files VALUES(?,?,?,?)").run(
        file.id,
        file.itemId,
        file.path,
        JSON.stringify(file.content),
      );
    for (const value of loaded.progress)
      db.prepare("INSERT INTO media_progress VALUES(?,?,?,?,?)").run(
        value.content.id,
        value.userId,
        value.itemId,
        value.episodeId,
        JSON.stringify(value.content),
      );
    for (const value of loaded.sessions)
      db.prepare("INSERT INTO listening_reports VALUES(?,?,?,?,?)").run(
        value.userId,
        id.parse(value.content.id),
        value.itemId,
        value.episodeId,
        JSON.stringify(value.content),
      );
    for (const value of loaded.bookmarks)
      db.prepare("INSERT INTO bookmarks VALUES(?,?,?,?)").run(
        value.id,
        value.userId,
        value.itemId,
        JSON.stringify(value.content),
      );
    for (const row of loaded.archive)
      db.prepare("INSERT INTO migration_archive VALUES(?,?,?,?)").run(
        input.expectedDigest,
        row.table,
        row.key,
        ["settings", "sessions"].includes(row.table) ? sealArchive(JSON.parse(row.content)) : row.content,
      );
    const completed = completionSchema.parse({
      id: randomUUID(),
      digest: input.expectedDigest,
      scope: "media",
      mappingDigest,
      accountCount: loaded.users.length,
      completedAt: Date.now(),
      report: loaded.report,
    });
    db.prepare("INSERT INTO migrations VALUES(?,?,?,?)").run(
      completed.id,
      completed.digest,
      completed.scope,
      JSON.stringify(completed),
    );
    return completed;
  });
  catalogChanged();
  return result;
}
