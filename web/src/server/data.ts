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
  globalThis.leafwakeDatabase = db;
  return db;
}

export function transaction<T>(work: (db: DatabaseSync) => T): T {
  const db = database();
  db.exec("BEGIN IMMEDIATE");
  try {
    const value = work(db);
    db.exec("COMMIT");
    return value;
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
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
