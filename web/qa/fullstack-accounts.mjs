import assert from "node:assert/strict";
import test from "node:test";

const origin = process.env.LEAFWAKE_ACCOUNT_TEST_URL || "http://127.0.0.1:19888";
async function request(path, { method = "GET", data, token, refresh } = {}) {
  return fetch(origin + path, {
    method,
    headers: {
      ...(data === undefined ? {} : { "content-type": "application/json" }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(refresh ? { "x-refresh-token": refresh } : {}),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
    signal: AbortSignal.timeout(15000),
  });
}
async function signIn(username, password = "synthetic-password-2026") {
  const response = await request("/login", { method: "POST", data: { username, password } });
  assert.equal(response.status, 200);
  return (await response.json()).user;
}
test("account administration restricts roles and immediately revokes removed authority", async () => {
  const owner = await signIn("installation-owner");
  const token = owner.accessToken;
  const list = await request("/api/users", { token });
  assert.equal(list.status, 200, "owner can administer accounts");
  assert.ok((await list.json()).users.some((u) => u.id === owner.id));
  const name = `restricted-${Date.now()}`;
  const created = await request("/api/users", {
    method: "POST",
    token,
    data: {
      username: name,
      password: "synthetic-password-2026",
      type: "user",
      permissions: {
        download: false,
        update: false,
        delete: false,
        upload: false,
        accessExplicitContent: false,
        accessAllLibraries: false,
        accessAllTags: false,
      },
      librariesAccessible: ["permitted-library"],
      itemTagsSelected: ["safe"],
    },
  });
  assert.equal(created.status, 200);
  const user = await created.json();
  assert.equal(user.password_hash, undefined);
  assert.equal(user.passwordHash, undefined);
  const partial = await request(`/api/users/${user.id}`, {
    method: "PATCH",
    token,
    data: { permissions: { download: true } },
  });
  assert.equal(partial.status, 200);
  const policy = await partial.json();
  assert.equal(
    policy.permissions.accessAllLibraries,
    false,
    "partial changes retain restricted library policy",
  );
  assert.equal(policy.permissions.accessAllTags, false, "partial changes retain restricted tag policy");
  const session = await signIn(name);
  assert.equal(session.permissions.accessAllLibraries, false);
  assert.deepEqual(session.librariesAccessible, ["permitted-library"]);
  assert.equal((await request("/api/users", { token: session.accessToken })).status, 403);
  assert.equal(
    (
      await request("/api/users", {
        method: "POST",
        token: session.accessToken,
        data: { username: "escalation", password: "synthetic-password-2026", type: "admin" },
      })
    ).status,
    403,
  );
  assert.equal(
    (await request(`/api/users/${owner.id}`, { method: "DELETE", token })).status,
    403,
    "owner cannot be deleted",
  );
  assert.equal(
    (
      await request("/api/users", {
        method: "POST",
        token,
        data: { username: "second-owner", password: "synthetic-password-2026", type: "root" },
      })
    ).status,
    400,
  );
  assert.equal(
    (await request(`/api/users/${user.id}/revoke`, { method: "POST", token, data: {} })).status,
    200,
  );
  assert.equal((await request("/api/me", { token: session.accessToken })).status, 401);
  assert.equal(
    (await request("/auth/refresh", { method: "POST", refresh: session.refreshToken })).status,
    401,
  );
  const again = await signIn(name);
  assert.equal((await request("/logout", { method: "POST", refresh: again.refreshToken })).status, 200);
  assert.equal((await request("/api/me", { token: again.accessToken })).status, 401);
  assert.equal((await request("/auth/refresh", { method: "POST", refresh: again.refreshToken })).status, 401);
  const active = await signIn(name);
  const disabled = await request(`/api/users/${user.id}`, {
    method: "PATCH",
    token,
    data: { isActive: false },
  });
  assert.equal(disabled.status, 200);
  assert.equal((await request("/api/me", { token: active.accessToken })).status, 401);
  assert.equal(
    (
      await request("/login", {
        method: "POST",
        data: { username: name, password: "synthetic-password-2026" },
      })
    ).status,
    401,
  );
  assert.equal(
    (
      await request(`/api/users/${user.id}`, {
        method: "PATCH",
        token,
        data: { isActive: true, password: "replacement-password-2026" },
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await request("/login", {
        method: "POST",
        data: { username: name, password: "synthetic-password-2026" },
      })
    ).status,
    401,
  );
  await signIn(name, "replacement-password-2026");
  assert.equal((await request(`/api/users/${user.id}`, { method: "DELETE", token })).status, 200);
  assert.equal((await request(`/api/users/${user.id}`, { token })).status, 404);
});
test("repeated rejected credentials are bounded without revealing account existence", async () => {
  const username = `unknown-${Date.now()}`;
  for (let i = 0; i < 12; i++)
    assert.equal(
      (await request("/login", { method: "POST", data: { username, password: "incorrect" } })).status,
      401,
    );
  assert.equal(
    (await request("/login", { method: "POST", data: { username, password: "incorrect" } })).status,
    429,
  );
});
