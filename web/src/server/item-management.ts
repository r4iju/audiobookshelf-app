import "server-only";
import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { mkdir, open, realpath, rename, rm } from "node:fs/promises";
import { basename, extname, resolve } from "node:path";
import { z } from "zod";
import { type metadataEditInput, providerSettingsInput } from "@/lib/abs/item-management";
import { libraryItemSchema } from "@/lib/abs/schemas";
import {
  type Account,
  canReadLibrary,
  canReadMedia,
  DomainError,
  findAccount,
  permissions,
  requireAdministrator,
} from "./accounts";
import { catalogUpload, findLibrary, itemFor, metadataIdentity, mountedPath, within } from "./catalog";
import { catalogChanged, database, dataDirectory, managedMediaDirectory, transaction } from "./data";
import { remoteStream, remoteUrl } from "./remote";

export { metadataEditInput, providerSettingsInput } from "@/lib/abs/item-management";

function authority(actor: Account, permission: "update" | "delete" | "upload") {
  const current = findAccount(actor.id);
  if (!current.active || !permissions.parse(JSON.parse(current.permissions))[permission])
    throw new DomainError(403, `The ${permission} permission is required`);
  return current;
}
export function editMetadata(actor: Account, id: string, input: z.infer<typeof metadataEditInput>) {
  const result = transaction((db) => {
    const current = authority(actor, "update"),
      item = itemFor(current, id);
    const refs = (
      kind: "authors" | "series",
      entries: { id?: string; name: string; sequence?: string | null }[],
    ) =>
      entries.map((entry) => {
        return { ...entry, ...metadataIdentity(kind, entry.name, item.media.metadata[kind] ?? []) };
      });
    const patch = input.metadata ?? {};
    const metadata = {
      ...item.media.metadata,
      ...patch,
      ...(patch.authors
        ? { authors: refs("authors", patch.authors), authorName: patch.authors.map((a) => a.name).join(", ") }
        : {}),
      ...(patch.series ? { series: refs("series", patch.series) } : {}),
    };
    const value = libraryItemSchema.parse({
      ...item,
      updatedAt: Date.now(),
      media: { ...item.media, metadata, tags: input.tags ?? item.media.tags },
    });
    db.prepare("UPDATE catalog_items SET content=? WHERE id=?").run(JSON.stringify(value), id);
    db.prepare(
      "INSERT INTO metadata_overrides VALUES(?,?) ON CONFLICT(item_id) DO UPDATE SET content=excluded.content",
    ).run(id, JSON.stringify({ metadata: value.media.metadata, tags: value.media.tags }));
    return value;
  });
  catalogChanged();
  return result;
}
export function removeCatalogItem(actor: Account, id: string) {
  transaction((db) => {
    const current = authority(actor, "delete");
    itemFor(current, id);
    if (db.prepare("SELECT id FROM podcast_jobs WHERE item_id=? AND state='running'").get(id))
      throw new DomainError(409, "Stop active episode downloads before removing this item");
    db.prepare("INSERT INTO retired_items VALUES(?,?,?)").run(id, current.id, Date.now());
    db.prepare("DELETE FROM rss_feeds WHERE item_id=?").run(id);
    db.prepare("DELETE FROM podcast_subscriptions WHERE item_id=?").run(id);
    db.prepare(
      "UPDATE podcast_jobs SET state='cancelled',lease_until=NULL WHERE item_id=? AND state='queued'",
    ).run(id);
    db.prepare("UPDATE playback_sessions SET active=0 WHERE item_id=?").run(id);
  });
  catalogChanged();
  return { success: true, mediaDeleted: false, historyRetained: true };
}
export function restoreCatalogItem(actor: Account, id: string) {
  const result = transaction((db) => {
    const current = authority(actor, "delete"),
      row = db.prepare("SELECT content FROM catalog_items WHERE id=?").get(id);
    if (!row) throw new DomainError(404, "Not found");
    const item = libraryItemSchema.parse(JSON.parse(z.string().parse(row.content)));
    if (
      !canReadMedia(current, {
        libraryId: item.libraryId,
        explicit: Boolean(item.media.metadata.explicit),
        tags: item.media.tags,
      })
    )
      throw new DomainError(404, "Not found");
    db.prepare("DELETE FROM retired_items WHERE item_id=?").run(id);
    return itemFor(current, id);
  });
  catalogChanged();
  return result;
}
async function bodyBytes(request: Request, max: number) {
  if (!request.body) throw new DomainError(400, "A file body is required");
  const reader = request.body.getReader(),
    chunks: Buffer[] = [];
  let size = 0;
  try {
    const deadline = Date.now() + 20000;
    while (true) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const next = await Promise.race([
        reader.read(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new DomainError(408, "Cover upload timed out")),
            Math.max(1, deadline - Date.now()),
          );
        }),
      ]).finally(() => {
        if (timer) clearTimeout(timer);
      });
      if (next.done) break;
      size += next.value.length;
      if (size > max) throw new DomainError(413, "File exceeds the size limit");
      chunks.push(Buffer.from(next.value));
    }
  } finally {
    await reader.cancel();
  }
  return Buffer.concat(chunks);
}
function imageType(bytes: Buffer) {
  let width = 0,
    height = 0,
    type = "";
  if (
    bytes.length >= 33 &&
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
    bytes.toString("ascii", 12, 16) === "IHDR"
  ) {
    width = bytes.readUInt32BE(16);
    height = bytes.readUInt32BE(20);
    type = "image/png";
  } else if (bytes[0] === 255 && bytes[1] === 216) {
    let offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] !== 255) break;
      const marker = bytes[offset + 1] ?? 0;
      if (marker === 218 || marker === 217) break;
      const length = bytes.readUInt16BE(offset + 2);
      if (length < 2 || offset + length + 2 > bytes.length) break;
      if ([192, 193, 194].includes(marker) && length >= 8) {
        height = bytes.readUInt16BE(offset + 5);
        width = bytes.readUInt16BE(offset + 7);
        type = "image/jpeg";
        break;
      }
      offset += length + 2;
    }
  }
  if (!width || !height || width > 8192 || height > 8192 || width * height > 20000000)
    throw new DomainError(400, "Use a valid PNG or JPEG cover under 20 million pixels");
  return type;
}
let coverUploads = 0;
export async function saveCover(request: Request, authorize: () => Account, id: string) {
  if (coverUploads >= 2) throw new DomainError(503, "Two cover uploads are already running");
  coverUploads++;
  try {
    itemFor(authority(authorize(), "update"), id);
    const bytes = await bodyBytes(request, 5 * 1024 * 1024),
      type = imageType(bytes);
    transaction((db) => {
      const item = itemFor(authority(authorize(), "update"), id);
      db.prepare(
        "INSERT INTO item_covers VALUES(?,?,?) ON CONFLICT(item_id) DO UPDATE SET mime=excluded.mime,bytes=excluded.bytes",
      ).run(id, type, bytes);
      db.prepare("UPDATE catalog_items SET content=? WHERE id=?").run(
        JSON.stringify({
          ...item,
          updatedAt: Date.now(),
          media: { ...item.media, coverPath: `managed:${id}` },
        }),
        id,
      );
    });
    catalogChanged();
    return { success: true };
  } finally {
    coverUploads--;
  }
}
export function cover(request: Request, actor: Account, id: string) {
  itemFor(actor, id);
  const row = database().prepare("SELECT mime,bytes FROM item_covers WHERE item_id=?").get(id);
  if (!row) throw new DomainError(404, "No managed cover is available");
  const bytes = z.instanceof(Uint8Array).parse(row.bytes);
  return new Response(request.method === "HEAD" ? null : bytes, {
    headers: {
      "content-type": z.string().parse(row.mime),
      "content-length": String(bytes.length),
      "cache-control": "private, no-store",
      "x-content-type-options": "nosniff",
    },
  });
}
let uploads = 0;
export async function upload(request: Request, authorize: () => Account, libraryId: string) {
  if (uploads >= 2) throw new DomainError(503, "Two uploads are already running");
  uploads++;
  let staging: string | undefined,
    published: string | undefined,
    handle: Awaited<ReturnType<typeof open>> | undefined;
  let scanId: string | undefined,
    succeeded = false;
  const reader = request.body?.getReader();
  try {
    const actor = authority(authorize(), "upload"),
      library = findLibrary(libraryId);
    if (library.mediaType !== "book" || !canReadLibrary(actor, libraryId))
      throw new DomainError(403, "Choose an accessible book library");
    const filename = z.string().min(1).max(256).parse(new URL(request.url).searchParams.get("filename"));
    if (
      basename(filename) !== filename ||
      filename.includes("\\") ||
      [...filename].some((c) => c.charCodeAt(0) < 32) ||
      ![
        ".mp3",
        ".m4b",
        ".m4a",
        ".flac",
        ".ogg",
        ".opus",
        ".wav",
        ".aac",
        ".epub",
        ".pdf",
        ".mobi",
        ".azw3",
        ".cbz",
        ".cbr",
      ].includes(extname(filename).toLowerCase())
    )
      throw new DomainError(400, "Choose a supported media filename without folders");
    const root = await realpath(managedMediaDirectory());
    const folders = await Promise.all(library.folders.map((f) => mountedPath(f.fullPath)));
    if (!folders.some((f) => within(f, root)))
      throw new DomainError(409, "Add the managed /data/media folder to this library before uploading");
    transaction((db) => {
      authority(authorize(), "upload");
      if (db.prepare("SELECT id FROM scan_runs WHERE library_id=? AND status='running'").get(libraryId))
        throw new DomainError(409, "Wait for the library's current scan or upload");
      scanId = randomUUID();
      db.prepare("INSERT INTO scan_runs VALUES(?,?,'running',?,NULL,NULL)").run(
        scanId,
        libraryId,
        Date.now(),
      );
    });
    const job = randomUUID();
    staging = resolve(dataDirectory(), `upload-${job}`);
    await mkdir(staging, { mode: 0o700 });
    const path = resolve(staging, filename);
    handle = await open(
      path,
      constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_NOFOLLOW,
      0o600,
    );
    const pinned =
      process.platform === "linux" ? await realpath(`/proc/self/fd/${handle.fd}`) : await realpath(path);
    if (!within(await realpath(staging), pinned)) throw new DomainError(400, "Upload storage changed");
    if (!reader) throw new DomainError(400, "Choose a media file");
    const deadline = Date.now() + 600000;
    let size = 0;
    while (true) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) throw new DomainError(408, "Upload time limit exceeded");
      let timer: ReturnType<typeof setTimeout> | undefined;
      const next = await Promise.race([
        reader.read(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => reject(new DomainError(408, "Upload time limit exceeded")), remaining);
        }),
      ]).finally(() => {
        if (timer) clearTimeout(timer);
      });
      if (next.done) break;
      authority(authorize(), "upload");
      size += next.value.length;
      if (size > 1024 * 1024 * 1024) throw new DomainError(413, "Uploads must be at most 1 GiB");
      await handle.writeFile(next.value);
    }
    if (!size) throw new DomainError(400, "The uploaded file is empty");
    await handle.sync();
    await handle.close();
    handle = undefined;
    const current = authority(authorize(), "upload");
    if (
      !canReadLibrary(current, libraryId) ||
      JSON.stringify(findLibrary(libraryId)) !== JSON.stringify(library)
    )
      throw new DomainError(409, "Library or upload authority changed");
    published = resolve(root, `upload-${job}`);
    await rename(staging, published);
    staging = undefined;
    const item = await catalogUpload(libraryId, published, () => authority(authorize(), "upload"));
    published = undefined;
    succeeded = true;
    return { item };
  } finally {
    try {
      await reader?.cancel().catch(() => {});
      await handle?.close();
      if (staging) await rm(staging, { recursive: true, force: true });
      if (published) await rm(published, { recursive: true, force: true });
    } finally {
      if (scanId)
        database()
          .prepare("UPDATE scan_runs SET status=?,completed_at=? WHERE id=?")
          .run(succeeded ? "complete" : "failed", Date.now(), scanId);
      uploads--;
    }
  }
}
const defaults = { enabled: false, searchUrl: "https://openlibrary.org/search.json" };
export function providerSettings(actor: Account) {
  requireAdministrator(actor);
  const row = database().prepare("SELECT content FROM product_settings WHERE key='metadata-provider'").get();
  return row ? providerSettingsInput.parse(JSON.parse(z.string().parse(row.content))) : defaults;
}
export function saveProvider(actor: Account, input: z.infer<typeof providerSettingsInput>) {
  requireAdministrator(actor);
  const url = remoteUrl(input.searchUrl);
  if (
    url.search ||
    (url.protocol !== "https:" &&
      !(process.env.LEAFWAKE_METADATA_ALLOWED_HOSTS ?? "").split(",").includes(url.hostname))
  )
    throw new DomainError(400, "Use an HTTPS provider search endpoint without query parameters");
  database()
    .prepare(
      "INSERT INTO product_settings VALUES('metadata-provider',?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
    )
    .run(JSON.stringify(input));
  return input;
}
let searches = 0,
  lastSearch = 0;
