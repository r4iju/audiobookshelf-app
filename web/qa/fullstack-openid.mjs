import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import test from "node:test";

const base = process.env.LEAFWAKE_OPENID_TEST_URL || "http://127.0.0.1:19902";
async function api(path, token, value, method = value === undefined ? "GET" : "PATCH") {
  const r = await fetch(base + path, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: value === undefined ? undefined : JSON.stringify(value),
  });
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("configured provider signs in through persisted PKCE exchange without legacy server", async () => {
  const login = await fetch(base + "/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "import-owner", password: "synthetic-password-2026" }),
  }).then((r) => r.json());
  const token = login.user.accessToken;
  const _initial = await api("/api/admin/openid/settings", token);
  const settings = {
    enabled: true,
    issuer: "http://host.docker.internal:19884",
    publicUrl: base,
    clientId: "abs-web-qa",
    clientSecret: "abs-web-qa-secret",
    redirectUris: [base + "/oauth", "audiobookshelf-native-preview://oauth"],
    allowRegistration: true,
    buttonText: "Synthetic provider",
    autoLaunch: false,
  };
  await api("/api/admin/openid/settings", token, settings);
  const saved = await api("/api/admin/openid/settings", token);
  assert.equal(saved.clientSecret, undefined);
  assert.equal(saved.hasClientSecret, true);
  const status = await fetch(base + "/status").then((r) => r.json());
  assert.ok(status.authMethods.includes("openid"));
  async function flow(verifier = randomBytes(32).toString("base64url"), redirect = base + "/oauth") {
    const state = randomBytes(24).toString("base64url"),
      challenge = createHash("sha256").update(verifier).digest("base64url");
    const query = new URLSearchParams({
      state,
      code_challenge: challenge,
      code_challenge_method: "S256",
      redirect_uri: redirect,
      client_id: "Audiobookshelf-Web",
      response_type: "code",
    });
    const r = await fetch(base + "/auth/openid?" + query, { redirect: "manual" });
    assert.equal(r.status, 302);
    const cookie = r.headers.get("set-cookie").split(";")[0];
    const provider = new URL(r.headers.get("location"));
    assert.equal(provider.searchParams.get("state"), state);
    assert.equal(provider.searchParams.get("code_challenge"), challenge);
    provider.hostname = "127.0.0.1";
    const params = provider.searchParams;
    params.set("decision", "allow");
    const granted = await fetch(provider.origin + "/authorize", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: params,
      redirect: "manual",
    });
    assert.equal(granted.status, 302);
    const callback = await fetch(granted.headers.get("location"), {
      headers: { cookie },
      redirect: "manual",
    });
    assert.equal(callback.status, 302);
    const returned = new URL(callback.headers.get("location"));
    assert.equal(returned.searchParams.get("state"), state);
    return { state, code: returned.searchParams.get("code"), verifier, cookie };
  }
  async function exchange(f, verifier = f.verifier) {
    return fetch(
      base +
        "/auth/openid/callback?" +
        new URLSearchParams({ state: f.state, code: f.code, code_verifier: verifier }),
      { headers: { cookie: f.cookie, "x-return-tokens": "true" }, redirect: "manual" },
    );
  }
  const f = await flow();
  const response = await exchange(f);
  assert.equal(response.status, 200);
  const account = await response.json();
  assert.equal(account.user.type, "user");
  assert.ok(account.user.accessToken);
  assert.ok(account.user.refreshToken);
  assert.equal((await exchange(f)).status, 400);
  const bad = await flow();
  assert.equal((await exchange(bad, randomBytes(32).toString("base64url"))).status, 400);
  assert.equal(
    (
      await fetch(
        base +
          "/auth/openid?" +
          new URLSearchParams({
            state: "abc",
            code_challenge: "abc",
            code_challenge_method: "S256",
            redirect_uri: "https://evil.example",
            response_type: "code",
          }),
        { redirect: "manual" },
      )
    ).status,
    400,
  );
  const native = await flow(undefined, "audiobookshelf-native-preview://oauth");
  const nativeResponse = await exchange(native);
  assert.equal(nativeResponse.status, 200);
  assert.equal((await nativeResponse.json()).user.id, account.user.id);
  await api("/api/admin/openid/settings", token, { ...saved, enabled: false, clientSecret: null });
  console.log("Provider identity, browser/native PKCE, masked secret and replay denial passed");
});
