import "server-only";
import { createHash, randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { open, realpath } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { z } from "zod";
import {
  type CompleteImportInput,
  type CompleteImportReport,
  completeImportReport,
} from "@/lib/abs/complete-import";
import { libraryItemSchema } from "@/lib/abs/schemas";
import { type Account, DomainError, findAccount } from "./accounts";
import { createBackup } from "./backups";
import { within } from "./catalog";
import { catalogChanged, database, transaction } from "./data";
import { validateFeedAddress } from "./feeds";
import { imageType } from "./item-management";
import { sourceCopy } from "./migration";
import { inventoryJson } from "./migration-json-inventory";
import { openIdInput, prepareOpenIdImport } from "./openid";
import { podcastSettings, podcastSettingsSchema } from "./podcast-settings";
import { serverSettings, serverSettingsSchema } from "./server-settings";

export { completeImportInput } from "@/lib/abs/complete-import";

const scalar = z.union([z.string(), z.number().finite(), z.null()]);
const rowSchema = z.record(z.string(), scalar);
const objectSchema = z.record(z.string(), z.unknown());
const id = z.string().min(1).max(256);
function object(value: unknown) {
  return objectSchema.parse(JSON.parse(z.string().parse(value ?? "{}")));
}
function owner(authorize: () => Account) {
  const actor = findAccount(authorize().id);
  if (!actor.active || actor.type !== "root") throw new DomainError(403, "Owner access required");
  return actor;
}
const common = ["id", "createdAt", "updatedAt"];
// Columns describe source data, not executable legacy behavior. Unrecognized columns never become cutover-safe.
const columns: Record<string, string[]> = {
  users: [
    ...common,
    "username",
    "email",
    "pash",
    "type",
    "token",
    "isActive",
    "isLocked",
    "lastSeen",
    "permissions",
    "bookmarks",
    "extraData",
  ],
  libraries: [...common, "name", "mediaType", "displayOrder", "settings", "icon", "provider"],
  libraryFolders: [...common, "libraryId", "path"],
  libraryItems: [
    ...common,
    "libraryId",
    "libraryFolderId",
    "mediaId",
    "mediaType",
    "path",
    "relPath",
    "ino",
    "isFile",
    "isMissing",
    "isInvalid",
    "libraryFiles",
    "size",
    "mtimeMs",
    "ctimeMs",
    "birthtimeMs",
    "extraData",
    "numFiles",
  ],
  books: [
    ...common,
    "title",
    "subtitle",
    "duration",
    "audioFiles",
    "ebookFile",
    "chapters",
    "tags",
    "genres",
    "narrators",
    "explicit",
    "publishedYear",
    "publishedDate",
    "publisher",
    "description",
    "isbn",
    "asin",
    "language",
    "abridged",
    "coverPath",
    "numTracks",
    "numAudioFiles",
    "size",
    "numChapters",
    "missingParts",
    "numMissingParts",
    "lastCoverSearch",
    "lastCoverSearchQuery",
  ],
  podcasts: [
    ...common,
    "title",
    "author",
    "description",
    "feedURL",
    "imageURL",
    "coverPath",
    "tags",
    "genres",
    "explicit",
    "language",
    "itunesPageUrl",
    "itunesId",
    "itunesArtistId",
    "type",
    "autoDownloadEpisodes",
    "autoDownloadSchedule",
    "lastEpisodeCheck",
    "lastEpisodePubDate",
    "maxEpisodesToKeep",
    "maxNewEpisodesToDownload",
    "numEpisodes",
    "size",
  ],
  podcastEpisodes: [
    ...common,
    "podcastId",
    "title",
    "subtitle",
    "description",
    "enclosure",
    "enclosureURL",
    "pubDate",
    "publishedAt",
    "episode",
    "season",
    "episodeType",
    "audioFile",
    "duration",
    "size",
    "index",
    "chapters",
    "oldEpisodeId",
  ],
  authors: [...common, "name", "description", "asin", "imagePath"],
  series: [...common, "name", "description"],
  bookAuthors: [...common, "bookId", "authorId"],
  bookSeries: [...common, "bookId", "seriesId", "sequence"],
  mediaProgresses: [
    ...common,
    "userId",
    "mediaItemId",
    "mediaItemType",
    "duration",
    "currentTime",
    "isFinished",
    "hideFromContinueListening",
    "ebookLocation",
    "ebookProgress",
    "extraData",
    "finishedAt",
    "startedAt",
  ],
  playbackSessions: [
    ...common,
    "userId",
    "libraryId",
    "mediaItemId",
    "mediaItemType",
    "duration",
    "currentTime",
    "timeListening",
    "startTime",
    "extraData",
    "mediaMetadata",
    "displayTitle",
    "displayAuthor",
    "playMethod",
    "mediaPlayer",
    "serverVersion",
    "chapters",
    "date",
    "dayOfWeek",
  ],
  collections: [...common, "name", "description", "libraryId"],
  collectionBooks: [...common, "collectionId", "bookId", "order"],
  playlists: [...common, "name", "description", "libraryId", "userId"],
  playlistMediaItems: [...common, "playlistId", "mediaItemId", "mediaItemType", "order"],
  feeds: [
    ...common,
    "slug",
    "entityType",
    "entityId",
    "userId",
    "serverAddress",
    "title",
    "ownerName",
    "ownerEmail",
    "preventIndexing",
    "description",
    "coverPath",
    "language",
    "explicit",
    "author",
    "feedUrl",
  ],
  feedEpisodes: [
    ...common,
    "feedId",
    "title",
    "filePath",
    "enclosureURL",
    "enclosureType",
    "enclosureSize",
    "pubDate",
    "duration",
    "description",
  ],
  settings: ["id", "key", "value", "createdAt", "updatedAt"],
};
const archived = new Set([
  "createdAt",
  "updatedAt",
  "email",
  "token",
  "lastSeen",
  "isLocked",
  "icon",
  "provider",
  "relPath",
  "ino",
  "size",
  "mtimeMs",
  "ctimeMs",
  "birthtimeMs",
  "numFiles",
  "numTracks",
  "numAudioFiles",
  "numChapters",
  "missingParts",
  "numMissingParts",
  "lastCoverSearch",
  "lastCoverSearchQuery",
  "displayTitle",
  "displayAuthor",
  "playMethod",
  "mediaPlayer",
  "serverVersion",
  "date",
  "dayOfWeek",
]);
const serverMapped = new Set([
  "id",
  "serverName",
  "language",
  "authLoginCustomMessage",
  "allowedOrigins",
  "rateLimitLoginRequests",
  "rateLimitLoginWindow",
  "podcastEpisodeSchedule",
  "backupSchedule",
  "backupsToKeep",
  "authActiveAuthMethods",
  "authOpenIDIssuerURL",
  "authOpenIDClientID",
  "authOpenIDClientSecret",
  "authOpenIDAutoRegister",
  "authOpenIDAutoLaunch",
  "authOpenIDButtonText",
  "authOpenIDMobileRedirectURIs",
]);
const retiredServer = new Set([
  "tokenSecret",
  "version",
  "buildNumber",
  "logLevel",
  "loggerDailyLogsToKeep",
  "loggerScannerLogsToKeep",
  "backupPath",
  "maxBackupSize",
  "homeBookshelfView",
  "bookshelfView",
  "dateFormat",
  "timeFormat",
  "scannerDisableWatcher",
  "storeCoverWithItem",
  "storeMetadataWithItem",
  "metadataFileFormat",
  "scannerCoverProvider",
]);
const defaultOnly: Record<string, unknown> = {
  scannerParseSubtitle: false,
  scannerFindCovers: false,
  scannerPreferMatchedMetadata: false,
  allowIframe: false,
  sortingIgnorePrefix: false,
  sortingPrefixes: ["the", "a"],
  chromecastEnabled: false,
  authOpenIDAuthorizationURL: null,
  authOpenIDTokenURL: null,
  authOpenIDUserInfoURL: null,
  authOpenIDJwksURL: null,
  authOpenIDLogoutURL: null,
  authOpenIDTokenSigningAlgorithm: "RS256",
  authOpenIDMatchExistingBy: null,
  authOpenIDGroupClaim: "",
  authOpenIDAdvancedPermsClaim: "",
  authOpenIDSubfolderForRedirectURLs: null,
};
function fingerprint(input: CompleteImportInput) {
  return createHash("sha256").update(JSON.stringify(input)).digest("hex");
}
let preparations = 0;
async function inventory(input: CompleteImportInput, authorize: () => Account) {
  owner(authorize);
  if (preparations) throw new DomainError(503, "A migration inventory is already running");
  preparations++;
  let source: ReturnType<typeof sourceCopy> | undefined;
  try {
    const db = database();
    for (const scope of ["accounts", "media", "lists", "delivery"])
      if (!db.prepare("SELECT id FROM migrations WHERE digest=? AND scope=?").get(input.digest, scope))
        throw new DomainError(
          409,
          "Complete accounts, media, lists and delivery from the same snapshot first",
        );
    source = sourceCopy(input.sourcePath);
    if (source.digest !== input.digest)
      throw new DomainError(409, "The source snapshot digest does not match the imported installation");
    const base = validateFeedAddress(input.publicUrl);
    const deliveryReceipt = db
      .prepare("SELECT content FROM migrations WHERE digest=? AND scope='delivery'")
      .get(input.digest);
    const delivered = z
      .object({ serverAddress: z.string() })
      .parse(JSON.parse(z.string().parse(deliveryReceipt?.content)));
    if (delivered.serverAddress !== base)
      throw new DomainError(409, "Use the same replacement URL as the delivery migration");
    const errors: CompleteImportReport["errors"] = [],
      unsupported: CompleteImportReport["unsupported"] = [],
      tables = new Map<string, z.infer<typeof rowSchema>[]>(),
      tableInventory: CompleteImportReport["inventory"] = [];
    let sourceRows = 0;
    for (const entry of source.db
      .prepare(
        "SELECT name,type FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND type IN ('table','view','trigger') ORDER BY name",
      )
      .all()) {
      const name = z
        .string()
        .regex(/^[A-Za-z][A-Za-z0-9_]*$/)
        .parse(entry.name);
      if (entry.type !== "table") {
        unsupported.push({
          table: name,
          fields: [],
          reason: "Executable source views and triggers are not imported",
        });
        continue;
      }
      const count = Number(source.db.prepare(`SELECT COUNT(*) AS n FROM "${name}"`).get()?.n);
      sourceRows += count;
      if (count > 100000 || sourceRows > 500000)
        throw new DomainError(400, "The source inventory exceeds the supported row limit");
      const fields = source.db
        .prepare(`PRAGMA table_info("${name}")`)
        .all()
        .map((c) => String(c.name));
      const known = columns[name];
      tableInventory.push({
        table: name,
        rows: count,
        disposition: known ? "mapped" : "unsupported",
        fields: fields.map((field) => ({
          name: field,
          disposition: !known?.includes(field) ? "unsupported" : archived.has(field) ? "archived" : "mapped",
        })),
      });
      if (!known) {
        if (count)
          unsupported.push({
            table: name,
            fields,
            reason: "No supported migration exists for this source table",
          });
        continue;
      }
      const unknown = fields.filter((f) => !known.includes(f));
      if (unknown.length && count)
        unsupported.push({
          table: name,
          fields: unknown,
          reason: "Unrecognized source columns remain in the private archive",
        });
      tables.set(
        name,
        source.db
          .prepare(`SELECT * FROM "${name}"`)
          .all()
          .map((row) => rowSchema.parse(row)),
      );
    }
    for (const entry of tableInventory)
      inventoryJson(entry.table, tables.get(entry.table) ?? [], entry, unsupported);
    const mediaReceipt = db
      .prepare("SELECT content FROM migrations WHERE digest=? AND scope='media'")
      .get(input.digest);
    const mediaReport = z
      .object({
        report: z.object({
          remainingData: z.array(
            z.object({ table: z.string(), rows: z.number(), recordIds: z.array(z.string()).optional() }),
          ),
        }),
      })
      .parse(JSON.parse(z.string().parse(mediaReceipt?.content)));
    for (const remaining of mediaReport.report.remainingData) {
      if (
        [
          "users",
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
        ].includes(remaining.table) &&
        remaining.rows
      )
        unsupported.push({
          table: remaining.table,
          fields: [],
          reason: "Source records have no mapped destination relationship",
        });
    }
    for (const scope of ["lists", "delivery"]) {
      const receipt = db
        .prepare("SELECT content FROM migrations WHERE digest=? AND scope=?")
        .get(input.digest, scope);
      const previous = z
        .object({
          report: z.object({
            unsupported: z.array(
              z.object({ table: z.string(), id: z.string(), fields: z.array(z.string()) }),
            ),
          }),
        })
        .parse(JSON.parse(z.string().parse(receipt?.content)));
      for (const entry of previous.report.unsupported) {
        const fields = entry.fields.filter((field) => !archived.has(field));
        if (fields.length)
          unsupported.push({
            ...entry,
            fields,
            reason: "The earlier migration stage archived these fields without replacement behavior",
          });
      }
    }
    for (const row of tables.get("libraries") ?? []) {
      const librarySettings = object(row.settings);
      for (const [key, value] of Object.entries(librarySettings)) {
        if (key === "coverAspectRatio" || key === "disableWatcher" || key === "metadataPrecedence") continue;
        const defaults: Record<string, unknown> = {
          autoScanCronExpression: null,
          skipMatchingMediaWithAsin: false,
          skipMatchingMediaWithIsbn: false,
          audiobooksOnly: false,
          epubsAllowScriptedContent: false,
          hideSingleBookSeries: false,
          onlyShowLaterBooksInContinueSeries: false,
          markAsFinishedPercentComplete: null,
          markAsFinishedTimeRemaining: 10,
          podcastSearchRegion: "us",
        };
        if (key in defaults && JSON.stringify(value) === JSON.stringify(defaults[key])) continue;
        unsupported.push({
          table: "libraries",
          id: String(row.id),
          fields: [`settings.${key}`],
          reason: "This active library setting is not supported by the replacement",
        });
      }
    }
    for (const row of tables.get("podcasts") ?? []) {
      for (const field of ["autoDownloadSchedule", "maxEpisodesToKeep", "maxNewEpisodesToDownload"]) {
        const value = row[field];
        if (
          value === undefined ||
          value === null ||
          (field === "autoDownloadSchedule" && value === "0 * * * *") ||
          (field !== "autoDownloadSchedule" && value === 0)
        )
          continue;
        unsupported.push({
          table: "podcasts",
          id: String(row.id),
          fields: [field],
          reason: "This per-podcast schedule or limit has no exact persisted replacement",
        });
      }
    }
    for (const row of tables.get("users") ?? []) {
      const extra = object(row.extraData);
      for (const [key, value] of Object.entries(extra)) {
        if (key === "authOpenIDSub") continue;
        if (key === "seriesHideFromContinueListening" && Array.isArray(value) && !value.length) continue;
        unsupported.push({
          table: "users",
          id: String(row.id),
          fields: [`extraData.${key}`],
          reason: "This account extension has no validated replacement behavior",
        });
      }
    }
    const settingsRows = tables.get("settings") ?? [],
      configuration = new Map<string, unknown>();
    let settings: Record<string, unknown> = {};
    for (const row of settingsRows) {
      const value = object(row.value),
        key = String(row.key ?? row.id ?? value.id);
      if (key === "server-settings") {
        if (Object.keys(settings).length)
          errors.push({ table: "settings", id: key, message: "Duplicate server settings" });
        settings = value;
      } else if (key === "email-settings") {
        const devices = z.array(z.record(z.string(), z.unknown())).parse(value.ereaderDevices ?? []);
        for (const device of devices) {
          const fields = Object.keys(device).filter(
            (field) => !["name", "email", "availabilityOption", "users"].includes(field),
          );
          if (fields.length)
            unsupported.push({
              table: "settings",
              id: key,
              fields: fields.map((field) => `ereaderDevices[].${field}`),
              reason: "Unrecognized nested delivery configuration has no replacement behavior",
            });
        }
      } else
        unsupported.push({
          table: "settings",
          id: key,
          fields: Object.keys(value),
          reason: "This source configuration has no replacement behavior",
        });
    }
    for (const [key, value] of Object.entries(settings))
      if (
        !serverMapped.has(key) &&
        !retiredServer.has(key) &&
        !(key in defaultOnly && JSON.stringify(value ?? null) === JSON.stringify(defaultOnly[key]))
      )
        unsupported.push({
          table: "settings",
          id: "server-settings",
          fields: [key],
          reason: "This active setting has no validated replacement behavior",
        });
    const server = serverSettingsSchema.parse({
      ...serverSettings(),
      ...(settings.serverName === undefined ? {} : { serverName: settings.serverName }),
      ...(settings.language === undefined ? {} : { language: settings.language }),
      ...(settings.authLoginCustomMessage == null ? {} : { loginMessage: settings.authLoginCustomMessage }),
      ...(settings.allowedOrigins === undefined ? {} : { allowedOrigins: settings.allowedOrigins }),
      ...(settings.rateLimitLoginRequests === undefined
        ? {}
        : { rateLimitLoginRequests: Number(settings.rateLimitLoginRequests) }),
      ...(settings.rateLimitLoginWindow === undefined
        ? {}
        : { rateLimitLoginWindow: Number(settings.rateLimitLoginWindow) }),
    });
    if (Object.keys(settings).length) configuration.set("server", server);
    if (settings.podcastEpisodeSchedule !== undefined) {
      if (settings.podcastEpisodeSchedule !== "0 * * * *")
        unsupported.push({
          table: "settings",
          id: "server-settings",
          fields: ["podcastEpisodeSchedule"],
          reason: "Only the original hourly schedule maps exactly to the persisted interval scheduler",
        });
      else
        configuration.set(
          "podcasts",
          podcastSettingsSchema.parse({ ...podcastSettings(), updateIntervalMinutes: 60 }),
        );
    }
    if (settings.backupSchedule !== undefined) {
      if (settings.backupSchedule !== false)
        unsupported.push({
          table: "settings",
          id: "server-settings",
          fields: ["backupSchedule"],
          reason: "An active cron backup schedule requires explicit interval configuration after rehearsal",
        });
      else
        configuration.set("backup_configuration", {
          enabled: false,
          intervalMinutes: 1440,
          keepLast: z
            .number()
            .int()
            .min(1)
            .max(50)
            .parse(settings.backupsToKeep ?? 2),
        });
    }
    const methods = z.array(z.enum(["local", "openid"])).parse(settings.authActiveAuthMethods ?? ["local"]);
    if (!methods.includes("local"))
      unsupported.push({
        table: "settings",
        id: "server-settings",
        fields: ["authActiveAuthMethods"],
        reason: "Local recovery-owner sign-in must remain available in the replacement",
      });
    const subjects = (tables.get("users") ?? []).flatMap((row) => {
      const extra = object(row.extraData);
      if (!extra.authOpenIDSub) return [];
      return [{ userId: id.parse(row.id), subject: z.string().min(1).max(1024).parse(extra.authOpenIDSub) }];
    });
    let openId: Awaited<ReturnType<typeof prepareOpenIdImport>> | null = null;
    if (methods.includes("openid") || subjects.length) {
      const callbacks = z.array(z.string()).parse(settings.authOpenIDMobileRedirectURIs ?? []);
      if (callbacks.some((callback) => !input.redirectUris.includes(callback)))
        errors.push({
          table: "settings",
          id: "server-settings",
          message: "Keep every original exact native OpenID callback in the replacement callback list",
        });
      if (!methods.includes("openid"))
        errors.push({
          table: "settings",
          id: "server-settings",
          message: "Linked source OpenID identities require an enabled original provider",
        });
      if (new Set(subjects.map((v) => v.subject)).size !== subjects.length)
        errors.push({
          table: "users",
          message: "Duplicate original OpenID subjects cannot be linked safely",
        });
      const prepared = openIdInput.parse({
        enabled: true,
        issuer: settings.authOpenIDIssuerURL,
        publicUrl: input.publicUrl,
        clientId: settings.authOpenIDClientID,
        clientSecret: settings.authOpenIDClientSecret ?? "",
        redirectUris: input.redirectUris,
        allowRegistration: settings.authOpenIDAutoRegister ?? false,
        autoLaunch: settings.authOpenIDAutoLaunch ?? false,
        buttonText: settings.authOpenIDButtonText ?? "OpenID sign-in",
      });
      openId = await prepareOpenIdImport(prepared);
      owner(authorize);
      source.verify();
      if (!openId.issuer) throw new DomainError(409, "The original provider issuer could not be validated");
      for (const identity of subjects) {
        findAccount(identity.userId);
        if (
          db
            .prepare("SELECT user_id FROM openid_identities WHERE issuer=? AND subject=?")
            .get(openId.issuer, identity.subject)
        )
          errors.push({
            table: "users",
            id: identity.userId,
            message: "Destination OpenID identity already exists",
          });
      }
      if (db.prepare("SELECT key FROM product_settings WHERE key='openid'").get())
        errors.push({
          table: "settings",
          id: "server-settings",
          message: "Destination OpenID settings already exist",
        });
    }
    for (const key of configuration.keys())
      if (db.prepare("SELECT key FROM product_settings WHERE key=?").get(key))
        errors.push({ table: "settings", id: key, message: "Destination configuration already exists" });
    const mappedRoots = await Promise.all(
      input.coverMappings.map(async (mapping) => {
        if (!isAbsolute(mapping.from) || !isAbsolute(mapping.to))
          throw new DomainError(400, "Cover mount mappings must be absolute");
        const roots = (process.env.LEAFWAKE_IMPORT_ROOTS ?? "/imports")
          .split(":")
          .filter(Boolean)
          .concat((process.env.LEAFWAKE_MEDIA_ROOTS ?? "/media").split(":").filter(Boolean));
        const path = resolve(mapping.to);
        if (
          (await realpath(path)) !== path ||
          !(
            await Promise.all(
              roots.map(async (root) => {
                try {
                  return within(await realpath(resolve(root)), path);
                } catch {
                  return false;
                }
              }),
            )
          ).some(Boolean)
        )
          throw new DomainError(
            400,
            "Cover mounts must be real folders inside configured read-only import or media roots",
          );
        return { from: resolve(mapping.from), to: path };
      }),
    );
    owner(authorize);
    source.verify();
    const covers: { itemId: string; bytes: Buffer; mime: string; digest: string }[] = [];
    let coverBytes = 0;
    for (const table of ["books", "podcasts"]) {
      for (const row of tables.get(table) ?? []) {
        if (!row.coverPath) continue;
        const libraryItem = (tables.get("libraryItems") ?? []).find((item) => item.mediaId === row.id);
        if (!libraryItem) {
          errors.push({ table, id: String(row.id), message: "Cover belongs to unmapped media" });
          continue;
        }
        const itemId = id.parse(libraryItem.id);
        if (db.prepare("SELECT item_id FROM item_covers WHERE item_id=?").get(itemId)) {
          errors.push({ table, id: String(row.id), message: "Destination cover already exists" });
          continue;
        }
        let file: Awaited<ReturnType<typeof open>> | undefined;
        try {
          const original = z.string().parse(row.coverPath);
          if (!isAbsolute(original)) throw new Error();
          const matches = mappedRoots
            .filter((root) => within(root.from, resolve(original)))
            .sort((a, b) => b.from.length - a.from.length);
          const mapping = matches[0];
          if (!mapping) throw new Error();
          const path = resolve(mapping.to, resolve(original).slice(mapping.from.length).replace(/^\//, ""));
          if (!within(mapping.to, path) || (await realpath(path)) !== path) throw new Error();
          file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
          const before = await file.stat();
          if (
            !before.isFile() ||
            before.size > 5 * 1024 * 1024 ||
            covers.length >= 1000 ||
            coverBytes + before.size > 128 * 1024 * 1024
          )
            throw new Error();
          if (process.platform !== "linux" || (await realpath(`/proc/self/fd/${file.fd}`)) !== path)
            throw new Error();
          const bytes = await file.readFile(),
            after = await file.stat();
          if (
            before.size !== after.size ||
            before.mtimeMs !== after.mtimeMs ||
            before.ctimeMs !== after.ctimeMs ||
            bytes.length !== before.size ||
            (process.platform === "linux" && (await realpath(`/proc/self/fd/${file.fd}`)) !== path)
          )
            throw new Error();
          covers.push({
            itemId,
            bytes,
            mime: imageType(bytes),
            digest: createHash("sha256").update(bytes).digest("hex"),
          });
          coverBytes += bytes.length;
        } catch {
          errors.push({
            table,
            id: String(row.id),
            message: "Map an unchanged PNG or JPEG cover file inside the configured source mounts",
          });
        } finally {
          await file?.close();
        }
        owner(authorize);
        source.verify();
      }
    }
    for (const row of tables.get("authors") ?? [])
      if (row.imagePath)
        unsupported.push({
          table: "authors",
          id: String(row.id),
          fields: ["imagePath"],
          reason:
            "Author portrait delivery is not supported; the original file must remain available for rollback",
        });
    // Field-specific source settings are disclosed even when retired; their private values are never returned.
    for (const row of tableInventory)
      if (row.table === "settings")
        for (const key of Object.keys(settings))
          row.fields.push({
            name: `server-settings.${key}`,
            disposition: serverMapped.has(key)
              ? "mapped"
              : retiredServer.has(key) || key in defaultOnly
                ? "archived"
                : "unsupported",
          });
    source.verify();
    owner(authorize);
    const report = completeImportReport.parse({
      digest: input.digest,
      scope: "complete",
      canImport: errors.length === 0 && unsupported.length === 0,
      canCutover: errors.length === 0 && unsupported.length === 0,
      counts: {
        openIdIdentities: subjects.length,
        covers: covers.length,
        configuration: configuration.size + (openId ? 1 : 0),
        sourceRows,
      },
      inventory: tableInventory,
      errors,
      unsupported,
      notices: [
        "Original IDs, account roles, passwords, progress, history, lists and published-feed relations are preserved by the prior stages. OpenID links use the validated original issuer and subject; names and emails never create links.",
        "Imported covers are copied into private SQLite storage. Original database and media remain read-only and unchanged. Keep original media and this snapshot for rollback.",
        "Legacy token secrets and sign-in sessions are retired. Leafwake issues new sign-ins. Legacy file-writing/scanner-watcher options are replaced by bounded explicit scans and managed metadata; originals remain in the private archive.",
        "Legacy log levels and file retention are retired in favor of sanitized container logs and bounded product diagnostics. Configure container log rotation outside the image.",
        "Every unsupported table, field or active setting blocks full cutover. Archive retention alone does not claim feature migration.",
      ],
    });
    return { report, configuration, openId, subjects, covers };
  } finally {
    source?.close();
    preparations--;
  }
}
export async function inspectComplete(input: CompleteImportInput, authorize: () => Account) {
  return (await inventory(input, authorize)).report;
}
export async function commitComplete(input: CompleteImportInput, authorize: () => Account) {
  owner(authorize);
  const db = database(),
    prior = db
      .prepare("SELECT content FROM migrations WHERE digest=? AND scope='complete'")
      .get(input.digest),
    mappingDigest = fingerprint(input);
  if (prior) {
    const value = z
      .object({ mappingDigest: z.string(), report: completeImportReport })
      .passthrough()
      .parse(JSON.parse(z.string().parse(prior.content)));
    if (value.mappingDigest !== mappingDigest)
      throw new DomainError(409, "Complete migration used different source, cover or callback mappings");
    return value;
  }
  const prepared = await inventory(input, authorize);
  if (!prepared.report.canCutover)
    throw new DomainError(409, "Resolve every unsupported datum and migration error before full cutover");
  const rollbackBackup = await createBackup(owner(authorize), authorize);
  const pinned = sourceCopy(input.sourcePath);
  try {
    if (pinned.digest !== input.digest) throw new DomainError(409, "Source snapshot changed before commit");
    const result = transaction((db) => {
      const actor = owner(authorize);
      for (const [key, value] of prepared.configuration) {
        if (db.prepare("SELECT key FROM product_settings WHERE key=?").get(key))
          throw new DomainError(409, "Destination configuration changed during inventory");
        db.prepare("INSERT INTO product_settings VALUES(?,?)").run(key, JSON.stringify(value));
      }
      if (prepared.openId) {
        if (db.prepare("SELECT key FROM product_settings WHERE key='openid'").get())
          throw new DomainError(409, "Destination OpenID settings changed during inventory");
        db.prepare("INSERT INTO product_settings VALUES('openid',?)").run(prepared.openId.content);
        for (const identity of prepared.subjects)
          db.prepare("INSERT INTO openid_identities VALUES(?,?,?)").run(
            prepared.openId.issuer,
            identity.subject,
            identity.userId,
          );
      }
      for (const cover of prepared.covers) {
        const row = db.prepare("SELECT content FROM catalog_items WHERE id=?").get(cover.itemId);
        if (!row || db.prepare("SELECT item_id FROM item_covers WHERE item_id=?").get(cover.itemId))
          throw new DomainError(409, "Destination cover changed during inventory");
        const item = libraryItemSchema.parse(JSON.parse(z.string().parse(row.content)));
        db.prepare("INSERT INTO item_covers VALUES(?,?,?)").run(cover.itemId, cover.mime, cover.bytes);
        item.media.coverPath = `managed:${cover.itemId}`;
        db.prepare("UPDATE catalog_items SET content=? WHERE id=?").run(JSON.stringify(item), item.id);
      }
      for (const row of db.prepare("SELECT content FROM catalog_items").all()) {
        const item = libraryItemSchema.parse(JSON.parse(z.string().parse(row.content)));
        if (item.mediaType === "podcast" && item.media.autoDownloadEpisodes)
          db.prepare(
            "INSERT INTO podcast_subscriptions VALUES(?,?,?,NULL,NULL,NULL) ON CONFLICT(item_id) DO NOTHING",
          ).run(item.id, actor.id, Date.now() + podcastSettings().updateIntervalMinutes * 60000);
      }
      pinned.verify();
      const value = {
        id: randomUUID(),
        digest: input.digest,
        scope: "complete",
        accountCount: prepared.subjects.length,
        completedAt: Date.now(),
        mappingDigest,
        rollbackBackupId: rollbackBackup.id,
        report: prepared.report,
      };
      db.prepare("INSERT INTO migrations VALUES(?,?,?,?)").run(
        value.id,
        input.digest,
        "complete",
        JSON.stringify(value),
      );
      return value;
    });
    catalogChanged();
    return result;
  } finally {
    pinned.close();
  }
}
