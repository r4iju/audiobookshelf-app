import "server-only";
import { createHash, randomUUID } from "node:crypto";
import { closeSync, constants, existsSync, fstatSync, openSync, readSync, realpathSync } from "node:fs";
import { resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { z } from "zod";
import { bookmarkSchema } from "@/lib/abs/schemas";
import { DomainError, permissions, requireSetupKey } from "./accounts";
import { within } from "./catalog";
import { database, initialized, transaction } from "./data";

export const inspectImportSchema = z
  .object({ setupKey: z.string().min(1).max(256), sourcePath: z.string().min(1).max(4096) })
  .strict();
export const commitImportSchema = inspectImportSchema.extend({
  expectedDigest: z.string().regex(/^[a-f0-9]{64}$/),
});
const legacyPolicy = permissions
  .extend({
    librariesAccessible: z.array(z.string().max(256)).max(10000).default([]),
    itemTagsSelected: z.array(z.string().max(256)).max(10000).default([]),
  })
  .strict();
const sourceUser = z.object({
  id: z.string().min(1).max(256),
  username: z.string().min(1).max(256),
  email: z.string().max(512).nullable().optional(),
  lastSeen: z.string().nullable().optional(),
  updatedAt: z.string().nullable().optional(),
  pash: z
    .string()
    .regex(/^\$2[aby]\$(0[4-9]|1[0-2])\$[./A-Za-z0-9]{53}$/)
    .nullable(),
  type: z.enum(["root", "admin", "user", "guest"]),
  isActive: z.number().int().min(0).max(1),
  isLocked: z.number().int().min(0).max(1),
  permissions: z.string(),
  bookmarks: z.string(),
  extraData: z.string(),
  createdAt: z.string(),
});
const reportSchema = z.object({
  digest: z.string(),
  scope: z.literal("accounts"),
  sourceSchema: z.string(),
  canImport: z.boolean(),
  canCutover: z.boolean(),
  accounts: z.array(
    z.object({ id: z.string(), username: z.string(), type: z.string(), active: z.boolean() }),
  ),
  errors: z.array(z.object({ accountId: z.string().optional(), message: z.string() })),
  remainingData: z.array(z.object({ table: z.string(), rows: z.number() })),
  notices: z.array(z.string()),
});
export type ImportReport = z.infer<typeof reportSchema>;
const completionSchema = z.object({
  id: z.string(),
  digest: z.string(),
  scope: z.literal("accounts"),
  accountCount: z.number(),
  completedAt: z.number(),
  report: reportSchema,
});
export function sourceCopy(path: string) {
  if (process.platform !== "linux")
    throw new DomainError(400, "Run migration and snapshot restore inside the Audiobook Loft product image");
  const roots = (process.env.LEAFWAKE_IMPORT_ROOTS || "/imports")
    .split(":")
    .filter(Boolean)
    .map((root) => resolve(root));
  const absolute = resolve(path);
  if (!roots.some((root) => within(root, absolute)))
    throw new DomainError(400, "Use a source copy inside a configured import folder");
  let fd: number | undefined;
  try {
    const actual = realpathSync(absolute);
    if (actual !== absolute || !roots.some((root) => within(realpathSync(root), actual)))
      throw new DomainError(400, "Source links are not accepted");
    if (existsSync(`${actual}-wal`) || existsSync(`${actual}-journal`))
      throw new DomainError(400, "Use a closed, consistent SQLite copy without journal sidecars");
    fd = openSync(actual, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    if (realpathSync(`/proc/self/fd/${fd}`) !== actual)
      throw new DomainError(400, "Source descriptor escaped its configured mount");
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size > 256 * 1024 * 1024)
      throw new DomainError(400, "Source must be a regular SQLite copy under 256 MiB");
    const sourceFd = fd;
    const hashCopy = () => {
      const digest = createHash("sha256"),
        buffer = Buffer.alloc(65536);
      let offset = 0;
      for (;;) {
        const length = readSync(sourceFd, buffer, 0, buffer.length, offset);
        if (!length) break;
        digest.update(buffer.subarray(0, length));
        offset += length;
      }
      return digest.digest("hex");
    };
    const fingerprint = hashCopy();
    const pinned = process.platform === "linux" ? `/proc/self/fd/${fd}` : actual;
    const db = new DatabaseSync(pinned, { readOnly: true });
    db.exec("PRAGMA query_only=ON; PRAGMA trusted_schema=OFF; BEGIN;");
    return {
      db,
      digest: fingerprint,
      verify() {
        const current = fstatSync(sourceFd);
        if (
          current.size !== stat.size ||
          current.mtimeMs !== stat.mtimeMs ||
          current.ctimeMs !== stat.ctimeMs ||
          hashCopy() !== fingerprint
        )
          throw new DomainError(409, "Source copy changed during inventory");
      },
      close() {
        db.close();
        if (fd !== undefined) closeSync(fd);
      },
    };
  } catch (error) {
    if (fd !== undefined) closeSync(fd);
    if (error instanceof DomainError) throw error;
    throw new DomainError(400, "Source copy could not be opened as SQLite");
  }
}
function readInventory(source: ReturnType<typeof sourceCopy>) {
  const tables = source.db
    .prepare("SELECT name,type FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")
    .all();
  if (!tables.some((table) => table.name === "users" && table.type === "table"))
    throw new DomainError(400, "Unsupported source account schema");
  const columns = source.db
    .prepare("PRAGMA table_info(users)")
    .all()
    .map((column) => String(column.name));
  for (const required of [
    "id",
    "username",
    "pash",
    "type",
    "isActive",
    "isLocked",
    "permissions",
    "bookmarks",
    "extraData",
    "createdAt",
  ])
    if (!columns.includes(required)) throw new DomainError(400, "Unsupported source account schema");
  const count = Number(source.db.prepare("SELECT COUNT(*) AS count FROM users").get()?.count);
  if (count < 1 || count > 10000) throw new DomainError(400, "Source must contain 1–10000 accounts");
  const errors: ImportReport["errors"] = [];
  const knownColumns = new Set([
    "id",
    "username",
    "email",
    "pash",
    "type",
    "token",
    "isActive",
    "isLocked",
    "lastSeen",
    "permissions",
    "bookmarks",
    "extraData",
    "createdAt",
    "updatedAt",
  ]);
  for (const column of columns)
    if (!knownColumns.has(column)) errors.push({ message: `Unsupported account column: ${column}` });
  const users: {
    id: string;
    username: string;
    password: string;
    type: string;
    active: number;
    policy: string;
    libraries: string;
    tags: string;
    created: number;
    archive: string;
  }[] = [];
  const usernames = new Set<string>();
  for (const raw of source.db.prepare("SELECT * FROM users").all()) {
    const parsed = sourceUser.safeParse(raw);
    if (!parsed.success) {
      errors.push({
        accountId: typeof raw.id === "string" ? raw.id : undefined,
        message: "Unsupported account fields or password hash",
      });
      continue;
    }
    const user = parsed.data;
    try {
      const policy = legacyPolicy.parse(JSON.parse(user.permissions));
      const extra = z.record(z.string(), z.unknown()).parse(JSON.parse(user.extraData));
      const subject =
        extra.authOpenIDSub === undefined || extra.authOpenIDSub === null
          ? null
          : z.string().min(1).max(1024).parse(extra.authOpenIDSub);
      if (user.pash === null && (!subject || user.type === "root"))
        throw new Error(
          "A passwordless source account requires a linked OpenID subject and a local recovery owner",
        );
      const created = Date.parse(user.createdAt);
      if (!Number.isFinite(created)) throw new Error("Invalid creation date");
      if (usernames.has(user.username.toLowerCase())) throw new Error("Conflicting account names");
      usernames.add(user.username.toLowerCase());
      const { librariesAccessible, itemTagsSelected, ...flags } = policy;
      const bookmarks = z.array(bookmarkSchema).max(100000).parse(JSON.parse(user.bookmarks));
      users.push({
        id: user.id,
        username: user.username,
        password: user.pash ?? "!openid",
        type: user.type,
        active: user.isActive,
        policy: JSON.stringify(flags),
        libraries: JSON.stringify(librariesAccessible),
        tags: JSON.stringify(itemTagsSelected),
        created,
        archive: JSON.stringify({
          email: user.email ?? null,
          isLocked: Boolean(user.isLocked),
          extraData: extra,
          bookmarks,
          lastSeen: user.lastSeen ?? null,
          updatedAt: user.updatedAt ?? null,
        }),
      });
    } catch (error) {
      errors.push({
        accountId: user.id,
        message:
          error instanceof z.ZodError
            ? "Unsupported account policy"
            : error instanceof SyntaxError
              ? "Invalid account JSON"
              : error instanceof Error
                ? error.message
                : "Unsupported account policy",
      });
    }
  }
  if (users.filter((user) => user.type === "root" && user.active === 1).length !== 1)
    errors.push({ message: "Exactly one active source owner is required" });
  const remainingData: ImportReport["remainingData"] = [];
  for (const table of tables) {
    if (table.type !== "table" || table.name === "users") continue;
    const name = z
      .string()
      .regex(/^[A-Za-z][A-Za-z0-9_]*$/)
      .parse(table.name);
    const rows = Number(source.db.prepare(`SELECT COUNT(*) AS count FROM "${name}"`).get()?.count);
    if (rows) remainingData.push({ table: name, rows });
  }
  const report = reportSchema.parse({
    digest: source.digest,
    scope: "accounts",
    sourceSchema: "Audiobookshelf SQLite account columns",
    canImport: errors.length === 0,
    canCutover: false,
    accounts: users.map((user) => ({
      id: user.id,
      username: user.username,
      type: user.type,
      active: Boolean(user.active),
    })),
    errors: [...new Map(errors.map((error) => [JSON.stringify(error), error])).values()],
    remainingData,
    notices: [
      "Account import only. Media, progress, lists and server configuration require the remaining migration stages.",
      "Previous tokens and sessions are not imported. Sign in with the original password.",
      "Email, lock state, creation/update dates, last-seen metadata and extra account data are retained in the account archive.",
    ],
  });
  source.verify();
  return { users, report };
}
export function inspectImport(input: z.infer<typeof inspectImportSchema>) {
  requireSetupKey(input.setupKey);
  if (initialized())
    throw new DomainError(409, "Use migration administration on an initialized installation");
  const source = sourceCopy(input.sourcePath);
  try {
    return readInventory(source).report;
  } finally {
    source.close();
  }
}
export function commitImport(input: z.infer<typeof commitImportSchema>) {
  requireSetupKey(input.setupKey);
  const prior = database()
    .prepare("SELECT content FROM migrations WHERE digest=? AND scope='accounts'")
    .get(input.expectedDigest);
  if (prior) return completionSchema.parse(JSON.parse(z.string().parse(prior.content)));
  if (initialized()) throw new DomainError(409, "Import accounts into a fresh installation");
  const source = sourceCopy(input.sourcePath);
  try {
    if (source.digest !== input.expectedDigest)
      throw new DomainError(409, "Source copy changed. Inspect it again");
    const { users, report } = readInventory(source);
    if (!report.canImport) throw new DomainError(409, "Resolve the inventory errors before import");
    return transaction((db) => {
      if (db.prepare("SELECT id FROM users LIMIT 1").get())
        throw new DomainError(409, "Installation was initialized meanwhile");
      const insert = db.prepare(
        "INSERT INTO users(id,username,username_key,password_hash,type,active,permissions,libraries,tags,created_at,archive) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
      );
      for (const user of users)
        insert.run(
          user.id,
          user.username,
          user.username.toLowerCase(),
          user.password,
          user.type,
          user.active,
          user.policy,
          user.libraries,
          user.tags,
          user.created,
          user.archive,
        );
      const result = {
        id: randomUUID(),
        digest: source.digest,
        scope: "accounts",
        accountCount: users.length,
        completedAt: Date.now(),
        report,
      };
      db.prepare("INSERT INTO migrations VALUES(?,?,?,?)").run(
        result.id,
        result.digest,
        result.scope,
        JSON.stringify(result),
      );
      return completionSchema.parse(result);
    });
  } finally {
    source.close();
  }
}
export function migrationHistory() {
  return {
    migrations: database()
      .prepare("SELECT content FROM migrations ORDER BY rowid")
      .all()
      .map((row) =>
        z
          .looseObject({
            id: z.string(),
            digest: z.string(),
            scope: z.string(),
            accountCount: z.number(),
            completedAt: z.number(),
            report: z.unknown(),
          })
          .parse(JSON.parse(z.string().parse(row.content))),
      ),
  };
}
