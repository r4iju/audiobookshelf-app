import "server-only";
import { type ChildProcess, spawn } from "node:child_process";
import { constants } from "node:fs";
import { lstat, mkdir, open, readdir, readFile, realpath, rename, rm } from "node:fs/promises";
import { extname, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { z } from "zod";
import { type Account, DomainError, findAccount } from "./accounts";
import { findLibrary, itemFor, mountedPath, within } from "./catalog";
import { database, dataDirectory } from "./data";
import { sessionFor } from "./playback";

const chunkSeconds = 6;
const maxJobs = 32,
  maxCache = 1024;
const jobSchema = z.object({
  id: z.string(),
  session_id: z.string().uuid(),
  segment: z.number().int(),
  status: z.string(),
  updated_at: z.number(),
});
type Job = z.infer<typeof jobSchema>;
const formats: Record<string, string> = {
  ".mp3": "mp3",
  ".wav": "wav",
  ".flac": "flac",
  ".m4a": "mov",
  ".m4b": "mov",
  ".mp4": "mov",
  ".ogg": "ogg",
  ".opus": "ogg",
  ".aac": "aac",
  ".webm": "matroska",
  ".mka": "matroska",
};
declare global {
  var leafwakeTranscode:
    | { running: Map<string, ChildProcess | null>; pumping: boolean; timer: ReturnType<typeof setInterval> }
    | undefined;
}
function directory() {
  return resolve(dataDirectory(), "transcode");
}
function filename(job: Job) {
  return resolve(directory(), `${job.session_id}-${job.segment}.ts`);
}
function sessionActor(sessionId: string) {
  const row = database().prepare("SELECT user_id FROM playback_sessions WHERE id=?").get(sessionId);
  if (!row) throw new DomainError(404, "Not found");
  const actor = findAccount(z.string().parse(row.user_id));
  if (!actor.active) throw new DomainError(404, "Not found");
  sessionFor(actor, sessionId);
  return actor;
}
export function startTranscode() {
  if (globalThis.leafwakeTranscode) return;
  database().exec("UPDATE transcode_jobs SET status='queued' WHERE status='running'");
  const timer = setInterval(() => {
    void pump();
  }, 250);
  timer.unref();
  globalThis.leafwakeTranscode = { running: new Map(), pumping: false, timer };
  void pump();
}
export async function cancelTranscode(sessionId: string) {
  for (const [id, child] of globalThis.leafwakeTranscode?.running ?? [])
    if (id.startsWith(`${sessionId}:`)) child?.kill("SIGKILL");
  const jobs = database()
    .prepare("SELECT * FROM transcode_jobs WHERE session_id=?")
    .all(sessionId)
    .map((row) => jobSchema.parse(row));
  database().prepare("DELETE FROM transcode_jobs WHERE session_id=?").run(sessionId);
  await Promise.all(
    jobs.map((job) =>
      Promise.all([rm(filename(job), { force: true }), rm(`${filename(job)}.partial`, { force: true })]),
    ),
  );
}
async function prune() {
  await mkdir(directory(), { recursive: true, mode: 0o700 });
  // A restored database or cascaded account deletion can leave cache files without job rows.
  for (const entry of await readdir(directory(), { withFileTypes: true })) {
    const match = entry.name.match(/^([0-9a-f-]{36})-(\d+)\.ts(\.partial)?$/);
    if (!match) continue;
    const row = database()
      .prepare("SELECT status FROM transcode_jobs WHERE id=?")
      .get(`${match[1]}:${Number(match[2])}`);
    if (!row || (match[3] && row.status !== "running"))
      await rm(resolve(directory(), entry.name), { force: true });
  }
  const expired = database()
    .prepare(
      "SELECT DISTINCT j.session_id FROM transcode_jobs j LEFT JOIN playback_sessions s ON s.id=j.session_id WHERE s.id IS NULL OR s.active=0 OR s.expires_at<?",
    )
    .all(Date.now());
  for (const row of expired) await cancelTranscode(z.string().parse(row.session_id));
  const old = database()
    .prepare(
      "SELECT * FROM transcode_jobs WHERE status NOT IN ('running','queued') ORDER BY updated_at DESC LIMIT -1 OFFSET ?",
    )
    .all(maxCache)
    .map((row) => jobSchema.parse(row));
  for (const job of old) {
    database()
      .prepare("DELETE FROM transcode_jobs WHERE id=? AND status NOT IN ('running','queued')")
      .run(job.id);
    await rm(filename(job), { force: true });
    await rm(`${filename(job)}.partial`, { force: true });
  }
}
async function encode(job: Job) {
  const handles: Awaited<ReturnType<typeof open>>[] = [];
  let child: ChildProcess | undefined;
  try {
    const actor = sessionActor(job.session_id),
      session = sessionFor(actor, job.session_id);
    const item = itemFor(actor, session.libraryItemId);
    if (session.playMethod !== 1 || Math.abs((item.media.duration ?? 0) - session.duration) > 0.1)
      throw Error("Media changed");
    const start = job.segment * chunkSeconds,
      end = Math.min(session.duration, start + chunkSeconds);
    const tracks = (item.media.tracks ?? []).filter(
      (track) => track.startOffset < end && track.startOffset + track.duration > start,
    );
    if (!tracks.length || tracks.length > 64) throw Error("Unsupported media layout");
    const folders = await Promise.all(
      findLibrary(item.libraryId).folders.map((folder) => mountedPath(folder.fullPath)),
    );
    const args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-max_alloc", "67108864"];
    for (const track of tracks) {
      const match = track.contentUrl.match(/^\/api\/items\/([^/]+)\/file\/([^/]+)$/);
      if (!match || match[1] !== item.id) throw Error("Invalid track");
      const row = database()
        .prepare("SELECT source_path FROM media_files WHERE item_id=? AND id=?")
        .get(item.id, z.string().parse(match[2]));
      const source = z.string().parse(row?.source_path),
        format = formats[extname(source).toLowerCase()];
      if (!format) throw Error("Unsupported source format");
      const entry = await lstat(source),
        canonical = await realpath(source);
      if (!entry.isFile() || entry.isSymbolicLink() || !folders.some((folder) => within(folder, canonical)))
        throw Error("Invalid media path");
      const handle = await open(canonical, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      handles.push(handle);
      const opened = process.platform === "linux" ? await realpath(`/proc/self/fd/${handle.fd}`) : canonical;
      if (!(await handle.stat()).isFile() || !folders.some((folder) => within(folder, opened)))
        throw Error("Invalid opened media");
      const offset = Math.max(0, start - track.startOffset),
        duration = Math.min(end, track.startOffset + track.duration) - Math.max(start, track.startOffset);
      args.push(
        "-threads",
        "1",
        "-protocol_whitelist",
        "file",
        "-f",
        format,
        "-ss",
        String(offset),
        "-t",
        String(duration),
        "-i",
        process.platform === "linux"
          ? `/proc/self/fd/${handles.length + 2}`
          : `/dev/fd/${handles.length + 2}`,
      );
    }
    const filter =
      tracks
        .map(
          (_, i) =>
            `[${i}:a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,asetpts=PTS-STARTPTS[a${i}]`,
        )
        .join(";") + `;${tracks.map((_, i) => `[a${i}]`).join("")}concat=n=${tracks.length}:v=0:a=1[out]`;
    await mkdir(directory(), { recursive: true, mode: 0o700 });
    const output = filename(job);
    await rm(`${output}.partial`, { force: true });
    sessionActor(job.session_id);
    args.push(
      "-filter_complex_threads",
      "1",
      "-filter_complex",
      filter,
      "-map",
      "[out]",
      "-vn",
      "-c:a",
      "aac",
      "-b:a",
      "128k",
      "-threads",
      "1",
      "-t",
      String(end - start),
      "-fs",
      "262144",
      "-f",
      "mpegts",
      "-y",
      `${output}.partial`,
    );
    await new Promise<void>((accept, reject) => {
      child = spawn("ffmpeg", args, {
        shell: false,
        stdio: ["ignore", "ignore", "ignore", ...handles.map((handle) => handle.fd)],
      });
      globalThis.leafwakeTranscode?.running.set(job.id, child);
      const timeout = setTimeout(() => child?.kill("SIGKILL"), 20_000);
      const authority = setInterval(() => {
        try {
          sessionActor(job.session_id);
        } catch {
          child?.kill("SIGKILL");
        }
      }, 250);
      child.once("error", reject);
      child.once("close", (code) => {
        clearTimeout(timeout);
        clearInterval(authority);
        code === 0 ? accept() : reject(Error("Transcode failed"));
      });
    });
    sessionActor(job.session_id);
    if (!database().prepare("SELECT id FROM transcode_jobs WHERE id=? AND status='running'").get(job.id))
      throw Error("Job cancelled");
    const size = (await lstat(`${output}.partial`)).size;
    if (size < 188 || size >= 262144) throw Error("Invalid bounded output");
    await rename(`${output}.partial`, output);
    sessionActor(job.session_id);
    const committed = database()
      .prepare("UPDATE transcode_jobs SET status='complete',updated_at=? WHERE id=? AND status='running'")
      .run(Date.now(), job.id);
    if (!committed.changes) throw Error("Job cancelled during publication");
  } catch {
    database()
      .prepare("UPDATE transcode_jobs SET status='failed',updated_at=? WHERE id=? AND status='running'")
      .run(Date.now(), job.id);
    await rm(`${filename(job)}.partial`, { force: true });
    await rm(filename(job), { force: true });
  } finally {
    globalThis.leafwakeTranscode?.running.delete(job.id);
    await Promise.all(handles.map((handle) => handle.close()));
  }
}
async function pump() {
  const state = globalThis.leafwakeTranscode;
  if (!state || state.pumping) return;
  state.pumping = true;
  try {
    await prune();
    while (state.running.size < 2) {
      const row = database()
        .prepare("SELECT * FROM transcode_jobs WHERE status='queued' ORDER BY updated_at LIMIT 1")
        .get();
      if (!row) break;
      const job = jobSchema.parse(row);
      database()
        .prepare("UPDATE transcode_jobs SET status='running' WHERE id=? AND status='queued'")
        .run(job.id);
      // Reserve capacity before encode's filesystem awaits.
      state.running.set(job.id, null);
      void encode(job);
    }
  } finally {
    state.pumping = false;
  }
}
export async function serveHls(
  request: Request,
  authorize: () => Account,
  sessionId: string,
  resource: string,
) {
  startTranscode();
  const session = sessionFor(authorize(), sessionId);
  if (session.playMethod !== 1) throw new DomainError(404, "Not found");
  const headers = { "cache-control": "private, no-store", "x-content-type-options": "nosniff" };
  if (resource === "output.m3u8") {
    const count = Math.ceil(session.duration / chunkSeconds);
    if (!Number.isFinite(count) || count < 1 || count > 28800)
      throw new DomainError(422, "Unsupported media duration");
    const token = new URL(request.url).searchParams.get("token");
    const suffix = token ? `?token=${encodeURIComponent(token)}` : "";
    const lines = [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-TARGETDURATION:6",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-PLAYLIST-TYPE:VOD",
    ];
    for (let index = 0; index < count; index++)
      lines.push(
        "#EXT-X-DISCONTINUITY",
        `#EXTINF:${Math.min(chunkSeconds, session.duration - index * chunkSeconds).toFixed(6)},`,
        `${index}.ts${suffix}`,
      );
    lines.push("#EXT-X-ENDLIST", "");
    return new Response(request.method === "HEAD" ? null : lines.join("\n"), {
      headers: { ...headers, "content-type": "application/vnd.apple.mpegurl" },
    });
  }
  const match = resource.match(/^(0|[1-9]\d{0,4})\.ts$/);
  if (!match) throw new DomainError(404, "Not found");
  const segment = Number(match[1]);
  if (segment * chunkSeconds >= session.duration) throw new DomainError(404, "Not found");
  const id = `${sessionId}:${segment}`;
  let row = database().prepare("SELECT * FROM transcode_jobs WHERE id=?").get(id);
  if (!row) {
    if (
      Number(
        database()
          .prepare("SELECT COUNT(*) AS n FROM transcode_jobs WHERE status IN ('queued','running')")
          .get()?.n,
      ) >= maxJobs
    )
      throw new DomainError(503, "Media workers are busy. Retry shortly");
    database()
      .prepare("INSERT INTO transcode_jobs VALUES(?,?,?,'queued',?)")
      .run(id, sessionId, segment, Date.now());
    void pump();
  }
  const deadline = Date.now() + 25_000;
  while (Date.now() < deadline) {
    if (request.signal.aborted) throw new DomainError(499, "Request cancelled");
    sessionFor(authorize(), sessionId);
    row = database().prepare("SELECT * FROM transcode_jobs WHERE id=?").get(id);
    if (!row || row.status === "failed") throw new DomainError(422, "The media could not be transcoded");
    if (row.status === "complete") {
      const job = jobSchema.parse(row);
      try {
        const bytes = await readFile(filename(job));
        sessionFor(authorize(), sessionId);
        database().prepare("UPDATE transcode_jobs SET updated_at=? WHERE id=?").run(Date.now(), id);
        return new Response(request.method === "HEAD" ? null : bytes, {
          headers: { ...headers, "content-type": "video/mp2t", "content-length": String(bytes.length) },
        });
      } catch (error) {
        if (error instanceof DomainError) throw error;
        database().prepare("DELETE FROM transcode_jobs WHERE id=? AND status='complete'").run(id);
        throw new DomainError(503, "Media cache changed. Retry shortly");
      }
    }
    await delay(100, undefined, { signal: request.signal }).catch(() => {});
  }
  throw new DomainError(503, "Media workers are busy. Retry shortly");
}
