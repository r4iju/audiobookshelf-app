import "server-only";
import { createHash, randomBytes, randomUUID, scrypt, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { database, initialized, setupKey, transaction } from "./data";

function derive(password: string, salt: string, length: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, length, (error, key) => {
      if (error) reject(error);
      else resolve(key);
    });
  });
}
export class DomainError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}
const permissions = z.object({
  download: z.boolean(),
  update: z.boolean(),
  delete: z.boolean(),
  upload: z.boolean(),
  accessExplicitContent: z.boolean(),
});
const userRow = z.object({
  id: z.string(),
  username: z.string(),
  password_hash: z.string(),
  type: z.enum(["root", "admin", "user", "guest"]),
  active: z.number(),
  permissions: z.string(),
  libraries: z.string(),
  created_at: z.number(),
});
export type Account = z.infer<typeof userRow>;
const rootPermissions = {
  download: true,
  update: true,
  delete: true,
  upload: true,
  accessExplicitContent: true,
};
export const credentialsSchema = z.object({
  username: z.string().min(1).max(256),
  password: z.string().min(1).max(512),
});
export const setupSchema = credentialsSchema.extend({
  username: z
    .string()
    .trim()
    .min(3)
    .max(64)
    .regex(/^[\p{L}\p{N}._-]+$/u),
  password: z.string().min(12).max(512),
  setupKey: z.string().min(1).max(256),
});
function digest(value: string) {
  return createHash("sha256").update(value).digest("hex");
}
function equal(left: string, right: string) {
  const a = Buffer.from(digest(left));
  const b = Buffer.from(digest(right));
  return timingSafeEqual(a, b);
}
async function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const key = await derive(password, salt, 64);
  return `scrypt$${salt}$${key.toString("hex")}`;
}
async function matchesPassword(password: string, encoded: string) {
  const [algorithm, salt, hash] = encoded.split("$");
  if (algorithm !== "scrypt" || !salt || !hash) return false;
  const key = await derive(password, salt, 64);
  const expected = Buffer.from(hash, "hex");
  return key.length === expected.length && timingSafeEqual(key, expected);
}
export async function createOwner(input: z.infer<typeof setupSchema>) {
  if (initialized()) throw new DomainError(409, "This server is already initialized");
  if (!equal(input.setupKey, setupKey())) throw new DomainError(403, "The setup key is required");
  const password = await hashPassword(input.password);
  transaction((db) => {
    if (db.prepare("SELECT id FROM users LIMIT 1").get())
      throw new DomainError(409, "This server is already initialized");
    db.prepare(
      "INSERT INTO users(id, username, username_key, password_hash, type, permissions, created_at) VALUES (?, ?, ?, ?, 'root', ?, ?)",
    ).run(
      randomUUID(),
      input.username,
      input.username.toLowerCase(),
      password,
      JSON.stringify(rootPermissions),
      Date.now(),
    );
  });
}
function visibleUser(user: Account) {
  return {
    id: user.id,
    username: user.username,
    type: user.type,
    permissions: permissions.parse(JSON.parse(user.permissions)),
    librariesAccessible: z.array(z.string()).parse(JSON.parse(user.libraries)),
    mediaProgress: [],
    bookmarks: [],
    seriesHideFromContinueListening: [],
    createdAt: user.created_at,
  };
}
function issueSession(user: Account) {
  const accessToken = randomBytes(32).toString("base64url");
  const refreshToken = randomBytes(48).toString("base64url");
  const now = Date.now();
  database()
    .prepare("INSERT INTO auth_sessions VALUES (?, ?, ?, ?, ?, ?, ?)")
    .run(
      randomUUID(),
      user.id,
      digest(accessToken),
      digest(refreshToken),
      now + 15 * 60_000,
      now + 30 * 86400_000,
      now,
    );
  return {
    user: { ...visibleUser(user), accessToken, refreshToken },
    userDefaultLibraryId: null,
    serverSettings: { version: "1.0.0-dev", language: "en" },
    ereaderDevices: [],
  };
}
export async function passwordLogin(input: z.infer<typeof credentialsSchema>) {
  const row = database()
    .prepare("SELECT * FROM users WHERE username_key = ? AND active = 1")
    .get(input.username.toLowerCase());
  const user = row ? userRow.parse(row) : null;
  // Unknown accounts pay the same derivation cost as valid credentials.
  const encoded = user?.password_hash ?? `scrypt$00000000000000000000000000000000$${"0".repeat(128)}`;
  if (!(await matchesPassword(input.password, encoded)) || !user)
    throw new DomainError(401, "Invalid username or password");
  return issueSession(user);
}
export function authenticate(token: string | null) {
  if (!token || token.length > 256) throw new DomainError(401, "Sign-in required");
  const row = database()
    .prepare(`SELECT u.* FROM users u JOIN auth_sessions s ON s.user_id = u.id
    WHERE s.access_hash = ? AND s.access_expires_at > ? AND u.active = 1`)
    .get(digest(token), Date.now());
  if (!row) throw new DomainError(401, "Sign-in required");
  return userRow.parse(row);
}
export function accountResponse(user: Account) {
  return visibleUser(user);
}
export function refreshSession(token: string | null) {
  if (!token || token.length > 256) throw new DomainError(401, "Sign-in required");
  return transaction((db) => {
    const row = db
      .prepare(`SELECT u.* FROM users u JOIN auth_sessions s ON s.user_id = u.id
      WHERE s.refresh_hash = ? AND s.refresh_expires_at > ? AND u.active = 1`)
      .get(digest(token), Date.now());
    if (!row) throw new DomainError(401, "Sign-in required");
    db.prepare("DELETE FROM auth_sessions WHERE refresh_hash = ?").run(digest(token));
    return issueSession(userRow.parse(row));
  });
}
