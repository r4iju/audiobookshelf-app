import { execFile } from "node:child_process";
import { accessSync, closeSync, constants, existsSync, fstatSync, openSync, statfsSync } from "node:fs";
import { resolve } from "node:path";
import { promisify } from "node:util";

const execute = promisify(execFile);
let tools;
let checkedAt = 0;
async function tool(name) {
  try {
    const { stdout } = await execute(name, ["-version"], {
      timeout: 2000,
      maxBuffer: 16_384,
      encoding: "utf8",
    });
    const version = stdout.match(/^(?:ffmpeg|ffprobe) version ([\w.+:-]{1,80})/);
    return { available: Boolean(version), version: version?.[1] ?? null };
  } catch {
    return { available: false, version: null };
  }
}
export async function readiness(directory) {
  if (!tools || Date.now() - checkedAt > 60_000) {
    checkedAt = Date.now();
    tools = Promise.all([tool("ffmpeg"), tool("ffprobe")]).then(([ffmpeg, ffprobe]) => ({ ffmpeg, ffprobe }));
  }
  let writable = false,
    freeBytes = 0,
    databaseBytes = 0;
  try {
    accessSync(directory, constants.W_OK | constants.X_OK);
    const fs = statfsSync(directory, { bigint: true });
    freeBytes = Number(fs.bavail * fs.bsize);
    writable = freeBytes > 1024 * 1024;
    const fd = openSync(
      resolve(directory, "leafwake.sqlite"),
      constants.O_RDWR | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );
    try {
      const stat = fstatSync(fd);
      writable = writable && stat.isFile();
      databaseBytes = stat.size;
    } finally {
      closeSync(fd);
    }
  } catch {
    writable = false;
  }
  const result = await tools;
  const issues = [];
  if (existsSync(resolve(directory, ".restore-in-progress")))
    issues.push("Restore is incomplete. Keep the original volume and retry into a new empty volume.");
  if (!writable)
    issues.push(
      "Data storage is unavailable, unwritable or has less than 1 MiB free. Check the mounted data volume and available space.",
    );
  if (!result.ffmpeg.available || !result.ffprobe.available)
    issues.push(
      "Media tools are unavailable. Use the complete Leafwake image with FFmpeg and FFprobe installed.",
    );
  return {
    ready: issues.length === 0,
    issues,
    tools: result,
    storage: { writable, freeBytes, databaseBytes },
  };
}
