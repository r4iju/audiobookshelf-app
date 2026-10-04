import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import test from "node:test";

const origin = process.env.LEAFWAKE_INSTALL_TEST_URL || "http://127.0.0.1:19885";
const state = process.env.LEAFWAKE_INSTALL_TEST_STATE || "/tmp/leafwake-installation-state.json";
const credentials = { username: "installation-owner", password: "synthetic-password-2026" };
async function call(path, data, headers = {}) {
  return fetch(origin + path, {
    method: data === undefined ? "GET" : "POST",
    headers: { ...(data === undefined ? {} : { "content-type": "application/json" }), ...headers },
    body: data === undefined ? undefined : JSON.stringify(data),
    signal: AbortSignal.timeout(15000),
  });
}
async function login() {
  const response = await call("/login", credentials, { "x-return-tokens": "true" });
  assert.equal(response.status, 200, "password sign-in succeeds");
  const body = await response.json();
  assert.equal(body.user.username, credentials.username);
  assert.equal(body.user.type, "root");
  assert.equal(typeof body.user.id, "string");
  assert.equal(body.user.permissions.download, true);
  assert.equal(typeof body.user.accessToken, "string");
  assert.ok(body.user.accessToken.length > 30);
  assert.equal(typeof body.user.refreshToken, "string");
  assert.ok(body.user.refreshToken.length > 30);
  assert.equal(body.user.passwordHash, undefined, "credential material is never returned");
  return body.user;
}
if (process.env.LEAFWAKE_INSTALL_TEST_PHASE === "restart") {
  test("a restarted installation retains its owner, tokens and closed bootstrap", async () => {
    const saved = JSON.parse(await readFile(state, "utf8"));
    assert.equal((await (await call("/status")).json()).isInit, true);
    assert.equal((await login()).id, saved.id, "owner identity survives restart");
    const browserLogin = await call("/login", credentials, { origin });
    assert.equal(
      browserLogin.status,
      200,
      "the legitimate browser origin can sign in through the published port",
    );
    const me = await call("/api/me", undefined, { authorization: `Bearer ${saved.accessToken}` });
    assert.equal(me.status, 200, "persisted access session survives restart");
    assert.equal((await me.json()).id, saved.id);
    assert.equal(
      (await call("/api/setup", { ...credentials, setupKey: process.env.LEAFWAKE_SETUP_KEY })).status,
      409,
    );
    const refresh = await call("/auth/refresh", {}, { "x-refresh-token": saved.refreshToken });
    assert.equal(refresh.status, 200);
    const rotated = (await refresh.json()).user;
    assert.ok(rotated.refreshToken !== saved.refreshToken, "refresh credentials rotate");
    assert.equal((await call("/auth/refresh", {}, { "x-refresh-token": saved.refreshToken })).status, 401);
  });
} else {
  test("one running product initializes exactly one owner and serves UI and authenticated API", async () => {
    const status = await call("/status");
    assert.equal(status.status, 200, "the image serves the replacement backend, not only a browser client");
    const before = await status.json();
    assert.equal(before.isInit, false);
    assert.equal(before.app, "Leafwake");
    const page = await call("/setup");
    assert.equal(page.status, 200);
    assert.match(await page.text(), /Create your owner account/);
    assert.equal(
      (await call("/api/setup", credentials)).status,
      403,
      "bootstrap requires the local setup key",
    );
    assert.equal((await call("/api/me")).status, 401, "account endpoint requires authentication");
    assert.equal((await call("/login", credentials)).status, 401);
    const key = process.env.LEAFWAKE_SETUP_KEY;
    assert.ok(key, "the isolated test controls its setup key");
    const attempts = await Promise.all(
      Array.from({ length: 4 }, () => call("/api/setup", { ...credentials, setupKey: key })),
    );
    assert.equal(attempts.filter((r) => r.status === 201).length, 1, "only one first-owner creation commits");
    assert.equal(
      attempts.filter((r) => r.status === 409).length,
      3,
      "concurrent bootstrap requests cannot create extra owners",
    );
    assert.equal((await (await call("/status")).json()).isInit, true);
    const user = await login();
    await writeFile(state, JSON.stringify(user), { mode: 0o600 });
    const authorized = await call("/api/authorize", {}, { authorization: `Bearer ${user.accessToken}` });
    assert.equal(authorized.status, 200);
    assert.equal((await authorized.json()).user.id, user.id);
    assert.equal((await call("/login", { ...credentials, password: "wrong" })).status, 401);
    assert.equal((await call("/login", {})).status, 400);
    assert.equal((await call("/login", { ...credentials, extra: "x".repeat(17000) })).status, 413);
    const crossOrigin = await call("/login", credentials, { origin: "https://untrusted.invalid" });
    assert.equal(crossOrigin.status, 403, "browser mutations reject unapproved origins");
    const health = await call("/healthz");
    assert.equal(health.status, 200);
    assert.equal((await health.json()).status, "ready");
  });
}
