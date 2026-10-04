import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { completeSource } from "./complete-source.mjs";

const base = process.env.LEAFWAKE_COMPLETE_MIGRATION_TEST_URL || "http://127.0.0.1:19914";
const operatorKey = "synthetic-complete-migration-2026";
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
async function json(path, data, token, method) {
  const r = await call(path, data, token, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
const sha = async (path) =>
  createHash("sha256")
    .update(await readFile(path))
    .digest("hex");
async function oidc() {
  const state = randomBytes(24).toString("base64url"),
    verifier = randomBytes(32).toString("base64url"),
    challenge = createHash("sha256").update(verifier).digest("base64url");
  const start = await fetch(
    base +
      "/auth/openid?" +
      new URLSearchParams({
        state,
        code_challenge: challenge,
        code_challenge_method: "S256",
        redirect_uri: base + "/oauth",
        client_id: "Audiobookshelf-Web",
        response_type: "code",
      }),
    { redirect: "manual" },
  );
  assert.equal(start.status, 302);
  const cookie = start.headers.get("set-cookie").split(";")[0],
    provider = new URL(start.headers.get("location"));
  provider.hostname = "127.0.0.1";
  provider.searchParams.set("decision", "allow");
  const grant = await fetch(provider.origin + "/authorize", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: provider.searchParams,
    redirect: "manual",
  });
  assert.equal(grant.status, 302);
  const callback = await fetch(grant.headers.get("location"), { headers: { cookie }, redirect: "manual" });
  assert.equal(callback.status, 302);
  const returned = new URL(callback.headers.get("location"));
  assert.equal(returned.searchParams.get("state"), state);
  const exchange = await fetch(
    base +
      "/auth/openid/callback?" +
      new URLSearchParams({ state, code: returned.searchParams.get("code"), code_verifier: verifier }),
    { headers: { cookie, "x-return-tokens": "true" }, redirect: "manual" },
  );
  assert.equal(exchange.status, 200);
  return exchange.json();
}
test("complete read-only migration retains OpenID identity, cover bytes, configuration and all imported relations without silent cutover", async () => {
  const fixture = await completeSource({
      unsupported:
        process.env.LEAFWAKE_COMPLETE_MIGRATION_UNSUPPORTED === "nested"
          ? "nested"
          : process.env.LEAFWAKE_COMPLETE_MIGRATION_UNSUPPORTED === "1",
    }),
    digest = await sha(fixture.filename);
  const setup = { setupKey: operatorKey, sourcePath: fixture.sourcePath };
  const inspected = await json("/api/setup/import/inspect", setup);
  assert.equal(
    inspected.canImport,
    true,
    "linked OpenID-only ordinary accounts must be staged without granting password access",
  );
  await json("/api/setup/import", { ...setup, expectedDigest: digest });
  const owner = (await json("/login", { username: "import-owner", password: "synthetic-password-2026" }))
      .user,
    token = owner.accessToken;
  assert.equal(
    (await call("/login", { username: "import-user", password: "synthetic-password-2026" })).status,
    401,
  );
  const mappings = [
    { from: "/old/synthetic/books", to: fixture.mediaRoot },
    { from: "/old/synthetic/podcasts", to: fixture.podcastRoot },
  ];
  const media = await json(
    "/api/admin/migrations/media/inspect",
    { sourcePath: fixture.sourcePath, mappings },
    token,
  );
  assert.equal(media.canImport, true);
  assert.equal(media.counts.listeningSeconds, 47);
  await json(
    "/api/admin/migrations/media",
    { sourcePath: fixture.sourcePath, mappings, expectedDigest: digest },
    token,
  );
  const podcast = await json(`/api/items/${fixture.podcastItemId}`, undefined, token);
  assert.equal(
    podcast.media.episodes.find((episode) => episode.id === fixture.remoteEpisodeId)?.enclosure?.url,
    "https://feed.example.invalid/new.mp3",
    "undownloaded source episodes retain their original enclosure URL",
  );
  await json("/api/admin/migrations/lists", { digest }, token);
  await json("/api/admin/migrations/delivery", { digest, serverAddress: base }, token);
  const input = {
    digest,
    sourcePath: fixture.sourcePath,
    publicUrl: base,
    coverMappings: [{ from: "/old/metadata", to: "/imports/metadata" }],
    redirectUris: [base + "/oauth", "audiobookshelf-native-preview://oauth"],
  };
  const report = await json("/api/admin/migrations/complete/inspect", input, token);
  assert.equal(report.canImport, !process.env.LEAFWAKE_COMPLETE_MIGRATION_UNSUPPORTED);
  assert.equal(report.counts.openIdIdentities, 1);
  assert.equal(report.counts.covers, 1);
  assert.ok(report.inventory.every((row) => row.disposition && row.table));
  assert.ok(!JSON.stringify(report).includes("abs-web-qa-secret"));
  assert.ok(!JSON.stringify(report).includes("synthetic-private-password"));
  const unknown = report.unsupported.some((row) =>
    process.env.LEAFWAKE_COMPLETE_MIGRATION_UNSUPPORTED === "nested"
      ? row.table === "mediaProgresses" && row.fields.some((field) => field.includes("customReaderState"))
      : row.table === "unsupportedNotes",
  );
  assert.equal(unknown, Boolean(process.env.LEAFWAKE_COMPLETE_MIGRATION_UNSUPPORTED));
  if (unknown) {
    assert.equal(report.canCutover, false);
    assert.equal((await call("/api/admin/migrations/complete", input, token)).status, 409);
    assert.equal((await json("/api/admin/openid/settings", undefined, token)).enabled, false);
    assert.equal(await sha(fixture.filename), digest);
    return;
  }
  assert.equal(report.canCutover, true);
  const result = await json("/api/admin/migrations/complete", input, token);
  assert.deepEqual(await json("/api/admin/migrations/complete", input, token), result);
  const user = (await oidc()).user;
  assert.equal(
    user.id,
    fixture.ids.user,
    "same issuer/subject resolves original user, not a new matching-name account",
  );
  assert.equal(user.username, "import-user");
  assert.ok(user.bookmarks.some((b) => b.title === "Original bookmark"));
  const settings = await json("/api/settings", undefined, token);
  assert.equal(settings.loginMessage, "Original sign-in notice");
  assert.equal(settings.rateLimitLoginRequests, 9);
  assert.deepEqual(
    Buffer.from(
      await (await call(`/api/items/${fixture.ids.item}/cover`, undefined, user.accessToken)).arrayBuffer(),
    ),
    fixture.cover,
  );
  const stats = await json("/api/me/listening-stats", undefined, user.accessToken);
  assert.equal(stats.totalTime, 47);
  const playlist = await json(`/api/playlists/${fixture.playlistId}`, undefined, user.accessToken);
  assert.equal(playlist.userId, fixture.ids.user);
  assert.deepEqual(
    playlist.items.map((v) => v.libraryItemId),
    [fixture.ids.item],
  );
  assert.equal((await call(`/api/playlists/${fixture.playlistId}`, undefined, token)).status, 404);
  const feed = await fetch(base + "/feed/original-slug");
  assert.equal(feed.status, 200);
  assert.ok((await feed.text()).includes("original-episode"));
  assert.equal(await sha(fixture.filename), digest);
  console.log(
    JSON.stringify({
      digest,
      sourcePath: fixture.sourcePath,
      userId: fixture.ids.user,
      itemId: fixture.ids.item,
      playlistId: fixture.playlistId,
      stage: result.id,
    }),
  );
});
