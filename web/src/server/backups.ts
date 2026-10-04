import "server-only";
import { chmodSync, mkdirSync, readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { z } from "zod";
import {
  createSnapshot,
  pinnedDatabase as pinnedCopy,
  readBackup,
  databaseSchema as schema,
} from "../../backup-format.mjs";
import { type Account, DomainError, findAccount } from "./accounts";
import { catalogChanged, database, dataDirectory, tokenSigningKey, transaction } from "./data";

declare global {
  var leafwakeMaintenance: boolean | undefined;
  var leafwakeInFlightRequests: number | undefined;
}
const manifestSchema = z.looseObject({
  id: z.string().uuid(),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  createdAt: z.number(),
  schema: z.string(),
  bytes: z.number(),
});
function requireOwner(actor: Account) {
  const current = findAccount(actor.id);
  if (!current.active) throw new DomainError(401, "Sign-in required");
  if (current.type !== "root") throw new DomainError(403, "Owner access required");
}
function folder() {
  const path = resolve(dataDirectory(), "backups");
  mkdirSync(path, { recursive: true, mode: 0o700 });
  chmodSync(path, 0o700);
  return path;
}
export function listBackups(actor: Account) {
  requireOwner(actor);
  return {
    backups: readdirSync(folder())
      .filter((name) => /^[a-f0-9-]{36}\.json$/.test(name))
      .map((name) => manifestSchema.parse(JSON.parse(readFileSync(resolve(folder(), name), "utf8"))))
      .sort((a, b) => b.createdAt - a.createdAt),
  };
}
export async function createBackup(
  actor: Account,
  authorize: () => Account = () => actor,
  scheduledId?: string,
) {
  requireOwner(actor);
  if (globalThis.leafwakeMaintenance) throw new DomainError(409, "Another maintenance operation is running");
  globalThis.leafwakeMaintenance = true;
  try {
    return await createSnapshot(database(), dataDirectory(), () => requireOwner(authorize()), scheduledId);
  } catch (error) {
    if (error instanceof DomainError) throw error;
    throw new DomainError(
      409,
      "Backup could not complete. Check data-folder permissions, free space and the 256 MiB database limit.",
    );
  } finally {
    globalThis.leafwakeMaintenance = false;
  }
}

export function restoreBackup(actor: Account, id: string) {
  requireOwner(actor);
  z.string().uuid().parse(id);
  if (globalThis.leafwakeMaintenance) throw new DomainError(409, "Another maintenance operation is running");
  globalThis.leafwakeMaintenance = true;
  try {
    if ((globalThis.leafwakeInFlightRequests ?? 0) > 1)
      throw new DomainError(
        409,
        "Pause playback and wait for active requests to finish before restoring, or use a new empty volume with the maintenance CLI.",
      );
    if (
      database()
        .prepare(
          "SELECT id FROM podcast_jobs WHERE state IN ('queued','running') UNION ALL SELECT id FROM transcode_jobs WHERE status IN ('queued','running') UNION ALL SELECT id FROM scan_runs WHERE status='running' UNION ALL SELECT item_id AS id FROM podcast_subscriptions WHERE lease_until>CAST(strftime('%s','now') AS INTEGER)*1000 LIMIT 1",
        )
        .get()
    )
      throw new DomainError(
        409,
        "Wait for scans and media jobs to finish, or restore into a new empty volume with the image maintenance CLI.",
      );
    const metadata = manifestSchema.parse(JSON.parse(readFileSync(resolve(folder(), `${id}.json`), "utf8")));
    const copy =
      "formatVersion" in metadata ? readBackup(folder(), id) : pinnedCopy(resolve(folder(), `${id}.sqlite`));
    if ("key" in copy && copy.key !== tokenSigningKey()) {
      copy.close();
      throw new DomainError(
        409,
        "This backup belongs to another installation key. Restore it into a new empty volume with the image maintenance CLI.",
      );
    }
    try {
      if (
        copy.digest !== metadata.sha256 ||
        schema(copy.db).digest !== schema(database()).digest ||
        metadata.schema !== schema(copy.db).digest
      )
        throw new DomainError(409, "Backup integrity or schema differs from this installation");
      const check = copy.db.prepare("PRAGMA quick_check").get();
      if (
        !check ||
        Object.values(check)[0] !== "ok" ||
        copy.db.prepare("PRAGMA foreign_key_check").all().length
      )
        throw new DomainError(409, "Backup failed SQLite validation");
      const owner = copy.db.prepare("SELECT id FROM users WHERE type='root' AND active=1").all();
      if (owner.length !== 1) throw new DomainError(409, "Backup must contain one active owner");
      transaction((db) => {
        requireOwner(actor);
        db.exec("PRAGMA defer_foreign_keys=ON;");
        const tables = schema(copy.db).tables;
        for (const table of tables) db.exec(`DELETE FROM "${z.string().parse(table.name)}"`);
        for (const table of tables) {
          const name = z.string().parse(table.name);
          const columns = copy.db
            .prepare(`PRAGMA table_info("${name}")`)
            .all()
            .map((column) =>
              z
                .string()
                .regex(/^[A-Za-z][A-Za-z0-9_]*$/)
                .parse(column.name),
            );
          const insert = db.prepare(
            `INSERT INTO "${name}" (${columns.map((column) => `"${column}"`).join(",")}) VALUES(${columns.map(() => "?").join(",")})`,
          );
          for (const row of copy.db.prepare(`SELECT * FROM "${name}"`).iterate())
            insert.run(
              ...columns.map((column) => {
                const value = row[column];
                if (value === undefined) throw new DomainError(409, "Backup column is missing");
                return value;
              }),
            );
        }
        db.exec(
          "DELETE FROM auth_sessions; DELETE FROM openid_flows; UPDATE playback_sessions SET active=0; UPDATE podcast_jobs SET state='queued',lease_until=NULL WHERE state='running'; UPDATE transcode_jobs SET status='queued' WHERE status='running'; UPDATE podcast_subscriptions SET lease_until=NULL; UPDATE scan_runs SET status='interrupted',completed_at=CAST(strftime('%s','now') AS INTEGER)*1000 WHERE status='running';",
        );
        if (db.prepare("PRAGMA foreign_key_check").all().length)
          throw new DomainError(409, "Restored relationships failed validation");
      });
      catalogChanged();
      return { success: true, signInAgain: true };
    } finally {
      copy.close();
    }
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT")
      throw new DomainError(404, "Backup not found");
    if (error instanceof DomainError) throw error;
    throw new DomainError(
      409,
      "Backup failed integrity or schema validation. Preserve the active data volume and inspect the selected backup with the maintenance CLI.",
    );
  } finally {
    globalThis.leafwakeMaintenance = false;
  }
}
