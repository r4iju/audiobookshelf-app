import "server-only";
import { randomBytes } from "node:crypto";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";

// Next's development module reloads must share the same process-owned connection.
declare global {
  var leafwakeDatabase: DatabaseSync | undefined;
}

export function dataDirectory() {
  return resolve(process.env.LEAFWAKE_DATA_DIR || ".data");
}

export function database() {
  if (globalThis.leafwakeDatabase) return globalThis.leafwakeDatabase;
  const directory = dataDirectory();
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const filename = resolve(directory, "leafwake.sqlite");
  const db = new DatabaseSync(filename);
  chmodSync(filename, 0o600);
  db.exec("PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000; PRAGMA journal_mode = WAL;");
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, username TEXT NOT NULL, username_key TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL, type TEXT NOT NULL CHECK(type IN ('root','admin','user','guest')),
      active INTEGER NOT NULL DEFAULT 1, permissions TEXT NOT NULL, libraries TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS auth_sessions (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      access_hash TEXT NOT NULL UNIQUE, refresh_hash TEXT NOT NULL UNIQUE,
      access_expires_at INTEGER NOT NULL, refresh_expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS auth_sessions_user ON auth_sessions(user_id);
    INSERT OR IGNORE INTO schema_version(version) VALUES (1);
  `);
  const version = db.prepare("SELECT MAX(version) AS version FROM schema_version").get();
  if (version && typeof version.version === "number" && version.version < 2) {
    db.exec(`BEGIN IMMEDIATE;
      ALTER TABLE users ADD COLUMN tags TEXT NOT NULL DEFAULT '[]';
      CREATE TABLE login_attempts (key TEXT PRIMARY KEY, attempts INTEGER NOT NULL, expires_at INTEGER NOT NULL);
      INSERT INTO schema_version(version) VALUES (2);
      COMMIT;`);
  }
  db.exec(`
    CREATE TABLE IF NOT EXISTS migrations (id TEXT PRIMARY KEY, digest TEXT NOT NULL, scope TEXT NOT NULL, content TEXT NOT NULL, UNIQUE(digest,scope));
    CREATE TABLE IF NOT EXISTS migration_archive (digest TEXT NOT NULL, table_name TEXT NOT NULL, row_key TEXT NOT NULL, content TEXT NOT NULL, PRIMARY KEY(digest,table_name,row_key));
    CREATE TABLE IF NOT EXISTS bookmarks (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, item_id TEXT NOT NULL REFERENCES catalog_items(id), content TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS libraries (id TEXT PRIMARY KEY, content TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS catalog_items (id TEXT PRIMARY KEY, library_id TEXT NOT NULL REFERENCES libraries(id),
      source_path TEXT NOT NULL, content TEXT NOT NULL, UNIQUE(library_id, source_path));
    CREATE TABLE IF NOT EXISTS media_files (id TEXT PRIMARY KEY, item_id TEXT NOT NULL REFERENCES catalog_items(id),
      source_path TEXT NOT NULL, content TEXT NOT NULL, UNIQUE(item_id, source_path));
    CREATE TABLE IF NOT EXISTS playback_sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL REFERENCES catalog_items(id), content TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
      expires_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS media_progress (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL REFERENCES catalog_items(id), episode_id TEXT NOT NULL DEFAULT '', content TEXT NOT NULL,
      UNIQUE(user_id, item_id, episode_id));
    CREATE TABLE IF NOT EXISTS listening_reports (user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES catalog_items(id), episode_id TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL, PRIMARY KEY(user_id, id));
    CREATE TABLE IF NOT EXISTS progress_resets (user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL REFERENCES catalog_items(id), episode_id TEXT NOT NULL DEFAULT '', cutoff INTEGER NOT NULL,
      PRIMARY KEY(user_id, item_id, episode_id));
    CREATE TABLE IF NOT EXISTS progress_reset_commands (user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES catalog_items(id), episode_id TEXT NOT NULL DEFAULT '',
      generation INTEGER NOT NULL, PRIMARY KEY(user_id,id));
    CREATE TABLE IF NOT EXISTS deleted_progress (user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      id TEXT NOT NULL, PRIMARY KEY(user_id,id));
    CREATE TABLE IF NOT EXISTS scan_runs (id TEXT PRIMARY KEY, library_id TEXT NOT NULL REFERENCES libraries(id),
      status TEXT NOT NULL, started_at INTEGER NOT NULL, completed_at INTEGER, report TEXT);
    INSERT OR IGNORE INTO schema_version(version) VALUES (3);
    UPDATE scan_runs SET status = 'interrupted', completed_at = CAST(strftime('%s','now') AS INTEGER) * 1000
      WHERE status = 'running';
  `);
  globalThis.leafwakeDatabase = db;
  if (
    !db
      .prepare("PRAGMA table_info(progress_resets)")
      .all()
      .some((column) => column.name === "generation")
  ) {
    db.exec("ALTER TABLE progress_resets ADD COLUMN generation INTEGER NOT NULL DEFAULT 1;");
  }
  if (
    !db
      .prepare("PRAGMA table_info(users)")
      .all()
      .some((column) => column.name === "archive")
  )
    db.exec("ALTER TABLE users ADD COLUMN archive TEXT NOT NULL DEFAULT '{}';");
  db.exec(
    "INSERT OR IGNORE INTO schema_version(version) VALUES (4); INSERT OR IGNORE INTO schema_version(version) VALUES (5);",
  );
  if (Number(db.prepare("SELECT MAX(version) AS version FROM schema_version").get()?.version) < 6) {
    db.exec(`BEGIN IMMEDIATE;
      CREATE TABLE media_files_v6 (id TEXT NOT NULL, item_id TEXT NOT NULL REFERENCES catalog_items(id),
        source_path TEXT NOT NULL, content TEXT NOT NULL, PRIMARY KEY(item_id,id), UNIQUE(item_id,source_path));
      INSERT INTO media_files_v6 SELECT id,item_id,source_path,content FROM media_files;
      DROP TABLE media_files;
      ALTER TABLE media_files_v6 RENAME TO media_files;
      INSERT INTO schema_version(version) VALUES(6);
      COMMIT;`);
  }
  return db;
}

export function progressGeneration(userId: string, itemId: string, episodeId = "") {
  const row = database()
    .prepare("SELECT generation FROM progress_resets WHERE user_id=? AND item_id=? AND episode_id=?")
    .get(userId, itemId, episodeId);
  return row && typeof row.generation === "number" ? row.generation : 0;
}

export function progressGenerations(userId: string, itemId: string) {
  return Object.fromEntries(
    database()
      .prepare("SELECT episode_id,generation FROM progress_resets WHERE user_id=? AND item_id=?")
      .all(userId, itemId)
      .map((row) => [String(row.episode_id), Number(row.generation)]),
  );
}

export function transaction<T>(
  work: (db: DatabaseSync) => T,
  change?: { userId: string; itemId?: string },
): T {
  const db = database();
  db.exec("BEGIN IMMEDIATE");
  let value: T;
  try {
    value = work(db);
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
  globalThis.leafwakeRealtimeChanged?.(change);
  return value;
}

export function catalogChanged() {
  globalThis.leafwakeCatalogRevision = (globalThis.leafwakeCatalogRevision ?? 0) + 1;
  globalThis.leafwakeRealtimeChanged?.({ catalog: true });
}

export function initialized() {
  const ready = Boolean(database().prepare("SELECT id FROM users LIMIT 1").get());
  if (!ready) setupKey();
  return ready;
}

export function setupKey() {
  const configured = process.env.LEAFWAKE_SETUP_KEY;
  if (configured) {
    if (configured.length < 16) throw new Error("Setup key must have at least 16 characters");
    return configured;
  }
  database();
  const filename = resolve(dataDirectory(), "setup-key");
  try {
    writeFileSync(filename, randomBytes(32).toString("base64url"), { flag: "wx", mode: 0o600 });
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "EEXIST")) throw error;
  }
  chmodSync(filename, 0o600);
  return readFileSync(filename, "utf8").trim();
}

export function tokenSigningKey() {
  const filename = resolve(dataDirectory(), "token-signing-key");
  try {
    writeFileSync(filename, randomBytes(32).toString("base64url"), { flag: "wx", mode: 0o600 });
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "EEXIST")) throw error;
  }
  chmodSync(filename, 0o600);
  return readFileSync(filename, "utf8").trim();
}
