import "server-only";
import { z } from "zod";
import type { CompleteImportReport } from "@/lib/abs/complete-import";

const file = [
  "ino",
  "metadata",
  "fileType",
  "isSupplementary",
  "addedAt",
  "updatedAt",
  "ebookFormat",
  "mimeType",
  "duration",
  "index",
  "exclude",
  "error",
  "invalid",
  "format",
  "bitRate",
  "codec",
  "timeBase",
  "channels",
  "channelLayout",
  "sampleRate",
  "chapters",
  "embeddedCoverArt",
  "metaTags",
  "trackNumFromMeta",
  "trackNumFromFilename",
  "discNumFromMeta",
  "discNumFromFilename",
  "isManualDuration",
  "isManualIndex",
  "language",
  "manuallyVerified",
];
const metadata = [
  "filename",
  "ext",
  "path",
  "relPath",
  "size",
  "mtimeMs",
  "ctimeMs",
  "birthtimeMs",
  "format",
];
const chapter = ["id", "start", "end", "title"];
const bookMetadata = [
  "title",
  "subtitle",
  "authors",
  "authorName",
  "authorNameLF",
  "series",
  "narrators",
  "genres",
  "publishedYear",
  "publishedDate",
  "publisher",
  "description",
  "isbn",
  "asin",
  "language",
  "explicit",
  "abridged",
  "author",
  "feedUrl",
];
// Paths use [] for array members. Unknown nested keys are never treated as migrated merely because their column is known.
const rules: Record<string, Record<string, readonly string[]>> = {
  users: {
    permissions: [
      "download",
      "update",
      "delete",
      "upload",
      "createEreader",
      "accessExplicitContent",
      "accessAllLibraries",
      "accessAllTags",
      "selectedTagsNotAccessible",
      "librariesAccessible",
      "itemTagsSelected",
    ],
    bookmarks: ["libraryItemId", "title", "time", "createdAt"],
    extraData: ["authOpenIDSub", "seriesHideFromContinueListening"],
  },
  libraries: {
    extraData: ["lastScanMetadataPrecedence"],
    settings: [
      "coverAspectRatio",
      "disableWatcher",
      "metadataPrecedence",
      "autoScanCronExpression",
      "skipMatchingMediaWithAsin",
      "skipMatchingMediaWithIsbn",
      "audiobooksOnly",
      "epubsAllowScriptedContent",
      "hideSingleBookSeries",
      "onlyShowLaterBooksInContinueSeries",
      "markAsFinishedPercentComplete",
      "markAsFinishedTimeRemaining",
      "podcastSearchRegion",
    ],
  },
  libraryItems: { extraData: [], libraryFiles: file, "libraryFiles[].metadata": metadata },
  books: {
    audioFiles: file,
    "audioFiles[].metadata": metadata,
    "audioFiles[].chapters": chapter,
    "audioFiles[].metaTags": [
      "tagAlbum",
      "tagArtist",
      "tagGenre",
      "tagTitle",
      "tagSeries",
      "tagSeriesPart",
      "tagTrack",
      "tagDisc",
      "tagSubtitle",
      "tagAlbumArtist",
      "tagDate",
      "tagComposer",
      "tagPublisher",
      "tagDescription",
      "tagComment",
      "tagLanguage",
      "tagASIN",
      "tagISBN",
      "tagEncoder",
    ],
    ebookFile: file,
    "ebookFile.metadata": metadata,
    chapters: chapter,
  },
  podcasts: {},
  podcastEpisodes: {
    audioFile: file,
    "audioFile.metadata": metadata,
    "audioFile.chapters": chapter,
    enclosure: ["url", "type", "length"],
    chapters: chapter,
  },
  mediaProgresses: { extraData: ["libraryItemId", "episodeId", "progress"] },
  playbackSessions: {
    chapters: chapter,
    extraData: ["libraryItemId", "episodeId"],
    mediaMetadata: bookMetadata,
    "mediaMetadata.authors": ["id", "name"],
    "mediaMetadata.series": ["id", "name", "sequence"],
  },
  devices: { extraData: ["browserName", "manufacturer", "model", "osName", "osVersion"] },
};
const archivePaths = new Set([
  "books.audioFiles[].language",
  "books.audioFiles[].manuallyVerified",
  "books.audioFiles[].metaTags.tagEncoder",
]);
const parsedJson = z.union([z.array(z.unknown()), z.record(z.string(), z.unknown()), z.null()]);
export function inventoryJson(
  table: string,
  rows: Record<string, string | number | null>[],
  inventory: CompleteImportReport["inventory"][number],
  unsupported: CompleteImportReport["unsupported"],
) {
  const tableRules = rules[table];
  if (!tableRules) return;
  const paths = new Map<string, "mapped" | "archived" | "unsupported">();
  for (const row of rows) {
    const missing = new Set<string>();
    const visit = (value: unknown, path: string, depth = 0) => {
      if (depth > 64 || paths.size > 10000) throw new Error("Nested inventory exceeds limits");
      if (Array.isArray(value)) {
        for (const member of value) visit(member, path + "[]", depth + 1);
        return;
      }
      if (value === null || typeof value !== "object") return;
      const allowed = tableRules[path] ?? tableRules[path.replace(/\[\]$/u, "")];
      for (const [key, child] of Object.entries(value)) {
        const name = path + "." + key,
          known = allowed?.includes(key) ?? false;
        paths.set(
          name,
          known
            ? table === "devices" ||
              (table === "libraries" && name.startsWith("extraData.")) ||
              archivePaths.has(`${table}.${name}`)
              ? "archived"
              : "mapped"
            : "unsupported",
        );
        if (!known) missing.add(name);
        visit(child, name, depth + 1);
      }
    };
    for (const column of Object.keys(tableRules).filter((path) => !path.includes("."))) {
      const value = row[column];
      if (value === null || value === undefined || value === "") continue;
      try {
        visit(parsedJson.parse(JSON.parse(z.string().parse(value))), column);
      } catch {
        missing.add(column);
      }
    }
    if (missing.size)
      unsupported.push({
        table,
        id: String(row.id ?? ""),
        fields: [...missing].sort(),
        reason: "Unrecognized nested source data has no validated replacement behavior",
      });
  }
  for (const [name, disposition] of paths) inventory.fields.push({ name, disposition });
}
