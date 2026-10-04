import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { hashSync } from "bcryptjs";

const base = process.env.LEAFWAKE_EREADER_POLICY_URL || "http://127.0.0.1:19936";
const root = "/Users/emanuel/.cache/leafwake/ereader-policy";
async function call(path, data, token, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, data, token, method) {
  const response = await call(path, data, token, method);
  assert.ok(response.ok, `${path}: ${response.status} ${await response.clone().text()}`);
  return response.json();
}
test("imported e-reader creation policy survives login and confines personal devices to their owner", async () => {
  await mkdir(root, { recursive: true });
  const name = `${randomUUID()}.sqlite`,
    filename = `${root}/${name}`;
  const source = new DatabaseSync(filename);
  source.exec(
    "CREATE TABLE users(id TEXT PRIMARY KEY,username TEXT,pash TEXT,type TEXT,isActive INTEGER,isLocked INTEGER,permissions TEXT,bookmarks TEXT,extraData TEXT,createdAt TEXT)",
  );
  for (const [username, type, allowed] of [
    ["policy-owner", "root", true],
    ["policy-allowed", "user", true],
    ["policy-denied", "user", false],
  ]) {
    source.prepare("INSERT INTO users VALUES(?,?,?,?,1,0,?,'[]','{}',?)").run(
      randomUUID(),
      username,
      hashSync("synthetic-password-2026", 8),
      type,
      JSON.stringify({
        download: true,
        update: false,
        delete: false,
        upload: false,
        createEreader: allowed,
        accessExplicitContent: false,
        accessAllLibraries: true,
        accessAllTags: true,
        selectedTagsNotAccessible: false,
        librariesAccessible: [],
        itemTagsSelected: [],
      }),
      "2026-01-01T00:00:00.000Z",
    );
  }
  source.close();
  const setup = { sourcePath: `/imports/${name}`, setupKey: "synthetic-ereader-policy-2026" };
  const report = await json("/api/setup/import/inspect", setup);
  assert.equal(report.canImport, true, "original createEreader policy must be supported");
  const digest = createHash("sha256")
    .update(await readFile(filename))
    .digest("hex");
  await json("/api/setup/import", { ...setup, expectedDigest: digest });
  const login = async (username) =>
    (await json("/login", { username, password: "synthetic-password-2026" })).user;
  const owner = await login("policy-owner"),
    allowed = await login("policy-allowed"),
    denied = await login("policy-denied");
  assert.equal(allowed.permissions.createEreader, true);
  assert.equal(denied.permissions.createEreader, false);
  const shared = {
    name: "Shared",
    email: "shared@example.invalid",
    availabilityOption: "userOrUp",
    users: [],
  };
  await json("/api/emails/ereader-devices", { ereaderDevices: [shared] }, owner.accessToken);
  const personal = {
    name: "Personal",
    email: "personal@example.invalid",
    availabilityOption: "specificUsers",
    users: [allowed.id],
  };
  assert.equal(
    (await call("/api/me/ereader-devices", { ereaderDevices: [] }, denied.accessToken)).status,
    403,
  );
  assert.equal(
    (await call("/api/me/ereader-devices", { ereaderDevices: [shared] }, allowed.accessToken)).status,
    400,
  );
  assert.equal(
    (
      await call(
        "/api/me/ereader-devices",
        { ereaderDevices: [{ ...personal, users: [denied.id] }] },
        allowed.accessToken,
      )
    ).status,
    400,
  );
  await json("/api/me/ereader-devices", { ereaderDevices: [personal] }, allowed.accessToken);
  assert.deepEqual(
    (await json("/api/authorize", {}, allowed.accessToken)).ereaderDevices.map((d) => d.name).sort(),
    ["Personal", "Shared"],
  );
  assert.deepEqual(
    (await json("/api/authorize", {}, denied.accessToken)).ereaderDevices.map((d) => d.name),
    ["Shared"],
  );
  await json("/api/me/ereader-devices", { ereaderDevices: [] }, allowed.accessToken);
  assert.deepEqual((await json("/api/emails/ereader-devices", undefined, owner.accessToken)).ereaderDevices, [
    shared,
  ]);
  await json(
    `/api/users/${allowed.id}`,
    { permissions: { createEreader: false } },
    owner.accessToken,
    "PATCH",
  );
  assert.equal(
    (await call("/api/me/ereader-devices", { ereaderDevices: [personal] }, allowed.accessToken)).status,
    401,
  );
  const revoked = await login("policy-allowed");
  assert.equal(
    (await call("/api/me/ereader-devices", { ereaderDevices: [personal] }, revoked.accessToken)).status,
    403,
  );
  assert.equal(
    createHash("sha256")
      .update(await readFile(filename))
      .digest("hex"),
    digest,
  );
});
