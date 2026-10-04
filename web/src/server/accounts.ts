import { serverSettings } from "./server-settings";
import "server-only";
import { createHash, createHmac, randomBytes, randomUUID, scrypt, timingSafeEqual } from "node:crypto";
import { compare } from "bcryptjs";
import { z } from "zod";
import { bookmarksFor } from "./bookmarks";
import { database, initialized, setupKey, tokenSigningKey, transaction } from "./data";
import { allProgress } from "./progress";

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
export const permissions = z.object({
  download: z.boolean(),
  update: z.boolean(),
  delete: z.boolean(),
  upload: z.boolean(),
  accessExplicitContent: z.boolean(),
  accessAllLibraries: z.boolean().default(true),
  accessAllTags: z.boolean().default(true),
  selectedTagsNotAccessible: z.boolean().default(false),
});
const userRow = z.object({
  id: z.string(),
  username: z.string(),
  password_hash: z.string(),
  type: z.enum(["root", "admin", "user", "guest"]),
  active: z.number(),
  permissions: z.string(),
  libraries: z.string(),
  tags: z.string(),
  created_at: z.number(),
  archive: z.string().optional(),
});
export type Account = z.infer<typeof userRow>;
const rootPermissions = {
  download: true,
  update: true,
  delete: true,
  upload: true,
  accessExplicitContent: true,
  accessAllLibraries: true,
  accessAllTags: true,
  selectedTagsNotAccessible: false,
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
export async function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const key = await derive(password, salt, 64);
  return `scrypt$${salt}$${key.toString("hex")}`;
}
async function matchesPassword(password: string, encoded: string) {
  if (/^\$2[aby]\$(0[4-9]|1[0-2])\$[./A-Za-z0-9]{53}$/.test(encoded)) return compare(password, encoded);
  const [algorithm, salt, hash] = encoded.split("$");
  if (algorithm !== "scrypt" || !salt || !hash) return false;
  const key = await derive(password, salt, 64);
  const expected = Buffer.from(hash, "hex");
  return key.length === expected.length && timingSafeEqual(key, expected);
}
export function requireSetupKey(value: string) {
  if (!equal(value, setupKey())) throw new DomainError(403, "The setup key is required");
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
    ...(user.archive
      ? z
          .object({ email: z.string().nullable().optional(), isLocked: z.boolean().optional() })
          .parse(JSON.parse(user.archive))
      : {}),
    id: user.id,
    username: user.username,
    type: user.type,
    permissions: permissions.parse(JSON.parse(user.permissions)),
    librariesAccessible: z.array(z.string()).parse(JSON.parse(user.libraries)),
    mediaProgress: allProgress(user),
    bookmarks: bookmarksFor(user),
    seriesHideFromContinueListening: [],
    itemTagsSelected: z.array(z.string()).parse(JSON.parse(user.tags)),
    isActive: Boolean(user.active),
    createdAt: user.created_at,
  };
}
function issueSession(user: Account) {
  const issued = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({ sub: user.id, iat: issued, exp: issued + 15 * 60, jti: randomUUID() }),
  ).toString("base64url");
  const signed = `${header}.${payload}`;
  const accessToken = `${signed}.${createHmac("sha256", tokenSigningKey()).update(signed).digest("base64url")}`;
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
    serverSettings: {
      version: "1.0.0-dev",
      language: serverSettings().language,
      name: serverSettings().serverName,
    },
    ereaderDevices: [],
  };
}
export async function passwordLogin(input: z.infer<typeof credentialsSchema>) {
  const key = digest(input.username.toLowerCase());
  const now = Date.now();
  const attempt = transaction((db) => {
    db.prepare("DELETE FROM login_attempts WHERE expires_at <= ?").run(now);
    db.prepare(`INSERT INTO login_attempts VALUES (?, 1, ?) ON CONFLICT(key)
      DO UPDATE SET attempts = attempts + 1`).run(key, now + serverSettings().rateLimitLoginWindow);
    return db.prepare("SELECT attempts FROM login_attempts WHERE key = ?").get(key);
  });
  if (
    attempt &&
    typeof attempt.attempts === "number" &&
    attempt.attempts > serverSettings().rateLimitLoginRequests
  )
    throw new DomainError(429, "Too many sign-in attempts. Try again later");
  const row = database()
    .prepare("SELECT * FROM users WHERE username_key = ? AND active = 1")
    .get(input.username.toLowerCase());
  const user = row ? userRow.parse(row) : null;
  // Unknown accounts pay the same derivation cost as valid credentials.
  const encoded = user?.password_hash ?? `scrypt$00000000000000000000000000000000$${"0".repeat(128)}`;
  if (!(await matchesPassword(input.password, encoded)) || !user)
    throw new DomainError(401, "Invalid username or password");
  return transaction((db) => {
    const row = db.prepare("SELECT * FROM users WHERE id = ?").get(user.id);
    const current = row ? userRow.parse(row) : null;
    if (
      !current?.active ||
      current.password_hash !== user.password_hash ||
      current.username.toLowerCase() !== input.username.toLowerCase()
    )
      throw new DomainError(401, "Invalid username or password");
    db.prepare("DELETE FROM login_attempts WHERE key = ?").run(key);
    return issueSession(current);
  });
}
export function authenticate(token: string | null) {
  if (!token || token.length > 1024) throw new DomainError(401, "Sign-in required");
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
  if (!token || token.length > 1024) throw new DomainError(401, "Sign-in required");
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

export function revokeSessions(userId: string) {
  database().prepare("DELETE FROM auth_sessions WHERE user_id = ?").run(userId);
}
export function endSession(access: string | null, refresh: string | null) {
  database()
    .prepare("DELETE FROM auth_sessions WHERE access_hash = ? OR refresh_hash = ?")
    .run(digest(access ?? ""), digest(refresh ?? ""));
  globalThis.leafwakeRealtimeChanged?.();
}
export function findAccount(id: string) {
  const row = database().prepare("SELECT * FROM users WHERE id = ?").get(id);
  if (!row) throw new DomainError(404, "Not found");
  return userRow.parse(row);
}
export function requireAdministrator(actor: Account) {
  // Re-read authority at the write boundary, including after asynchronous password derivation.
  const current = findAccount(actor.id);
  if (!current.active || !["root", "admin"].includes(current.type))
    throw new DomainError(403, "Administrator required");
  return current;
}
export function listAccounts(actor: Account) {
  requireAdministrator(actor);
  return database()
    .prepare("SELECT * FROM users ORDER BY username_key")
    .all()
    .map((row) => visibleUser(userRow.parse(row)));
}
const permissionPatch = z
  .object({
    download: z.boolean().optional(),
    update: z.boolean().optional(),
    delete: z.boolean().optional(),
    upload: z.boolean().optional(),
    accessExplicitContent: z.boolean().optional(),
    accessAllLibraries: z.boolean().optional(),
    accessAllTags: z.boolean().optional(),
    selectedTagsNotAccessible: z.boolean().optional(),
  })
  .strict();
const editable = z
  .object({
    username: setupSchema.shape.username.optional(),
    password: setupSchema.shape.password.optional(),
    type: z.enum(["admin", "user", "guest"]).optional(),
    isActive: z.boolean().optional(),
    permissions: permissionPatch.optional(),
    librariesAccessible: z.array(z.string().max(256)).max(1000).optional(),
    itemTagsSelected: z.array(z.string().max(256)).max(1000).optional(),
  })
  .strict();
export const createAccountSchema = editable.extend({
  username: setupSchema.shape.username,
  password: setupSchema.shape.password,
});
export const editAccountSchema = editable;
function ensureEditable(actor: Account, target: Account) {
  const current = requireAdministrator(actor);
  if (target.type === "root" || (current.type !== "root" && target.type === "admin"))
    throw new DomainError(403, "This account cannot be changed by this administrator");
  return current;
}
function assertUnique(username: string, id = "") {
  if (
    database()
      .prepare("SELECT id FROM users WHERE username_key = ? AND id != ?")
      .get(username.toLowerCase(), id)
  )
    throw new DomainError(400, "Username already taken");
}
export async function createAccount(actor: Account, input: z.infer<typeof createAccountSchema>) {
  requireAdministrator(actor);
  const encoded = await hashPassword(input.password);
  return transaction((db) => {
    const current = requireAdministrator(actor);
    const type = input.type ?? "user";
    if (type === "admin" && current.type !== "root") throw new DomainError(403, "Owner required");
    assertUnique(input.username);
    const id = randomUUID();
    const defaults = {
      download: true,
      update: false,
      delete: false,
      upload: false,
      accessExplicitContent: false,
      accessAllLibraries: true,
      accessAllTags: true,
      selectedTagsNotAccessible: false,
    };
    db.prepare(`INSERT INTO users(id, username, username_key, password_hash, type, active, permissions, libraries, tags, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
      id,
      input.username,
      input.username.toLowerCase(),
      encoded,
      type,
      input.isActive === false ? 0 : 1,
      JSON.stringify({ ...defaults, ...input.permissions }),
      JSON.stringify(input.librariesAccessible ?? []),
      JSON.stringify(input.itemTagsSelected ?? []),
      Date.now(),
    );
    return visibleUser(findAccount(id));
  });
}
export async function editAccount(actor: Account, id: string, input: z.infer<typeof editAccountSchema>) {
  ensureEditable(actor, findAccount(id));
  const encoded = input.password ? await hashPassword(input.password) : null;
  return transaction((db) => {
    const target = findAccount(id);
    const current = ensureEditable(actor, target);
    if (input.type === "admin" && current.type !== "root") throw new DomainError(403, "Owner required");
    const username = input.username ?? target.username;
    assertUnique(username, id);
    db.prepare(`UPDATE users SET username = ?, username_key = ?, password_hash = ?, type = ?, active = ?,
      permissions = ?, libraries = ?, tags = ? WHERE id = ?`).run(
      username,
      username.toLowerCase(),
      encoded ?? target.password_hash,
      input.type ?? target.type,
      input.isActive === undefined ? target.active : Number(input.isActive),
      JSON.stringify({ ...permissions.parse(JSON.parse(target.permissions)), ...input.permissions }),
      input.librariesAccessible ? JSON.stringify(input.librariesAccessible) : target.libraries,
      input.itemTagsSelected ? JSON.stringify(input.itemTagsSelected) : target.tags,
      id,
    );
    revokeSessions(id);
    return visibleUser(findAccount(id));
  });
}
export function removeAccount(actor: Account, id: string) {
  transaction((db) => {
    ensureEditable(actor, findAccount(id));
    db.prepare("DELETE FROM users WHERE id = ?").run(id);
  });
}
export function revokeAccount(actor: Account, id: string) {
  const target = findAccount(id);
  if (id !== actor.id) ensureEditable(actor, target);
  revokeSessions(id);
}
export function canReadLibrary(actor: Account, libraryId: string) {
  if (
    database()
      .prepare("SELECT id FROM libraries WHERE id=? AND json_extract(content,'$.isArchived')=1")
      .get(libraryId)
  )
    return false;
  const policy = permissions.parse(JSON.parse(actor.permissions));
  return (
    policy.accessAllLibraries || z.array(z.string()).parse(JSON.parse(actor.libraries)).includes(libraryId)
  );
}
export function canReadMedia(actor: Account, item: { libraryId: string; explicit: boolean; tags: string[] }) {
  if (!canReadLibrary(actor, item.libraryId)) return false;
  const policy = permissions.parse(JSON.parse(actor.permissions));
  if (item.explicit && !policy.accessExplicitContent) return false;
  if (policy.accessAllTags) return true;
  const selected = z.array(z.string()).parse(JSON.parse(actor.tags));
  const intersects = item.tags.some((tag) => selected.includes(tag));
  return policy.selectedTagsNotAccessible ? !intersects : intersects;
}

export function openIdSession(issuer: string, subject: string, registration: boolean, preferred: string) {
  return transaction((db) => {
    let identity = db
      .prepare("SELECT user_id FROM openid_identities WHERE issuer=? AND subject=?")
      .get(issuer, subject);
    if (!identity) {
      if (!registration) throw new DomainError(403, "OpenID account registration is disabled");
      const id = randomUUID();
      const prefix = preferred.replace(/[^\p{L}\p{N}._-]/gu, "").slice(0, 40) || "openid";
      const username = `${prefix}-${randomBytes(6).toString("hex")}`;
      const policy = {
        download: true,
        update: false,
        delete: false,
        upload: false,
        accessExplicitContent: false,
        accessAllLibraries: true,
        accessAllTags: true,
        selectedTagsNotAccessible: false,
      };
      db.prepare(
        "INSERT INTO users(id,username,username_key,password_hash,type,permissions,created_at) VALUES(?,?,?,'!openid','user',?,?)",
      ).run(id, username, username.toLowerCase(), JSON.stringify(policy), Date.now());
      db.prepare("INSERT INTO openid_identities VALUES(?,?,?)").run(issuer, subject, id);
      identity = { user_id: id };
    }
    const user = findAccount(z.string().parse(identity.user_id));
    if (!user.active) throw new DomainError(403, "This account is disabled");
    return issueSession(user);
  });
}
