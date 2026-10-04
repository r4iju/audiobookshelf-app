import "server-only";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { type Account, DomainError, findAccount, permissions, requireAdministrator } from "./accounts";
import { itemFor } from "./catalog";
import { catalogChanged, database, transaction } from "./data";
import { serveFile } from "./playback";

export const feedRecord = z.object({
  id: z.string(),
  itemId: z.string(),
  ownerId: z.string(),
  slug: z.string(),
  base: z.string(),
  episodes: z
    .array(
      z.object({
        id: z.string().max(256),
        fileId: z.string().max(256),
        path: z.string().max(2048),
        title: z.string().max(4096),
        description: z.string().max(65536),
        publishedAt: z.number().finite(),
        duration: z.number().nonnegative(),
      }),
    )
    .max(5000)
    .optional(),
  meta: z.object({
    title: z.string(),
    preventIndexing: z.boolean(),
    ownerName: z.string(),
    ownerEmail: z.string(),
  }),
});
export const openFeedSchema = z.object({
  serverAddress: z.string().max(2048),
  slug: z.string().regex(/^[a-z0-9][a-z0-9_-]{0,127}$/),
  metadataDetails: z.object({
    preventIndexing: z.boolean().default(true),
    ownerName: z.string().max(256).default(""),
    ownerEmail: z.union([z.email(), z.literal("")]).default(""),
  }),
});
export function validateFeedAddress(value: string) {
  const url = new URL(value);
  if (
    !["https:", "http:"].includes(url.protocol) ||
    url.username ||
    url.password ||
    url.hash ||
    url.search ||
    (url.pathname === "/" ? "" : url.pathname) !== (globalThis.leafwakeBasePath || "")
  )
    throw new DomainError(400, "Use the exact server URL including its configured subpath");
  return value.replace(/\/$/, "");
}
export function saveImportedFeed(feed: z.infer<typeof feedRecord>) {
  database()
    .prepare("INSERT INTO rss_feeds VALUES(?,?,?,?,?)")
    .run(feed.id, feed.itemId, feed.ownerId, feed.slug, JSON.stringify(feed));
}
function projection(feed: z.infer<typeof feedRecord>) {
  return { id: feed.id, entityId: feed.itemId, feedUrl: `/feed/${feed.slug}`, meta: feed.meta };
}
export function feedForItem(id: string) {
  const row = database().prepare("SELECT content FROM rss_feeds WHERE item_id=?").get(id);
  return row ? projection(feedRecord.parse(JSON.parse(z.string().parse(row.content)))) : null;
}
export function allFeeds(actor: Account) {
  requireAdministrator(actor);
  return {
    feeds: database()
      .prepare("SELECT content FROM rss_feeds")
      .all()
      .flatMap((row) => {
        const feed = feedRecord.parse(JSON.parse(z.string().parse(row.content)));
        try {
          itemFor(actor, feed.itemId);
          return [projection(feed)];
        } catch {
          return [];
        }
      }),
  };
}
export function openFeed(actor: Account, itemId: string, input: z.infer<typeof openFeedSchema>) {
  requireAdministrator(actor);
  const item = itemFor(actor, itemId);
  validateFeedAddress(input.serverAddress);
  if (!item.libraryFiles?.some((f) => f.fileType === "audio"))
    throw new DomainError(400, "RSS publishing requires downloaded audio");
  if ((item.libraryFiles?.filter((f) => f.fileType === "audio").length ?? 0) > 5000)
    throw new DomainError(400, "Feed exceeds the 5000 audio-file limit");
  const feed = {
    id: randomUUID(),
    itemId,
    ownerId: actor.id,
    slug: input.slug,
    base: input.serverAddress.replace(/\/$/, ""),
    meta: { title: item.media.metadata.title, ...input.metadataDetails },
  };
  transaction((db) => {
    requireAdministrator(actor);
    itemFor(actor, itemId);
    if (db.prepare("SELECT id FROM rss_feeds WHERE slug=? OR item_id=?").get(input.slug, itemId))
      throw new DomainError(409, "This slug or item already has an open feed");
    db.prepare("INSERT INTO rss_feeds VALUES(?,?,?,?,?)").run(
      feed.id,
      itemId,
      actor.id,
      input.slug,
      JSON.stringify(feed),
    );
  });
  catalogChanged();
  return { feed: projection(feed) };
}
export function closeFeed(actor: Account, id: string) {
  requireAdministrator(actor);
  const row = database().prepare("SELECT item_id FROM rss_feeds WHERE id=?").get(id);
  if (!row) throw new DomainError(404, "Not found");
  itemFor(actor, z.string().parse(row.item_id));
  database().prepare("DELETE FROM rss_feeds WHERE id=?").run(id);
  catalogChanged();
  return { success: true };
}
function published(slug: string) {
  const row = database().prepare("SELECT content FROM rss_feeds WHERE slug=?").get(slug);
  if (!row) throw new DomainError(404, "Not found");
  const feed = feedRecord.parse(JSON.parse(z.string().parse(row.content)));
  const actor = findAccount(feed.ownerId);
  requireAdministrator(actor);
  const item = itemFor(actor, feed.itemId);
  if (item.isMissing || !permissions.parse(JSON.parse(actor.permissions)).download)
    throw new DomainError(404, "Not found");
  return { feed, actor, item };
}
function xml(value: unknown) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[c] ?? "",
  );
}
export async function publicFeed(request: Request, slug: string, fileId?: string, episodePath?: string) {
  const current = published(slug),
    { feed, item } = current;
  if (episodePath) {
    fileId = feed.episodes?.find((e) => e.path === episodePath)?.fileId;
    if (!fileId) throw new DomainError(404, "Not found");
  }
  if (fileId) {
    if (!item.libraryFiles?.some((f) => f.ino === fileId && f.fileType === "audio"))
      throw new DomainError(404, "Not found");
    const response = await serveFile(request, () => published(slug).actor, item.id, fileId, true);
    if (!response.body) return response;
    const reader = response.body.getReader();
    return new Response(
      new ReadableStream({
        async pull(controller) {
          try {
            const check = () => {
              const current = published(slug);
              if (
                current.feed.id !== feed.id ||
                !current.item.libraryFiles?.some((file) => file.ino === fileId && file.fileType === "audio")
              )
                throw new DomainError(404, "Not found");
            };
            check();
            const next = await reader.read();
            check();
            if (next.done) controller.close();
            else controller.enqueue(next.value);
          } catch (error) {
            await reader.cancel();
            controller.error(error);
          }
        },
        cancel() {
          return reader.cancel();
        },
      }),
      { status: response.status, headers: response.headers },
    );
  }
  const files = item.libraryFiles?.filter((f) => f.fileType === "audio") ?? [];
  const entries = (
    feed.episodes
      ? feed.episodes
          .map((e) => files.find((f) => f.ino === e.fileId))
          .filter((f): f is NonNullable<typeof f> => Boolean(f))
      : files
  )
    .slice(0, 5000)
    .map((file, index) => {
      const episode = item.media.episodes?.find(
          (e) => e.audioFile?.metadata.filename === file.metadata.filename,
        ),
        track = item.media.tracks?.[index];
      const content = database()
        .prepare("SELECT content FROM media_files WHERE item_id=? AND id=?")
        .get(item.id, file.ino);
      if (!content) return "";
      const stored = JSON.parse(z.string().parse(content.content));
      const imported = feed.episodes?.find((e) => e.fileId === file.ino);
      const title = imported?.title || episode?.title || track?.title || file.metadata.filename;
      return `<item><title>${xml(title)}</title><guid isPermaLink="false">${xml(imported?.id || item.id + ":" + file.ino)}</guid><pubDate>${xml(new Date(imported?.publishedAt ?? episode?.publishedAt ?? item.addedAt ?? 0).toUTCString())}</pubDate><description>${xml(imported?.description ?? episode?.description ?? item.media.metadata.description ?? "")}</description><itunes:duration>${Math.round(imported?.duration ?? episode?.duration ?? track?.duration ?? 0)}</itunes:duration><enclosure url="${xml(feed.base + (imported?.path || "/feed/" + slug + "/media/" + encodeURIComponent(file.ino)))}" length="${Number(stored.metadata.size) || 0}" type="${xml(stored.mimeType || "audio/mpeg")}"/></item>`;
    })
    .join("");
  const body = `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>${xml(feed.meta.title)}</title><link>${xml(feed.base)}</link><description>${xml(item.media.metadata.description || feed.meta.title)}</description><itunes:block>${feed.meta.preventIndexing ? "Yes" : "No"}</itunes:block><itunes:owner><itunes:name>${xml(feed.meta.ownerName)}</itunes:name><itunes:email>${xml(feed.meta.ownerEmail)}</itunes:email></itunes:owner>${entries}</channel></rss>`;
  return new Response(request.method === "HEAD" ? null : body, {
    headers: {
      "content-type": "application/rss+xml; charset=utf-8",
      "cache-control": "no-store",
      "x-robots-tag": feed.meta.preventIndexing ? "noindex, nofollow" : "all",
    },
  });
}
