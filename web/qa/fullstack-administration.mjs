import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

const base = process.env.LEAFWAKE_ADMIN_TEST_URL || "http://127.0.0.1:19902";
async function call(path, token, data, method = data === undefined ? "GET" : "POST", extra = {}) {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      "content-type": "application/json",
      ...extra,
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, token, data, method, extra) {
  const r = await call(path, token, data, method, extra);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("owner server settings and safe library edits apply to authentication and catalog", async () => {
  const login = await json("/login", "", { username: "import-owner", password: "synthetic-password-2026" }),
    token = login.user.accessToken;
  const initial = await json("/api/settings", token);
  const settings = {
    ...initial,
    serverName: "Synthetic Leafwake",
    language: "de",
    loginMessage: "Private synthetic fixture",
    allowedOrigins: ["https://allowed.example"],
    rateLimitLoginRequests: 2,
    rateLimitLoginWindow: 60000,
    maxScanEntries: 1000,
    maxScanDepth: 16,
    maxMediaProbes: 2,
  };
  await json("/api/settings", token, settings, "PATCH");
  assert.deepEqual(await json("/api/settings", token), settings);
  assert.equal((await json("/status", "")).language, "de");
  assert.equal(
    (await json("/login", "", { username: "import-owner", password: "synthetic-password-2026" }))
      .serverSettings.language,
    "de",
  );
  assert.equal(
    (await call("/api/settings", token, { ...settings, allowedOrigins: ["*"] }, "PATCH")).status,
    400,
  );
  const library = await json("/api/libraries", token, {
    name: "Admin " + randomUUID(),
    mediaType: "book",
    folders: [{ fullPath: "/data/media" }],
  });
  const renamed = await json(
    `/api/libraries/${library.id}`,
    token,
    {
      name: "Renamed synthetic",
      displayOrder: 7,
      settings: { coverAspectRatio: 1.5 },
      folders: library.folders,
    },
    "PATCH",
  );
  assert.equal(renamed.name, "Renamed synthetic");
  assert.equal(renamed.folders[0].id, library.folders[0].id);
  assert.equal(
    (
      await call(
        `/api/libraries/${library.id}`,
        token,
        { folders: [{ id: library.folders[0].id, fullPath: "/etc" }] },
        "PATCH",
      )
    ).status,
    400,
  );
  assert.equal(
    (await call("/api/settings", token, settings, "PATCH", { origin: "https://denied.example" })).status,
    403,
  );
  await json("/api/settings", token, settings, "PATCH", { origin: "https://allowed.example" });
  const unknown = "unknown-" + randomUUID();
  for (let i = 0; i < 2; i++)
    assert.equal((await call("/login", "", { username: unknown, password: "wrong-password" })).status, 401);
  assert.equal((await call("/login", "", { username: unknown, password: "wrong-password" })).status, 429);
  const archived = await json(`/api/libraries/${library.id}`, token, { isArchived: true }, "PATCH");
  assert.equal(archived.isArchived, true);
  assert.equal((await call(`/api/libraries/${library.id}`, token)).status, 404);
  assert.ok(
    (await json("/api/admin/libraries", token)).libraries.some((l) => l.id === library.id && l.isArchived),
  );
  await json(`/api/libraries/${library.id}`, token, { isArchived: false }, "PATCH");
  await json(`/api/libraries/${library.id}`, token, undefined, "DELETE");
  assert.equal((await call(`/api/libraries/${library.id}`, token)).status, 404);
  const guest = await json("/api/users", token, {
    username: "admin-denied-" + randomUUID(),
    password: "synthetic-user-password",
    type: "user",
  });
  const guestLogin = await json("/login", "", {
    username: guest.username,
    password: "synthetic-user-password",
  });
  assert.equal((await call("/api/settings", guestLogin.user.accessToken)).status, 403);
  await json("/api/settings", token, initial, "PATCH");
  console.log("Owner settings/auth policy and confined library editing/deletion passed");
});
