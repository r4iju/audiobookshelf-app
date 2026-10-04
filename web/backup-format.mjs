import { createHash, randomUUID } from "node:crypto";
import {
  chmodSync,
  closeSync,
  constants,
  existsSync,
  fstatSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import { backup, DatabaseSync } from "node:sqlite";
import { z } from "zod";

export const maximumSchemaVersion = 16;
const digest = z.string().regex(/^[a-f0-9]{64}$/);
export const backupManifestSchema = z.object({
  id: z.string().uuid(),
  sha256: digest,
  createdAt: z.number().finite(),
  schema: digest,
  bytes: z
    .number()
    .int()
    .min(1)
    .max(256 * 1024 * 1024),
  formatVersion: z.literal(2),
  schemaVersion: z.number().int().min(1).max(maximumSchemaVersion),
  scheduled: z.boolean().optional(),
  keyIncluded: z.literal(true),
  keySha256: digest,
  media: z.object({
    included: z.literal(false),
    requiredMounts: z.array(z.string().max(4096)).max(1024),
    managedDirectory: z.string().max(4096),
  }),
});
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
export function databaseSchema(db) {
  const tables = db
    .prepare(
      "SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )
    .all();
  for (const table of tables)
    z.string()
      .regex(/^[A-Za-z][A-Za-z0-9_]*$/)
      .parse(table.name);
  return { tables, digest: sha(JSON.stringify(tables)) };
}
function file(filename, maximum) {
  const fd = openSync(filename, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size > maximum)
      throw Error("Backup file is invalid or exceeds its size limit");
    return { fd, stat };
  } catch (error) {
    closeSync(fd);
    throw error;
  }
}
function privateText(filename, maximum) {
  const { fd } = file(filename, maximum);
  try {
    return readFileSync(fd, "utf8");
  } finally {
    closeSync(fd);
  }
}
export function pinnedDatabase(filename) {
  const { fd, stat } = file(filename, 256 * 1024 * 1024);
  let db;
  try {
    const hash = createHash("sha256"),
      buffer = Buffer.alloc(65536);
    for (;;) {
      const length = readSync(fd, buffer, 0, buffer.length, null);
      if (!length) break;
      hash.update(buffer.subarray(0, length));
    }
    db = new DatabaseSync(process.platform === "linux" ? `/proc/self/fd/${fd}` : filename, {
      readOnly: true,
    });
    db.exec("PRAGMA query_only=ON; PRAGMA trusted_schema=OFF; BEGIN;");
    return {
      db,
      digest: hash.digest("hex"),
      bytes: stat.size,
      close() {
        db.close();
        closeSync(fd);
      },
    };
  } catch (error) {
    db?.close();
    closeSync(fd);
    throw error;
  }
}
export function validateDatabase(db) {
  const check = db.prepare("PRAGMA quick_check").get();
  if (!check || Object.values(check)[0] !== "ok" || db.prepare("PRAGMA foreign_key_check").all().length)
    throw Error("Backup failed SQLite validation");
  if (db.prepare("SELECT id FROM users WHERE type='root' AND active=1").all().length !== 1)
    throw Error("Backup must contain one active owner");
}
export function readBackup(folder, id) {
  z.string().uuid().parse(id);
  const manifest = backupManifestSchema.parse(
    JSON.parse(privateText(resolve(folder, `${id}.json`), 128 * 1024)),
  );
  if (manifest.id !== id) throw Error("Backup identity differs from its manifest");
  const key = privateText(resolve(folder, `${id}.key`), 128).trim();
  if (!/^[A-Za-z0-9_-]{43}$/.test(key) || sha(key) !== manifest.keySha256)
    throw Error("Backup key integrity failed");
  const copy = pinnedDatabase(resolve(folder, `${id}.sqlite`));
  try {
    if (
      copy.digest !== manifest.sha256 ||
      copy.bytes !== manifest.bytes ||
      databaseSchema(copy.db).digest !== manifest.schema ||
      Number(copy.db.prepare("SELECT MAX(version) AS v FROM schema_version").get()?.v) !==
        manifest.schemaVersion
    )
      throw Error("Backup integrity or schema differs from its manifest");
    validateDatabase(copy.db);
    return { ...copy, manifest, key };
  } catch (error) {
    copy.close();
    throw error;
  }
}
export async function createSnapshot(db, directory, authorize = () => {}, scheduledId) {
  const folder = resolve(directory, "backups");
  mkdirSync(folder, { recursive: true, mode: 0o700 });
  chmodSync(folder, 0o700);
  const id = scheduledId ? z.string().uuid().parse(scheduledId) : randomUUID(),
    target = resolve(folder, `${id}.sqlite`),
    temporary = `${target}.partial`;
  const key = privateText(resolve(directory, "token-signing-key"), 128).trim();
  if (!/^[A-Za-z0-9_-]{43}$/.test(key)) throw Error("Installation key is invalid");
  if (scheduledId) {
    if (existsSync(resolve(folder, `${id}.json`))) {
      const previous = readBackup(folder, id);
      try {
        if (previous.key !== key) throw Error("Scheduled backup key differs");
        authorize();
        return previous.manifest;
      } finally {
        previous.close();
      }
    }
    for (const path of [
      temporary,
      target,
      resolve(folder, `${id}.key`),
      resolve(folder, `${id}.json.partial`),
    ])
      rmSync(path, { force: true });
  }
  const deadline = Date.now() + 60_000;
  try {
    await backup(db, temporary, {
      progress({ totalPages }) {
        authorize();
        if (Date.now() > deadline || totalPages * 4096 > 256 * 1024 * 1024)
          throw Error("Backup exceeded its time or size limit");
      },
    });
    const snapshot = new DatabaseSync(temporary);
    try {
      snapshot.exec("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;");
    } finally {
      snapshot.close();
    }
    chmodSync(temporary, 0o600);
    authorize();
    const copy = pinnedDatabase(temporary);
    let manifest;
    try {
      validateDatabase(copy.db);
      const mounts = new Set();
      for (const row of copy.db.prepare("SELECT content FROM libraries").iterate()) {
        const library = z
          .object({ folders: z.array(z.object({ fullPath: z.string() })).default([]) })
          .parse(JSON.parse(String(row.content)));
        for (const f of library.folders) mounts.add(f.fullPath);
      }
      manifest = backupManifestSchema.parse({
        id,
        sha256: copy.digest,
        bytes: copy.bytes,
        schema: databaseSchema(copy.db).digest,
        createdAt: Date.now(),
        formatVersion: 2,
        scheduled: Boolean(scheduledId),
        schemaVersion: Number(copy.db.prepare("SELECT MAX(version) AS v FROM schema_version").get()?.v),
        keyIncluded: true,
        keySha256: sha(key),
        media: {
          included: false,
          requiredMounts: [...mounts].sort(),
          managedDirectory: resolve(directory, "media"),
        },
      });
    } finally {
      copy.close();
    }
    const keyFile = resolve(folder, `${id}.key`),
      manifestFile = resolve(folder, `${id}.json`),
      manifestTemporary = `${manifestFile}.partial`;
    writeFileSync(keyFile, key, { flag: "wx", mode: 0o600 });
    for (const path of [temporary, keyFile]) {
      const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
      try {
        fsyncSync(fd);
      } finally {
        closeSync(fd);
      }
    }
    renameSync(temporary, target);
    writeFileSync(manifestTemporary, JSON.stringify(manifest), { flag: "wx", mode: 0o600 });
    const published = openSync(manifestTemporary, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      fsyncSync(published);
    } finally {
      closeSync(published);
    }
    renameSync(manifestTemporary, manifestFile);
    const committed = openSync(folder, constants.O_RDONLY);
    try {
      fsyncSync(committed);
    } finally {
      closeSync(committed);
    }
    return manifest;
  } catch (error) {
    for (const path of [
      temporary,
      target,
      resolve(folder, `${id}.key`),
      resolve(folder, `${id}.json`),
      resolve(folder, `${id}.json.partial`),
    ])
      rmSync(path, { force: true });
    throw error;
  }
}
