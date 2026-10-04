import "server-only";
import type { ReadStream } from "node:fs";
import { basename } from "node:path";
import { Readable } from "node:stream";
import { ZipFile } from "yazl";
import { type Account, DomainError, permissions } from "./accounts";
import { itemFor } from "./catalog";
import { openMediaFile, serveFile } from "./playback";

declare global {
  var leafwakeArchiveCount: number | undefined;
}
export async function serveEbook(
  request: Request,
  authorize: () => Account,
  itemId: string,
  fileId?: string,
) {
  const item = itemFor(authorize(), itemId);
  const selected = fileId
    ? item.libraryFiles?.find((file) => file.ino === fileId && file.fileType === "ebook")
    : item.media.ebookFile;
  if (!selected) throw new DomainError(404, "Not found");
  return serveFile(request, authorize, itemId, selected.ino);
}
export async function downloadItem(request: Request, authorize: () => Account, itemId: string) {
  const actor = authorize(),
    item = itemFor(actor, itemId);
  if (!permissions.parse(JSON.parse(actor.permissions)).download)
    throw new DomainError(403, "Downloads are not allowed");
  const files = item.libraryFiles ?? [];
  if (!files.length || item.isMissing) throw new DomainError(404, "Not found");
  if (files.length > 2048) throw new DomainError(422, "Too many archive files");
  // A generated archive has no stable byte layout for resumption; individual file downloads support ranges.
  if (request.headers.has("range")) throw new DomainError(416, "Use individual file downloads for ranges");
  if ((globalThis.leafwakeArchiveCount ?? 0) >= 4) throw new DomainError(503, "Archive workers are busy");
  globalThis.leafwakeArchiveCount = (globalThis.leafwakeArchiveCount ?? 0) + 1;
  let released = false,
    cancelled = false;
  const release = () => {
    if (!released) {
      released = true;
      globalThis.leafwakeArchiveCount = Math.max(0, (globalThis.leafwakeArchiveCount ?? 1) - 1);
    }
  };
  const zip = new ZipFile();
  const output = zip.outputStream;
  if (!(output instanceof Readable)) {
    release();
    throw new DomainError(500, "Archive stream unavailable");
  }
  const active = new Set<ReadStream>();
  const stop = () => {
    if (cancelled) return;
    cancelled = true;
    for (const stream of active) stream.destroy();
    output.destroy();
    release();
  };
  output.on("error", stop);
  zip.on("error", (error: Error) => {
    output.destroy(error);
  });
  try {
    const names = new Set<string>();
    for (const file of files) {
      if (request.signal.aborted) throw new DomainError(499, "Request cancelled");
      const opened = await openMediaFile(authorize, itemId, file.ino, true);
      const size = opened.stat.size;
      await opened.handle.close();
      let name = basename(opened.content.metadata.filename.replaceAll("\\", "/"));
      if (!name || name === "." || name === ".." || Buffer.byteLength(name) > 4096)
        throw new DomainError(422, "Invalid archive filename");
      if (names.has(name)) name = `${names.size + 1}-${name}`;
      while (names.has(name)) name = `duplicate-${name}`;
      names.add(name);
      if (request.method === "HEAD") continue;
      zip.addReadStreamLazy(name, { size, compress: false, forceZip64Format: true }, (callback) => {
        void openMediaFile(authorize, itemId, file.ino, true).then(
          (opened) => {
            if (cancelled) {
              void opened.handle.close();
              callback(Error("Archive cancelled"), Readable.from([]));
              return;
            }
            const stream = opened.handle.createReadStream({ autoClose: true, highWaterMark: 65536 });
            stream.once("error", (error) => output.destroy(error));
            active.add(stream);
            stream.once("close", () => active.delete(stream));
            callback(null, stream);
          },
          (error) => callback(error instanceof Error ? error : Error("Media unavailable"), Readable.from([])),
        );
      });
    }
    const headers = {
      "content-type": "application/zip",
      "cache-control": "private, no-store",
      "x-content-type-options": "nosniff",
      "content-disposition": `attachment; filename*=UTF-8''${encodeURIComponent(`${item.media.metadata.title || "book"}.zip`)}`,
    };
    if (request.method === "HEAD") {
      release();
      return new Response(null, { headers });
    }
    if (request.signal.aborted || cancelled) throw new DomainError(499, "Request cancelled");
    zip.end({ forceZip64Format: true, comment: "" });
    const iterator = output[Symbol.asyncIterator]();
    request.signal.addEventListener("abort", stop, { once: true });
    const stream = new ReadableStream<Uint8Array>({
      async pull(controller) {
        try {
          const current = authorize();
          itemFor(current, itemId);
          if (!permissions.parse(JSON.parse(current.permissions)).download)
            throw Error("Downloads are no longer allowed");
          const next = await iterator.next();
          if (next.done) {
            release();
            request.signal.removeEventListener("abort", stop);
            controller.close();
          } else controller.enqueue(Buffer.isBuffer(next.value) ? next.value : Buffer.from(next.value));
        } catch (error) {
          stop();
          controller.error(error);
        }
      },
      cancel: stop,
    });
    return new Response(stream, { headers });
  } catch (error) {
    stop();
    throw error;
  }
}
