import "server-only";
import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { lstat, open, realpath } from "node:fs/promises";
import { z } from "zod";
import { playbackSessionSchema } from "@/lib/abs/schemas";
import { type Account, DomainError, findAccount, permissions } from "./accounts";
import { findLibrary, itemFor, mountedPath, within } from "./catalog";
import { database, progressGeneration, transaction } from "./data";
import { progressFor } from "./progress";

const fileSchema = z.object({ source_path: z.string(), content: z.string() });
const fileContentSchema = z.object({
  ino: z.string(),
  fileType: z.string(),
  mimeType: z.string(),
  metadata: z.object({ filename: z.string(), size: z.number() }),
});
const nativeFlag = z
  .union([z.boolean(), z.enum(["1", ""])])
  .transform((value) => value === true || value === "1");
export const playSchema = z.object({
  deviceInfo: z.record(z.string(), z.unknown()).optional(),
  supportedMimeTypes: z.array(z.string().max(128)).max(64).optional(),
  forceDirectPlay: nativeFlag.optional(),
  forceTranscode: nativeFlag.optional(),
});
export function openPlayback(actor: Account, itemId: string, input: z.infer<typeof playSchema>) {
  const item = itemFor(actor, itemId);
  if (item.isMissing || !item.media.tracks?.length) throw new DomainError(404, "Playable media not found");
  const transcode =
    input.forceTranscode ||
    (!input.forceDirectPlay &&
      input.supportedMimeTypes &&
      item.media.tracks.some(
        (track) => !track.mimeType || !input.supportedMimeTypes?.includes(track.mimeType),
      ));
  const sessionId = randomUUID();
  if (transcode && (!item.media.duration || item.media.duration > 172800))
    throw new DomainError(422, "Unsupported transcode duration");
  const now = Date.now();
  const session = playbackSessionSchema.parse({
    id: sessionId,
    userId: actor.id,
    timeListening: 0,
    mediaMetadata: item.media.metadata,
    deviceInfo: input.deviceInfo ?? {},
    libraryItemId: itemId,
    episodeId: null,
    mediaType: item.mediaType,
    displayTitle: item.media.metadata.title,
    displayAuthor: item.media.metadata.authorName,
    duration: item.media.duration,
    currentTime: progressFor(actor, itemId)?.currentTime ?? 0,
    progressGeneration: progressGeneration(actor.id, itemId),
    playMethod: transcode ? 1 : 0,
    chapters: item.media.chapters,
    audioTracks: transcode
      ? [
          {
            index: 1,
            startOffset: 0,
            duration: item.media.duration,
            contentUrl: `/hls/${sessionId}/output.m3u8`,
            mimeType: "application/vnd.apple.mpegurl",
          },
        ]
      : item.media.tracks,
    startedAt: now,
    updatedAt: now,
  });
  transaction((db) => {
    itemFor(findAccount(actor.id), itemId);
    db.prepare(
      "INSERT INTO playback_sessions(id,user_id,item_id,content,expires_at) VALUES (?, ?, ?, ?, ?)",
    ).run(session.id, actor.id, itemId, JSON.stringify(session), now + 24 * 60 * 60_000);
  });
  return session;
}
export function sessionFor(actor: Account, id: string) {
  const row = database()
    .prepare(
      "SELECT content,item_id FROM playback_sessions WHERE id = ? AND user_id = ? AND active = 1 AND expires_at > ?",
    )
    .get(id, actor.id, Date.now());
  if (!row) throw new DomainError(404, "Not found");
  itemFor(actor, z.string().parse(row.item_id));
  return playbackSessionSchema.parse(JSON.parse(z.string().parse(row.content)));
}
export function closePlayback(actor: Account, id: string) {
  sessionFor(actor, id);
  database()
    .prepare("UPDATE playback_sessions SET active = 0 WHERE id = ? AND user_id = ?")
    .run(id, actor.id);
}
function range(headers: Headers, size: number) {
  const value = headers.get("range");
  if (!value) return { start: 0, end: size - 1, status: 200 };
  const match = value.match(/^bytes=(\d*)-(\d*)$/);
  if (!match || (!match[1] && !match[2])) return null;
  const left = match[1] ? Number(match[1]) : null;
  const right = match[2] ? Number(match[2]) : null;
  if ((left !== null && !Number.isSafeInteger(left)) || (right !== null && !Number.isSafeInteger(right)))
    return null;
  const start = left ?? Math.max(0, size - (right ?? 0));
  const end = left === null ? size - 1 : Math.min(right ?? size - 1, size - 1);
  if ((left === null && !right) || start < 0 || start >= size || end < start) return null;
  return { start, end, status: 206 };
}
export async function serveFile(
  request: Request,
  authorize: () => Account,
  itemId: string,
  fileId: string,
  download = false,
) {
  const actor = authorize();
  const item = itemFor(actor, itemId);
  if (download && !permissions.parse(JSON.parse(actor.permissions)).download)
    throw new DomainError(403, "Downloads are not allowed");
  if (!item.libraryFiles?.some((file) => file.ino === fileId)) throw new DomainError(404, "Not found");
  const row = database()
    .prepare("SELECT source_path,content FROM media_files WHERE id = ? AND item_id = ?")
    .get(fileId, itemId);
  if (!row) throw new DomainError(404, "Not found");
  const file = fileSchema.parse(row);
  const content = fileContentSchema.parse(JSON.parse(file.content));
  let handle: Awaited<ReturnType<typeof open>> | undefined;
  try {
    const entry = await lstat(file.source_path);
    if (!entry.isFile() || entry.isSymbolicLink()) throw new DomainError(404, "Not found");
    const library = findLibrary(item.libraryId);
    const folders = await Promise.all(library.folders.map((folder) => mountedPath(folder.fullPath)));
    const canonical = await realpath(file.source_path);
    if (!folders.some((folder) => within(folder, canonical))) throw new DomainError(404, "Not found");
    handle = await open(canonical, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const opened =
      process.platform === "linux" ? await realpath(`/proc/self/fd/${handle.fd}`) : await realpath(canonical);
    const stat = await handle.stat();
    if (!stat.isFile() || !folders.some((folder) => within(folder, opened)))
      throw new DomainError(404, "Not found");
    // Recheck current account and catalog authority after filesystem awaits, before exposing bytes.
    const current = authorize();
    const currentItem = itemFor(current, itemId);
    if (!currentItem.libraryFiles?.some((file) => file.ino === fileId))
      throw new DomainError(404, "Not found");
    if (download && !permissions.parse(JSON.parse(current.permissions)).download)
      throw new DomainError(403, "Downloads are not allowed");
    const selected = range(request.headers, stat.size);
    const headers = new Headers({
      "content-type": content.mimeType,
      "accept-ranges": "bytes",
      "cache-control": "private, no-store",
      "x-content-type-options": "nosniff",
    });
    if (download)
      headers.set(
        "content-disposition",
        `attachment; filename*=UTF-8''${encodeURIComponent(content.metadata.filename)}`,
      );
    if (!selected) {
      headers.set("content-range", `bytes */${stat.size}`);
      await handle.close();
      return new Response(null, { status: 416, headers });
    }
    headers.set("content-length", String(selected.end - selected.start + 1));
    if (selected.status === 206)
      headers.set("content-range", `bytes ${selected.start}-${selected.end}/${stat.size}`);
    if (request.method === "HEAD") {
      await handle.close();
      return new Response(null, { status: selected.status, headers });
    }
    const openedHandle = handle;
    let position = selected.start;
    let closed = false;
    const close = async () => {
      if (!closed) {
        closed = true;
        await openedHandle.close();
      }
    };
    const stream = new ReadableStream<Uint8Array>({
      async pull(controller) {
        try {
          if (position > selected.end) {
            await close();
            controller.close();
            return;
          }
          const bytes = Buffer.alloc(Math.min(65536, selected.end - position + 1));
          const read = await openedHandle.read(bytes, 0, bytes.length, position);
          if (!read.bytesRead) {
            await close();
            controller.error(new Error("Media file ended early"));
            return;
          }
          position += read.bytesRead;
          controller.enqueue(bytes.subarray(0, read.bytesRead));
        } catch (error) {
          await close();
          controller.error(error);
        }
      },
      cancel: close,
    });
    return new Response(stream, { status: selected.status, headers });
  } catch (error) {
    await handle?.close();
    if (error instanceof DomainError) throw error;
    throw new DomainError(404, "Not found");
  }
}
export async function serveTrack(
  request: Request,
  authorize: () => Account,
  sessionId: string,
  index: number,
) {
  const session = sessionFor(authorize(), sessionId);
  const track = session.audioTracks.find((track) => track.index === index);
  if (!track) throw new DomainError(404, "Not found");
  const path = track.contentUrl.match(/^\/api\/items\/([^/]+)\/file\/([^/]+)$/);
  if (!path?.[1] || !path[2] || path[1] !== session.libraryItemId) throw new DomainError(404, "Not found");
  return serveFile(
    request,
    () => {
      const current = authorize();
      sessionFor(current, sessionId);
      return current;
    },
    path[1],
    path[2],
  );
}
