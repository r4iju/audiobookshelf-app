import "server-only";
import { accessSync, constants } from "node:fs";
import { z } from "zod";
import { readiness } from "../../diagnostics.mjs";
import { type Account, DomainError, findAccount } from "./accounts";
import { database, dataDirectory } from "./data";
export async function diagnostics(actor: Account) {
  const current = findAccount(actor.id);
  if (!current.active) throw new DomainError(401, "Sign-in required");
  if (current.type !== "root") throw new DomainError(403, "Owner access required");
  const db = database(),
    base = await readiness(dataDirectory());
  const checked = db.prepare("PRAGMA quick_check(1)").get(),
    integrity = checked && Object.values(checked)[0] === "ok" ? "ok" : "failed";
  const counts = (table: "podcast_jobs" | "transcode_jobs" | "scan_runs", column: "state" | "status") =>
    Object.fromEntries(
      db
        .prepare(`SELECT ${column} AS status,COUNT(*) AS count FROM ${table} GROUP BY ${column}`)
        .all()
        .map((row) => [String(row.status), Number(row.count)]),
    );
  const recentFailures = db
    .prepare(
      "SELECT 'podcast' AS kind,id,updated_at AS occurredAt FROM podcast_jobs WHERE state='failed' UNION ALL SELECT 'transcode',id,updated_at FROM transcode_jobs WHERE status='failed' UNION ALL SELECT 'scan',id,completed_at FROM scan_runs WHERE status IN ('failed','interrupted') ORDER BY occurredAt DESC LIMIT 20",
    )
    .all()
    .map((row) => ({
      kind: String(row.kind),
      id: String(row.id),
      occurredAt: Number(row.occurredAt),
      message:
        row.kind === "scan"
          ? "Scan failed or was interrupted. Check library mounts and rescan."
          : "Media job failed. Check media mounts, remote source availability and configured job limits, then retry.",
    }));
  const mounts = [];
  let mountsTruncated = Number(db.prepare("SELECT COUNT(*) AS count FROM libraries").get()?.count) > 100;
  for (const row of db.prepare("SELECT id,content FROM libraries LIMIT 100").iterate()) {
    const library = z
      .object({ folders: z.array(z.object({ fullPath: z.string() })) })
      .parse(JSON.parse(String(row.content)));
    if (library.folders.length > 10) mountsTruncated = true;
    for (const folder of library.folders.slice(0, 10)) {
      let readable = false;
      try {
        accessSync(folder.fullPath, constants.R_OK | constants.X_OK);
        readable = true;
      } catch {}
      mounts.push({ libraryId: String(row.id), path: folder.fullPath, readable });
    }
  }
  const issues = [...base.issues];
  if (mountsTruncated)
    issues.push(
      "Media mount checks were truncated to100 libraries and ten folders per library. Check the remaining mounts on the host before treating this installation as fully ready.",
    );
  if (integrity !== "ok")
    issues.push(
      "Database integrity check failed. Stop writes, preserve the volume and restore a validated backup into a new volume.",
    );
  if (mounts.some((m) => !m.readable))
    issues.push(
      "Some media folders are unavailable. Restore their listed mounts; do not rescan missing media as a substitute for restoring files.",
    );
  return {
    ...base,
    ready: issues.length === 0,
    issues,
    database: {
      integrity,
      schemaVersion: Number(db.prepare("SELECT MAX(version) AS version FROM schema_version").get()?.version),
    },
    jobs: {
      podcasts: counts("podcast_jobs", "state"),
      transcodes: counts("transcode_jobs", "status"),
      scans: counts("scan_runs", "status"),
    },
    recentFailures,
    mounts,
    mountsTruncated,
  };
}
