import "server-only";
import { createHash, randomUUID } from "node:crypto";
import {
  chmodSync,
  closeSync,
  constants,
  fstatSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  readSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import { backup, DatabaseSync } from "node:sqlite";
import { z } from "zod";
import { type Account, DomainError, findAccount } from "./accounts";
import { catalogChanged, database, dataDirectory, transaction } from "./data";

declare global {
  var leafwakeMaintenance: boolean | undefined;
}
const manifestSchema = z.object({
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
function schema(db: DatabaseSync) {
  const tables = db
    .prepare(
      "SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )
    .all();
  for (const table of tables)
    z.string()
      .regex(/^[A-Za-z][A-Za-z0-9_]*$/)
      .parse(table.name);
  return { tables, digest: createHash("sha256").update(JSON.stringify(tables)).digest("hex") };
}
function pinnedCopy(filename: string) {
  const fd = openSync(filename, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  let db: DatabaseSync | undefined;
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size > 256 * 1024 * 1024)
      throw new DomainError(400, "Backup must be a regular file under 256 MiB");
    const digest = createHash("sha256"),
      buffer = Buffer.alloc(65536);
    for (;;) {
      const length = readSync(fd, buffer, 0, buffer.length, null);
      if (!length) break;
      digest.update(buffer.subarray(0, length));
    }
    db = new DatabaseSync(process.platform === "linux" ? `/proc/self/fd/${fd}` : filename, {
      readOnly: true,
    });
    db.exec("PRAGMA query_only=ON; PRAGMA trusted_schema=OFF; BEGIN;");
    const opened = db;
    return {
      db: opened,
      digest: digest.digest("hex"),
      bytes: stat.size,
      close() {
        opened.close();
        closeSync(fd);
      },
    };
  } catch (error) {
    db?.close();
    closeSync(fd);
    throw error;
  }
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
export async function createBackup(actor: Account) {
  requireOwner(actor);
  if (globalThis.leafwakeMaintenance) throw new DomainError(409, "Another maintenance operation is running");
  globalThis.leafwakeMaintenance = true;
  const id = randomUUID(),
    filename = resolve(folder(), `${id}.sqlite`),
    temporary = `${filename}.partial`;
  try {
    await backup(database(), temporary);
    chmodSync(temporary, 0o600);
    requireOwner(actor);
    const copy = pinnedCopy(temporary);
    let manifest: z.infer<typeof manifestSchema>;
    try {
      manifest = manifestSchema.parse({
        id,
        sha256: copy.digest,
        createdAt: Date.now(),
        schema: schema(copy.db).digest,
        bytes: copy.bytes,
      });
    } finally {
      copy.close();
    }
    renameSync(temporary, filename);
    writeFileSync(resolve(folder(), `${id}.json`), JSON.stringify(manifest), { flag: "wx", mode: 0o600 });
    return manifest;
  } catch (error) {
    try {
      unlinkSync(temporary);
    } catch {}
    try {
      unlinkSync(filename);
    } catch {}
    throw error;
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
    const metadata = manifestSchema.parse(JSON.parse(readFileSync(resolve(folder(), `${id}.json`), "utf8")));
    const copy = pinnedCopy(resolve(folder(), `${id}.sqlite`));
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
        db.exec("DELETE FROM auth_sessions; UPDATE playback_sessions SET active=0;");
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
    throw error;
  } finally {
    globalThis.leafwakeMaintenance = false;
  }
}
