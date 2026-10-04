import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import test from "node:test";

const base = process.env.LEAFWAKE_PODCAST_TEST_URL || "http://127.0.0.1:19902";
const host = "http://host.docker.internal:19905";
async function call(path, token, data, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, token, data, method) {
  const r = await call(path, token, data, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
async function until(fn) {
  for (let i = 0; i < 160; i++) {
    const value = await fn();
    if (value) return value;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw Error("Schedule did not finish");
}
test("configured discovery, persisted owner limits, stable automatic updates and provider errors", async () => {
  let version = 1;
  let downloads = 0;
  let broken = false;
  const path = "/tmp/leafwake-schedule-audio.mp3";
  execFileSync("ffmpeg", [
    "-y",
    "-v",
    "error",
    "-f",
    "lavfi",
    "-i",
    "sine=frequency=990:duration=2",
    "-c:a",
    "libmp3lame",
    path,
  ]);
  const audio = readFileSync(path);
  const fixture = createServer((req, res) => {
    if (req.url.startsWith("/search")) {
      res.setHeader("Content-Type", "application/json");
      res.statusCode = broken ? 503 : 200;
      return res.end(
        JSON.stringify({
          results: [
            {
              collectionId: 42,
              collectionName: "Controlled show",
              artistName: "Fixture author",
              feedUrl: host + "/feed.xml",
              genres: ["Books"],
            },
          ],
        }),
      );
    }
    if (req.url === "/feed.xml")
      return res.end(
        `<rss version="2.0"><channel><title>Scheduled show</title>${Array.from({ length: version }, (_, i) => `<item><title>Episode ${i + 1}</title><guid>scheduled-${i + 1}</guid><pubDate>${new Date(2025, 0, i + 1).toUTCString()}</pubDate><enclosure url="${host}/audio-${i + 1}.mp3" type="audio/mpeg" /></item>`).join("")}</channel></rss>`,
      );
    downloads++;
    res.setHeader("Content-Length", audio.length);
    res.end(audio);
  });
  await new Promise((r) => fixture.listen(19905, "0.0.0.0", r));
  try {
    const login = await json("/login", "", { username: "import-owner", password: "synthetic-password-2026" });
    const token = login.user.accessToken;
    const initial = await json("/api/admin/podcasts/settings", token);
    const settings = {
      ...initial,
      discoveryEnabled: true,
      providerUrl: host + "/search",
      country: "GB",
      updateIntervalMinutes: 60,
      maxQueue: 8,
      maxConcurrent: 1,
      maxEpisodeBytes: 1048576,
      downloadTimeoutSeconds: 30,
      retentionEpisodes: 2,
    };
    await json("/api/admin/podcasts/settings", token, settings, "PATCH");
    assert.deepEqual(await json("/api/admin/podcasts/settings", token), settings);
    const guest = await json("/api/users", token, {
      username: "schedule-" + randomUUID(),
      password: "synthetic-guest-password",
      type: "user",
    });
    const guestLogin = await json("/login", "", {
      username: guest.username,
      password: "synthetic-guest-password",
    });
    assert.equal((await call("/api/admin/podcasts/settings", guestLogin.user.accessToken)).status, 403);
    const results = await json("/api/search/podcast?term=controlled", token);
    assert.equal(results[0].title, "Controlled show");
    assert.equal(results[0].feedUrl, host + "/feed.xml");
    broken = true;
    assert.equal((await call("/api/search/podcast?term=unavailable", token)).status, 503);
    broken = false;
    const library = await json("/api/libraries", token, {
      name: "Scheduled " + randomUUID(),
      mediaType: "podcast",
      folders: [{ fullPath: "/data/media" }],
    });
    const feed = await json("/api/podcasts/feed", token, { rssFeed: host + "/feed.xml" });
    const item = await json("/api/podcasts", token, {
      libraryId: library.id,
      folderId: library.folders[0].id,
      path: "/data/media/scheduled-" + randomUUID(),
      media: { metadata: feed.podcast.metadata, autoDownloadEpisodes: true },
    });
    await until(async () => (await json(`/api/items/${item.id}`, token)).media.episodes.length === 1);
    version = 2;
    await json(`/api/podcasts/${item.id}/check`, token, {});
    await until(async () => (await json(`/api/items/${item.id}`, token)).media.episodes.length === 2);
    const ids = (await json(`/api/items/${item.id}`, token)).media.episodes.map((e) => e.id);
    await json(`/api/podcasts/${item.id}/check`, token, {});
    assert.equal(downloads, 2);
    assert.deepEqual(
      (await json(`/api/items/${item.id}`, token)).media.episodes.map((e) => e.id),
      ids,
    );
    version = 3;
    await json(`/api/podcasts/${item.id}/check`, token, {});
    await until(
      async () =>
        (await json(`/api/items/${item.id}`, token)).media.episodes.some((e) => e.title === "Episode 3") &&
        (await json(`/api/items/${item.id}`, token)).media.episodes.length === 2,
    );
    assert.equal(downloads, 3);
    await json(`/api/podcasts/${item.id}/check`, token, {});
    assert.equal(downloads, 3, "retention does not redownload old episodes");
    const status = await json(`/api/podcasts/${item.id}/schedule`, token);
    assert.ok(status.lastCheckedAt > 0);
    assert.equal(status.lastError, null);
    console.log(JSON.stringify({ libraryId: library.id, itemId: item.id, settings, downloads }));
    await json("/api/admin/podcasts/settings", token, initial, "PATCH");
  } finally {
    fixture.closeAllConnections();
    await new Promise((r) => fixture.close(r));
  }
});