export async function metadataSearch(authorize: () => Account, term: string) {
  const actor = authority(authorize(), "update");
  requireAdministrator(actor);
  const settings = providerSettings(actor);
  if (!settings.enabled) throw new DomainError(409, "Enable the metadata provider in owner settings first");
  if (searches >= 2 || Date.now() - lastSearch < 1000)
    throw new DomainError(429, "Wait before another metadata search");
  const query = z.string().trim().min(1).max(256).parse(term);
  lastSearch = Date.now();
  searches++;
  try {
    const url = new URL(settings.searchUrl);
    url.searchParams.set("q", query);
    url.searchParams.set("limit", "20");
    url.searchParams.set("fields", "key,title,author_name,first_publish_year");
    const response = await remoteStream(url.toString(), 1024 * 1024, AbortSignal.timeout(20000), 0, {
      allowedHosts: process.env.LEAFWAKE_METADATA_ALLOWED_HOSTS ?? "",
    });
    let size = 0;
    const chunks: Buffer[] = [];
    for await (const part of response) {
      const b = Buffer.from(part);
      size += b.length;
      if (size > 1024 * 1024) {
        response.destroy();
        throw new DomainError(400, "Metadata provider response exceeds 1 MiB");
      }
      chunks.push(b);
    }
    requireAdministrator(authority(authorize(), "update"));
    const parsed = z
      .object({
        docs: z
          .array(
            z.object({
              key: z.string().max(256),
              title: z.string().max(256),
              author_name: z.array(z.string().max(256)).max(100).default([]),
              first_publish_year: z.number().int().nullable().optional(),
            }),
          )
          .max(20),
      })
      .parse(JSON.parse(Buffer.concat(chunks).toString("utf8")));
    return {
      results: parsed.docs.map((d) => ({
        key: d.key,
        title: d.title,
        authors: d.author_name,
        publishedYear: d.first_publish_year == null ? null : String(d.first_publish_year),
      })),
    };
  } finally {
    searches--;
  }
}
