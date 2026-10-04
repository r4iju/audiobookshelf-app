import { retainEpisodes, subscribe } from "./podcast-schedules";
import { podcastSettings } from "./podcast-settings";
import "server-only";
import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { createWriteStream } from "node:fs";
import { lstat, mkdir, realpath, rename, rm } from "node:fs/promises";
import { basename, dirname, extname, resolve } from "node:path";
import { Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import { XMLParser, XMLValidator } from "fast-xml-parser";
import { z } from "zod";
import { libraryItemSchema, podcastEpisodeSchema, podcastFeedSchema } from "@/lib/abs/schemas";
import { type Account, canReadLibrary, DomainError, findAccount, permissions } from "./accounts";
import { findLibrary, itemFor, itemsFor, mountedPath, within } from "./catalog";
import { catalogChanged, database, managedMediaDirectory, transaction } from "./data";
import { listsChanged, storedSchema } from "./lists";
import { remoteStream, remoteText, remoteUrl } from "./remote";

const episodeInput = z.object({
  title: z.string().max(4096).nullish(),
  description: z.string().max(65536).nullish(),
  guid: z.string().max(4096).nullish(),
  publishedAt: z.number().finite().nullish(),
  duration: z.union([z.string().max(64), z.number().finite()]).nullish(),
  enclosure: z.object({ url: z.string().max(4096), type: z.string().max(128).optional() }),
});
export const episodesInput = z.array(episodeInput).min(1).max(5000);
export const feedInput = z.object({ rssFeed: z.string().max(4096) });
export const newPodcastSchema = z.object({
  libraryId: z.string(),
  folderId: z.string(),
  path: z.string().max(4096),
  media: z.object({
    metadata: podcastFeedSchema.shape.podcast.shape.metadata,
    autoDownloadEpisodes: z.boolean().default(false),
  }),
});
const jobSchema = z.object({
  id: z.string(),
  item_id: z.string(),
  episode_key: z.string(),
  user_id: z.string(),
  state: z.enum(["queued", "running", "complete", "failed", "cancelled"]),
  attempts: z.number(),
  lease_until: z.number().nullable(),
  content: z.string(),
  updated_at: z.number(),
});
type Job = z.infer<typeof jobSchema>;
function writable(actor: Account, itemId?: string) {
  if (!actor.active || !permissions.parse(JSON.parse(actor.permissions)).update)
    throw new DomainError(403, "Podcast changes require update permission");
  if (itemId) itemFor(actor, itemId);
}
function object(value: unknown) {
  return z.record(z.string(), z.unknown()).parse(value);
}
function text(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string" || typeof value === "number") return String(value);
  return text(object(value)["#text"]);
}
function array(value: unknown) {
  return value == null ? [] : Array.isArray(value) ? value : [value];
}
export async function readFeed(value: string) {
  remoteUrl(value);
  const xml = await remoteText(value);
  if (/<!\s*(DOCTYPE|ENTITY)/i.test(xml) || (xml.match(/</g)?.length ?? 0) > 100000)
    throw new DomainError(400, "Unsupported feed declarations or size");
  let depth = 0;
  for (const tag of xml.matchAll(/<\/?([\w:.-]+)[^>]*>/g)) {
    if (tag[0].startsWith("</")) depth--;
    else if (!tag[0].endsWith("/>")) depth++;
    if (depth > 64) throw new DomainError(400, "Feed nesting limit exceeded");
  }
  if (XMLValidator.validate(xml) !== true) throw new DomainError(400, "Invalid feed XML");
  const parsed = object(
    new XMLParser({ ignoreAttributes: false, parseTagValue: false, processEntities: true }).parse(xml),
  );
  const atom = parsed.feed != null;
  const channel = atom ? object(parsed.feed) : object(object(parsed.rss).channel);
  const episodes = array(atom ? channel.entry : channel.item)
    .map((raw) => {
      const item = object(raw);
      const enclosure = atom
        ? array(item.link)
            .map(object)
            .find((l) => l["@_rel"] === "enclosure")
        : item.enclosure
          ? object(item.enclosure)
          : null;
      if (!enclosure) return null;
      const url = text(enclosure[atom ? "@_href" : "@_url"]);
      remoteUrl(url);
      const published = Date.parse(text(item.pubDate ?? item.published ?? item.updated));
      return {
        title: text(item.title),
        description: text(item.description ?? item.summary ?? item.content),
        guid: text(item.guid ?? item.id) || url,
        publishedAt: Number.isFinite(published) ? published : null,
        duration: text(item["itunes:duration"]) || null,
        enclosure: { url, type: text(enclosure["@_type"]) },
      };
    })
    .filter((episode) => episode !== null);
  if (episodes.length > 5000) throw new DomainError(400, "Feed episode limit exceeded");
  return podcastFeedSchema.parse({
    podcast: {
      metadata: {
        title: text(channel.title),
        author: text(
          channel["itunes:author"] ?? (atom && channel.author ? object(channel.author).name : null),
        ),
        description: text(channel.description ?? channel.subtitle),
        descriptionPlain: text(channel.description ?? channel.subtitle).replace(/<[^>]*>/g, ""),
        categories: array(channel["itunes:category"])
          .map((value) => text(object(value)["@_text"]))
          .filter(Boolean),
        image: channel["itunes:image"] ? text(object(channel["itunes:image"])["@_href"]) : null,
        language: text(channel.language),
        feedUrl: value,
        imageUrl: channel["itunes:image"] ? text(object(channel["itunes:image"])["@_href"]) : null,
        genres: [],
        explicit: ["yes", "true", "explicit"].includes(text(channel["itunes:explicit"]).toLowerCase()),
      },
      episodes,
    },
  });
}
export async function createPodcast(
  actor: Account,
  input: z.infer<typeof newPodcastSchema>,
  authorize: () => Account,
) {
  writable(actor);
  if (!canReadLibrary(actor, input.libraryId)) throw new DomainError(404, "Not found");
  const library = findLibrary(input.libraryId);
  if (library.mediaType !== "podcast" || !library.folders.some((folder) => folder.id === input.folderId))
    throw new DomainError(400, "Select a podcast library folder");
  const root = await mountedPath(dirname(input.path));
  if (
    !library.folders.some((folder) => folder.id === input.folderId && within(folder.fullPath, root)) ||
    basename(input.path) === "." ||
    basename(input.path) === ".."
  )
    throw new DomainError(400, "Podcast path must be in the selected library");
  if (!within(managedMediaDirectory(), input.path))
    throw new DomainError(
      400,
      "New podcast downloads require a folder in the persistent managed media volume",
    );
  if (!input.media.metadata.feedUrl) throw new DomainError(400, "A feed URL is required");
  const feed = await readFeed(input.media.metadata.feedUrl);
  writable(authorize());
  if (!canReadLibrary(authorize(), input.libraryId)) throw new DomainError(404, "Not found");
  const id = randomUUID(),
    path = resolve(input.path);
  if (
    database()
      .prepare("SELECT id FROM catalog_items WHERE library_id=? AND source_path=?")
      .get(library.id, path)
  )
    throw new DomainError(409, "This podcast folder already exists");
  await mkdir(path, { recursive: false, mode: 0o700 });
  const item = libraryItemSchema.parse({
    id,
    libraryId: library.id,
    mediaType: "podcast",
    addedAt: Date.now(),
    updatedAt: Date.now(),
    isMissing: false,
    isInvalid: false,
    libraryFiles: [],
    media: {
      id,
      metadata: {
        ...feed.podcast.metadata,
        ...input.media.metadata,
        title: input.media.metadata.title || feed.podcast.metadata.title,
      },
      tags: [],
      episodes: [],
      numEpisodes: 0,
      autoDownloadEpisodes: input.media.autoDownloadEpisodes,
    },
  });
  try {
    transaction((db) => {
      writable(authorize());
      if (!canReadLibrary(authorize(), input.libraryId)) throw new DomainError(404, "Not found");
      db.prepare("INSERT INTO catalog_items VALUES(?,?,?,?)").run(id, library.id, path, JSON.stringify(item));
    });
  } catch (error) {
    await rm(path, { recursive: true, force: true });
    throw error;
  }
  subscribe(authorize(), id);
  catalogChanged();
  if (input.media.autoDownloadEpisodes && feed.podcast.episodes.length)
    enqueue(
      authorize(),
      id,
      episodesInput.parse(
        feed.podcast.episodes.slice(
          0,
          Math.min(3, podcastSettings().maxQueue, podcastSettings().retentionEpisodes || 3),
        ),
      ),
    );
  return item;
}
function key(episode: z.infer<typeof episodeInput>) {
  return createHash("sha256")
    .update(episode.guid || episode.enclosure.url)
    .digest("hex");
}
function event(name: string, itemId: string, data: unknown) {
  catalogChanged();
  globalThis.leafwakeRealtimeChanged?.({ podcast: { name, itemId, data } });
}
export function enqueue(actor: Account, itemId: string, episodes: z.infer<typeof episodesInput>) {
  writable(actor, itemId);
  const item = itemFor(actor, itemId);
  if (item.mediaType !== "podcast") throw new DomainError(400, "Not a podcast");
  const queued = transaction((db) => {
    const current = Number(
      db.prepare("SELECT COUNT(*) AS n FROM podcast_jobs WHERE state IN ('queued','running')").get()?.n,
    );

    const created: Job[] = [];
    for (const episode of episodes) {
      remoteUrl(episode.enclosure.url);
      const episodeKey = key(episode);
      if (
        item.media.episodes?.some(
          (existing) =>
            (Boolean(episode.guid) && existing.guid === episode.guid) ||
            existing.enclosure?.url === episode.enclosure.url,
        )
      )
        continue;
      const prior = db
        .prepare("SELECT * FROM podcast_jobs WHERE item_id=? AND episode_key=?")
        .get(itemId, episodeKey);
      if (prior && ["queued", "running", "complete"].includes(String(prior.state))) continue;
      if (prior && globalThis.leafwakePodcasts?.running.has(String(prior.id)))
        throw new DomainError(409, "Previous download is still stopping; retry shortly");
      if (current + created.length >= podcastSettings().maxQueue)
        throw new DomainError(429, "Podcast queue is full");
      const job: Job = {
        id: randomUUID(),
        item_id: itemId,
        episode_key: episodeKey,
        user_id: actor.id,
        state: "queued",
        attempts: 0,
        lease_until: null,
        content: JSON.stringify(episode),
        updated_at: Date.now(),
      };
      db.prepare(
        "INSERT INTO podcast_jobs VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(item_id,episode_key) DO UPDATE SET id=excluded.id,user_id=excluded.user_id,state='queued',attempts=0,lease_until=NULL,content=excluded.content,updated_at=excluded.updated_at",
      ).run(job.id, itemId, episodeKey, actor.id, job.state, 0, null, job.content, job.updated_at);
      created.push(job);
    }
    return created;
  });
  for (const job of queued)
    event("episode_download_queued", itemId, {
      id: job.id,
      libraryItemId: itemId,
      episodeDisplayTitle: episodeInput.parse(JSON.parse(job.content)).title,
    });
  startPodcasts();
  return { success: true };
}
declare global {
  var leafwakePodcasts:
    | { running: Map<string, AbortController>; pumping: boolean; timer: ReturnType<typeof setInterval> }
    | undefined;
}
function jobAuthority(job: Job) {
  const actor = findAccount(job.user_id);
  writable(actor, job.item_id);
  const current = database().prepare("SELECT state FROM podcast_jobs WHERE id=?").get(job.id);
  if (current?.state !== "running") throw new DomainError(409, "Download no longer active");
  return actor;
}
export function startPodcasts() {
  if (globalThis.leafwakePodcasts) return;
  database().exec("UPDATE podcast_jobs SET state='queued',lease_until=NULL WHERE state='running'");
  const timer = setInterval(() => {
    void pump().catch(() => {});
  }, 250);
  timer.unref();
  globalThis.leafwakePodcasts = { running: new Map(), pumping: false, timer };
}
async function pump() {
  const worker = globalThis.leafwakePodcasts;
  if (!worker || worker.pumping) return;
  worker.pumping = true;
  try {
    while (worker.running.size < podcastSettings().maxConcurrent) {
      const row = database()
        .prepare("SELECT * FROM podcast_jobs WHERE state='queued' ORDER BY updated_at,id LIMIT 1")
        .get();
      if (!row) break;
      const job = jobSchema.parse(row),
        controller = new AbortController();
      transaction((db) =>
        db
          .prepare(
            "UPDATE podcast_jobs SET state='running',attempts=attempts+1,lease_until=?,updated_at=? WHERE id=? AND state='queued'",
          )
          .run(Date.now() + 10 * 60 * 1000, Date.now(), job.id),
      );
      worker.running.set(job.id, controller);
      void download(job, controller).finally(() => worker.running.delete(job.id));
    }
  } finally {
    worker.pumping = false;
  }
}
async function probe(path: string, format: string, signal: AbortSignal) {
  return new Promise<number>((resolve, reject) => {
    execFile(
      "ffprobe",
      [
        "-v",
        "error",
        "-protocol_whitelist",
        "file,pipe",
        "-f",
        format,
        "-show_entries",
        "format=duration",
        "-of",
        "json",
        path,
      ],
      { timeout: 30000, maxBuffer: 65536, signal },
      (error, stdout) => {
        if (error) return reject(error);
        try {
          const value = z
            .object({ format: z.object({ duration: z.coerce.number().finite().positive().max(172800) }) })
            .parse(JSON.parse(stdout));
          resolve(value.format.duration);
        } catch (error) {
          reject(error);
        }
      },
    );
  });
}
async function download(job: Job, controller: AbortController) {
  const content = episodeInput.parse(JSON.parse(job.content));
  let partial: string | undefined,
    output: string | undefined,
    published = false;
  const maxBytes = podcastSettings().maxEpisodeBytes;
  const expiry = setTimeout(
    () => controller.abort(new Error("Download time limit exceeded")),
    podcastSettings().downloadTimeoutSeconds * 1000,
  );
  expiry.unref();
  const checks = setInterval(() => {
    try {
      jobAuthority(job);
      database()
        .prepare("UPDATE podcast_jobs SET lease_until=? WHERE id=? AND state='running'")
        .run(Date.now() + 1000, job.id);
    } catch (error) {
      controller.abort(error);
    }
  }, 250);
  checks.unref();
  try {
    const actor = jobAuthority(job),
      item = itemFor(actor, job.item_id);
    const source = database().prepare("SELECT source_path FROM catalog_items WHERE id=?").get(item.id);
    const directory = await mountedPath(z.string().parse(source?.source_path));
    if (!within(managedMediaDirectory(), directory))
      throw new DomainError(
        400,
        "Imported media are read-only; move this subscription into managed storage before new downloads",
      );
    const mime =
      content.enclosure.type ||
      { ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".ogg": "audio/ogg", ".wav": "audio/wav" }[
        extname(new URL(content.enclosure.url).pathname)
      ];
    const formats: Record<string, { ext: string; demux: string }> = {
      "audio/mpeg": { ext: ".mp3", demux: "mp3" },
      "audio/mp3": { ext: ".mp3", demux: "mp3" },
      "audio/mp4": { ext: ".m4a", demux: "mov" },
      "audio/x-m4a": { ext: ".m4a", demux: "mov" },
      "audio/ogg": { ext: ".ogg", demux: "ogg" },
      "audio/wav": { ext: ".wav", demux: "wav" },
    };
    const format = mime ? formats[mime] : undefined;
    if (!format) throw new DomainError(400, "Unsupported enclosure audio type");
    const fileId = `podcast-${job.episode_key}`,
      episodeId = `episode-${job.episode_key}`;
    output = resolve(directory, `${job.episode_key}${format.ext}`);
    partial = `${output}.partial`;
    event("episode_download_started", item.id, {
      id: job.id,
      libraryItemId: item.id,
      episodeDisplayTitle: content.title,
    });
    let duration: number, size: number;
    const existing = await lstat(output).catch(() => null);
    if (existing) {
      if (!existing.isFile() || existing.isSymbolicLink() || existing.size > maxBytes)
        throw new DomainError(400, "Invalid recovered episode file");
      duration = await probe(output, format.demux, controller.signal);
      size = existing.size;
    } else {
      await rm(partial, { force: true });
      const response = await remoteStream(content.enclosure.url, maxBytes, controller.signal);
      let bytes = 0;
      await pipeline(
        response,
        new Transform({
          transform(chunk, _encoding, callback) {
            bytes += chunk.length;
            if (bytes > maxBytes) callback(new Error("Episode exceeds size limit"));
            else callback(null, chunk);
          },
        }),
        createWriteStream(partial, { flags: "wx", mode: 0o600 }),
        { signal: controller.signal },
      );
      duration = await probe(partial, format.demux, controller.signal);
      size = bytes;
      jobAuthority(job);
      controller.signal.throwIfAborted();
      if ((await realpath(directory)) !== directory) throw new Error("Podcast folder changed");
      await rename(partial, output);
    }
    const file = {
      ino: fileId,
      fileType: "audio",
      mimeType: mime,
      metadata: { filename: basename(output), path: output, size, ext: format.ext },
      duration,
    };
    const track = {
      index: 1,
      startOffset: 0,
      duration,
      contentUrl: `/api/items/${item.id}/file/${fileId}`,
      mimeType: mime,
    };
    const episode = podcastEpisodeSchema.parse({
      id: episodeId,
      libraryItemId: item.id,
      title: content.title || "Untitled episode",
      description: content.description,
      publishedAt: content.publishedAt,
      duration,
      size,
      guid: content.guid,
      enclosure: content.enclosure,
      audioFile: { ...file, metadata: file.metadata },
      audioTrack: track,
      chapters: [],
    });
    transaction((db) => {
      const current = itemFor(jobAuthority(job), item.id);
      controller.signal.throwIfAborted();
      current.libraryFiles = [...(current.libraryFiles ?? []).filter((file) => file.ino !== fileId), file];
      current.media.episodes = [...(current.media.episodes ?? []).filter((e) => e.id !== episodeId), episode];
      current.media.numEpisodes = current.media.episodes.length;
      current.updatedAt = Date.now();
      delete current.episodeDownloadsQueued;
      delete current.episodesDownloading;
      db.prepare(
        "INSERT INTO media_files VALUES(?,?,?,?) ON CONFLICT(item_id,id) DO UPDATE SET source_path=excluded.source_path,content=excluded.content",
      ).run(fileId, item.id, z.string().parse(output), JSON.stringify(file));
      db.prepare("UPDATE catalog_items SET content=? WHERE id=?").run(JSON.stringify(current), item.id);
      db.prepare("UPDATE podcast_jobs SET state='complete',lease_until=NULL,updated_at=? WHERE id=?").run(
        Date.now(),
        job.id,
      );
    });
    published = true;
    await retainEpisodes(findAccount(job.user_id), item.id).catch(() => {
      database()
        .prepare("UPDATE podcast_subscriptions SET last_error=? WHERE item_id=?")
        .run("Retention could not remove an episode; check delete permission and media storage", item.id);
    });
    event("episode_download_finished", item.id, {
      id: job.id,
      libraryItemId: item.id,
      episodeId,
      isFinished: true,
      failed: false,
      url: content.enclosure.url,
      episodeDisplayTitle: episode.title,
    });
  } catch (error) {
    database()
      .prepare(
        "UPDATE podcast_jobs SET state='failed',lease_until=NULL,updated_at=? WHERE id=? AND state='running'",
      )
      .run(Date.now(), job.id);
    event("episode_download_finished", job.item_id, {
      id: job.id,
      libraryItemId: job.item_id,
      isFinished: true,
      failed: true,
      url: content.enclosure.url,
      message: error instanceof Error ? error.message : "Download failed",
    });
  } finally {
    clearTimeout(expiry);
    clearInterval(checks);
    if (partial) await rm(partial, { force: true }).catch(() => {});
    if (output && !published) await rm(output, { force: true }).catch(() => {});
  }
}
export async function clearQueue(actor: Account, itemId: string) {
  writable(actor, itemId);
  const jobs = database()
    .prepare("SELECT id FROM podcast_jobs WHERE item_id=? AND state IN ('queued','running')")
    .all(itemId);
  transaction((db) =>
    db
      .prepare(
        "UPDATE podcast_jobs SET state='cancelled',lease_until=NULL,updated_at=? WHERE item_id=? AND state IN ('queued','running')",
      )
      .run(Date.now(), itemId),
  );
  for (const job of jobs) globalThis.leafwakePodcasts?.running.get(String(job.id))?.abort();
  event("episode_download_queue_cleared", itemId, { libraryItemId: itemId });
  return { success: true };
}
export function downloadsFor(actor: Account, itemId: string) {
  itemFor(actor, itemId);
  return {
    downloads: database()
      .prepare("SELECT id,state,content FROM podcast_jobs WHERE item_id=? ORDER BY updated_at DESC LIMIT 128")
      .all(itemId)
      .map((job) => {
        const episode = episodeInput.parse(JSON.parse(z.string().parse(job.content)));
        return {
          id: job.id,
          libraryItemId: itemId,
          episodeDisplayTitle: episode.title ?? "",
          url: episode.enclosure.url,
          isFinished: ["complete", "failed", "cancelled"].includes(String(job.state)),
          failed: ["failed", "cancelled"].includes(String(job.state)),
        };
      }),
  };
}
export async function removeEpisode(actor: Account, itemId: string, episodeId: string) {
  writable(actor, itemId);
  if (!permissions.parse(JSON.parse(actor.permissions)).delete)
    throw new DomainError(403, "Deleting episodes requires delete permission");
  const item = itemFor(actor, itemId),
    episode = item.media.episodes?.find((e) => e.id === episodeId);
  if (!episode) throw new DomainError(404, "Not found");
  const fileId = z.string().parse(episode.audioFile?.ino);
  const row = database()
    .prepare("SELECT source_path FROM media_files WHERE item_id=? AND id=?")
    .get(itemId, fileId);
  const path = z.string().parse(row?.source_path);
  if (!within(managedMediaDirectory(), path))
    throw new DomainError(400, "Imported source media are read-only");
  transaction((db) => {
    writable(actor, itemId);
    item.media.episodes = item.media.episodes?.filter((e) => e.id !== episodeId);
    item.media.numEpisodes = item.media.episodes?.length;
    item.libraryFiles = item.libraryFiles?.filter((f) => f.ino !== fileId);
    item.updatedAt = Date.now();
    db.prepare("UPDATE catalog_items SET content=? WHERE id=?").run(JSON.stringify(item), itemId);
    db.prepare("DELETE FROM media_files WHERE item_id=? AND id=?").run(itemId, fileId);
    db.prepare(
      "INSERT INTO progress_resets(user_id,item_id,episode_id,cutoff,generation) SELECT id,?,?,?,1 FROM users WHERE true ON CONFLICT(user_id,item_id,episode_id) DO UPDATE SET cutoff=excluded.cutoff,generation=progress_resets.generation+1",
    ).run(itemId, episodeId, Date.now());
    db.prepare("DELETE FROM media_progress WHERE item_id=? AND episode_id=?").run(itemId, episodeId);
    db.prepare(
      "UPDATE playback_sessions SET active=0 WHERE item_id=? AND json_extract(content,'$.episodeId')=?",
    ).run(itemId, episodeId);
    db.prepare("UPDATE podcast_jobs SET state='cancelled' WHERE item_id=? AND episode_key=?").run(
      itemId,
      key(episodeInput.parse({ enclosure: episode.enclosure, guid: episode.guid })),
    );
    for (const row of db.prepare("SELECT id,content FROM media_lists WHERE kind='playlist'").all()) {
      const list = storedSchema.parse(JSON.parse(z.string().parse(row.content)));
      list.entries = list.entries.filter(
        (ref) => ref.libraryItemId !== itemId || ref.episodeId !== episodeId,
      );
      db.prepare("UPDATE media_lists SET content=? WHERE id=?").run(
        JSON.stringify(list),
        z.string().parse(row.id),
      );
    }
  });
  await rm(path, { force: true });
  listsChanged();
  event("episode_removed", itemId, { libraryItemId: itemId, episodeId });
  return { success: true };
}
export function recentEpisodes(actor: Account, libraryId: string, params: URLSearchParams) {
  const limit = z.coerce
      .number()
      .int()
      .min(1)
      .max(200)
      .parse(params.get("limit") ?? 24),
    page = z.coerce
      .number()
      .int()
      .min(0)
      .max(100000)
      .parse(params.get("page") ?? 0);
  const episodes = itemsFor(actor, libraryId)
    .flatMap((item) =>
      (item.media.episodes ?? []).map((episode) => ({
        ...episode,
        libraryId,
        podcast: {
          id: item.id,
          libraryItemId: item.id,
          metadata: item.media.metadata,
          coverPath: item.media.coverPath,
        },
      })),
    )
    .sort((a, b) => (b.publishedAt ?? 0) - (a.publishedAt ?? 0) || a.id.localeCompare(b.id));
  return { episodes: episodes.slice(page * limit, (page + 1) * limit), total: episodes.length, limit, page };
}
