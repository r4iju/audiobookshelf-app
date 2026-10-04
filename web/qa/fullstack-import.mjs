import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { chmod, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { hashSync } from "bcryptjs";

const base = process.env.LEAFWAKE_IMPORT_TEST_URL || "http://127.0.0.1:19893";
const root = "/Users/emanuel/.cache/leafwake/fullstack-import-153";
const setupKey = "synthetic-import-operator-2026";
async function call(path, data, token, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(data === undefined ? {} : { "content-type": "application/json" }),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function login(username, password) {
  const response = await call("/login", { username, password });
  assert.equal(response.status, 200);
  return (await response.json()).user;
}
async function digest(path) {
  return createHash("sha256")
    .update(await readFile(path))
    .digest("hex");
}
test("read-only account import inventories failures, preserves credentials and policies, retries atomically and restores a backup", async () => {
  await mkdir(root, { recursive: true });
  const name = `source-${randomUUID()}.sqlite`;
  const filename = `${root}/${name}`;
  const sourcePath = `/imports/${name}`;
  const source = new DatabaseSync(filename);
  source.exec(
    `CREATE TABLE users(id TEXT PRIMARY KEY,username TEXT,email TEXT,pash TEXT,type TEXT,token TEXT,isActive INTEGER,isLocked INTEGER,lastSeen TEXT,permissions TEXT,bookmarks TEXT,extraData TEXT,createdAt TEXT,updatedAt TEXT); CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE auditNotes(id TEXT,value TEXT); INSERT INTO auditNotes VALUES('synthetic','must be reported');`,
  );
  source.prepare("INSERT INTO settings VALUES(?,?)").run(
    "server-settings",
    JSON.stringify({
      id: "server-settings",
      authOpenIDIssuerURL: null,
      authOpenIDClientID: null,
      authOpenIDClientSecret: null,
      authOpenIDTokenSigningAlgorithm: "RS256",
      authOpenIDButtonText: "Login with OpenId",
      authOpenIDMobileRedirectURIs: ["audiobookshelf://oauth"],
    }),
  );
  const ownerId = randomUUID(),
    qaId = randomUUID(),
    limitedId = randomUUID();
  const privileges = {
    download: true,
    update: true,
    delete: true,
    upload: true,
    accessExplicitContent: true,
    accessAllLibraries: true,
    accessAllTags: true,
    selectedTagsNotAccessible: false,
    librariesAccessible: [],
    itemTagsSelected: [],
  };
  const insert = source.prepare("INSERT INTO users VALUES(?,?,?,?,?,?,1,0,NULL,?,'[]','{}',?,?)");
  for (const [id, username, password, type, policy] of [
    [ownerId, "legacy-owner", "synthetic-password-2026", "root", privileges],
    [qaId, "qa", "qa-pass", "user", privileges],
    [
      limitedId,
      "legacy-limited",
      "synthetic-password-2026",
      "user",
      {
        ...privileges,
        accessExplicitContent: false,
        accessAllLibraries: false,
        librariesAccessible: ["preserved-library"],
        accessAllTags: false,
        itemTagsSelected: ["safe"],
      },
    ],
  ])
    insert.run(
      id,
      username,
      "",
      hashSync(password, 8),
      type,
      "",
      JSON.stringify(policy),
      "2025-01-01T00:00:00.000Z",
      "2025-01-01T00:00:00.000Z",
    );
  source.close();
  await chmod(filename, 0o444);
  const original = await digest(filename);
  assert.equal(
    (await call("/api/setup/import/inspect", { setupKey: "wrong-operator-key", sourcePath })).status,
    403,
  );
  const inspected = await call("/api/setup/import/inspect", { setupKey, sourcePath });
  assert.equal(inspected.status, 200, "fresh installation offers read-only inventory");
  const report = await inspected.json();
  assert.equal(report.digest, original);
  assert.equal(report.canImport, true);
  assert.equal(report.canCutover, false);
  assert.ok(report.remainingData.some((value) => value.table === "auditNotes" && value.rows === 1));
  assert.equal(JSON.stringify(report).includes("$2"), false, "password hashes never enter the report");
  assert.equal(
    (await call("/api/setup/import", { setupKey, sourcePath, expectedDigest: "0".repeat(64) })).status,
    409,
  );
  assert.equal((await (await call("/status")).json()).isInit, false);
  const badName = `bad-${randomUUID()}.sqlite`;
  await copyFile(filename, `${root}/${badName}`);
  await chmod(`${root}/${badName}`, 0o644);
  const bad = new DatabaseSync(`${root}/${badName}`);
  bad.prepare("UPDATE users SET pash='unsupported:synthetic' WHERE id=?").run(qaId);
  bad.close();
  await chmod(`${root}/${badName}`, 0o444);
  const badRequest = { setupKey, sourcePath: `/imports/${badName}` };
  const unsupported = await (await call("/api/setup/import/inspect", badRequest)).json();
  assert.equal(unsupported.canImport, false);
  assert.ok(unsupported.errors.some((value) => value.accountId === qaId));
  assert.equal(
    (await call("/api/setup/import", { ...badRequest, expectedDigest: await digest(`${root}/${badName}`) }))
      .status,
    409,
  );
  assert.equal((await (await call("/status")).json()).isInit, false);
  assert.equal(
    (await call("/api/setup/import/inspect", { setupKey, sourcePath: "/etc/passwd" })).status,
    400,
  );
  for (const defect of process.env.LEAFWAKE_IMPORT_TEST_DEFECT === "skip"
    ? []
    : process.env.LEAFWAKE_IMPORT_TEST_DEFECT
      ? [process.env.LEAFWAKE_IMPORT_TEST_DEFECT]
      : ["email", "unknown"]) {
    const defectiveName = `${defect}-${randomUUID()}.sqlite`;
    await copyFile(filename, `${root}/${defectiveName}`);
    await chmod(`${root}/${defectiveName}`, 0o644);
    const defective = new DatabaseSync(`${root}/${defectiveName}`);
    if (defect === "email") defective.prepare("UPDATE users SET email=x'010203' WHERE id=?").run(ownerId);
    else {
      defective.exec("ALTER TABLE users ADD COLUMN futurePolicy TEXT");
      defective.prepare("UPDATE users SET futurePolicy='must be reported' WHERE id=?").run(qaId);
    }
    defective.close();
    await chmod(`${root}/${defectiveName}`, 0o444);
    const result = await (
      await call("/api/setup/import/inspect", { setupKey, sourcePath: `/imports/${defectiveName}` })
    ).json();
    assert.equal(result.canImport, false, `unsupported ${defect} must block before account insertion`);
  }
  const imported = await call("/api/setup/import", { setupKey, sourcePath, expectedDigest: original });
  assert.equal(imported.status, 200, await imported.clone().text());
  assert.equal((await imported.json()).accountCount, 3);
  assert.equal(
    (await call("/api/setup/import", { setupKey, sourcePath, expectedDigest: original })).status,
    200,
  );
  const qa = await login("qa", "qa-pass");
  assert.equal(qa.id, qaId);
  const limited = await login("legacy-limited", "synthetic-password-2026");
  assert.deepEqual(limited.librariesAccessible, ["preserved-library"]);
  assert.deepEqual(limited.itemTagsSelected, ["safe"]);
  assert.equal(limited.permissions.accessExplicitContent, false);
  let owner = await login("legacy-owner", "synthetic-password-2026");
  assert.equal(owner.id, ownerId);
  assert.equal((await call("/api/admin/backups", {}, qa.accessToken)).status, 403);
  const backup = await (await call("/api/admin/backups", {}, owner.accessToken)).json();
  assert.ok(backup.id);
  assert.equal(
    (await call(`/api/users/${qaId}`, { isActive: false }, owner.accessToken, "PATCH")).status,
    200,
  );
  assert.equal((await call("/login", { username: "qa", password: "qa-pass" })).status, 401);
  assert.equal((await call(`/api/admin/backups/${backup.id}/restore`, {}, owner.accessToken)).status, 200);
  assert.equal(
    (await call("/api/me", undefined, qa.accessToken)).status,
    401,
    "restore revokes snapshot session authority",
  );
  assert.equal((await login("qa", "qa-pass")).id, qaId);
  owner = await login("legacy-owner", "synthetic-password-2026");
  const migrations = await (await call("/api/admin/migrations", undefined, owner.accessToken)).json();
  assert.ok(migrations.migrations.some((value) => value.digest === original && value.scope === "accounts"));
  assert.equal(await digest(filename), original, "source copy is never changed");
  await writeFile("/tmp/leafwake-import-state.json", JSON.stringify({ ownerId, qaId, digest: original }));
});
