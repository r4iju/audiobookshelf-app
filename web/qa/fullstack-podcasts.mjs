import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import test from "node:test";
import { io } from "socket.io-client";

const base = process.env.LEAFWAKE_PODCAST_TEST_URL || "http://127.0.0.1:19902";
const feedHost = process.env.LEAFWAKE_PODCAST_FIXTURE_HOST || "host.docker.internal";
async function call(path, token, data, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(data === undefined ? {} : { "content-type": "application/json" }),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, token, data, method) {
  const r = await call(path, token, data, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
async function eventually(fn, message) {
  for (let i = 0; i < 120; i++) {
    const value = await fn();
    if (value) return value;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(message);
}
test("feed subscription, bounded durable queue, episode playback/progress and removal", async () => {
  const audioPath = `/tmp/leafwake-podcast-${randomUUID()}.mp3`;
  execFileSync("ffmpeg", [
    "-v",
    "error",
    "-f",
    "lavfi",
    "-i",
    "sine=frequency=880:duration=7",
    "-c:a",
    "libmp3lame",
    audioPath,
  ]);
  const audio = await readFile(audioPath);
  let downloads = 0;
  const feedUrl = `http://${feedHost}:19905/feed.xml`;
  const fixture = createServer((req, res) => {
    if (req.url === "/feed.xml") {
      res.setHeader("content-type", "application/rss+xml");
      res.end(
        `<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Synthetic Feed</title><itunes:author>Local fixture author</itunes:author><description>Bounded feed test</description><language>en</language><item><title>First episode</title><guid>original-guid-1</guid><pubDate>Wed, 01 Jan 2025 00:00:00 GMT</pubDate><itunes:duration>00:00:07</itunes:duration><enclosure url="http://${feedHost}:19905/episode.mp3" type="audio/mpeg" length="${audio.length}"/></item></channel></rss>`,
      );
      return;
    }
    if (req.url === "/episode.mp3") {
      downloads++;
      res.setHeader("content-type", "audio/mpeg");
      res.setHeader("content-length", audio.length);
      setTimeout(() => res.end(audio), 500);
      return;
    }
    res.statusCode = 404;
    res.end();
  });
  await new Promise((resolve, reject) => {
    fixture.once("error", reject);
    fixture.listen(19905, "0.0.0.0", resolve);
  });
  const socket = io(base, { transports: ["websocket"] }),
    events = [];
  try {
    const user = (
        await json("/login", null, { username: "import-owner", password: "synthetic-password-2026" })
      ).user,
      token = user.accessToken;
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("No socket init")), 3000);
      socket.on("connect", () => socket.emit("auth", token));
      socket.once("init", () => {
        clearTimeout(timer);
        resolve();
      });
      if (socket.connected) socket.emit("auth", token);
    });
    socket.onAny((name, data) => events.push({ name, data }));
    assert.equal((await call("/api/podcasts/feed", token, { rssFeed: "file:///etc/passwd" })).status, 400);
    assert.equal(
      (await call("/api/podcasts/feed", token, { rssFeed: "http://127.0.0.1:3000/status" })).status,
      400,
      "LAN requires explicit host configuration",
    );
    const feed = await json("/api/podcasts/feed", token, { rssFeed: feedUrl });
    assert.equal(feed.podcast.metadata.title, "Synthetic Feed");
    assert.equal(feed.podcast.episodes[0].guid, "original-guid-1");
    const library = await json("/api/libraries", token, {
      name: `Podcasts ${randomUUID()}`,
      mediaType: "podcast",
      folders: [{ fullPath: "/data/media" }],
    });
    const item = await json("/api/podcasts", token, {
      libraryId: library.id,
      folderId: library.folders[0].id,
      path: `/data/media/feed-${randomUUID()}`,
      media: { metadata: feed.podcast.metadata, autoDownloadEpisodes: false },
    });
    await json(`/api/podcasts/${item.id}/download-episodes`, token, feed.podcast.episodes);
    await json(`/api/podcasts/${item.id}/download-episodes`, token, feed.podcast.episodes);
    const completed = await eventually(async () => {
      const current = await json(`/api/items/${item.id}`, token);
      return current.media.episodes?.length === 1 ? current : null;
    }, "Episode download not completed");
    assert.equal(downloads, 1, "duplicate enqueue downloads only once");
    const episode = completed.media.episodes[0];
    assert.ok(episode.duration >= 6.9 && episode.duration < 7.2);
    assert.ok(events.some((e) => e.name === "episode_download_queued"));
    assert.ok(events.some((e) => e.name === "episode_download_finished"));
    const session = await json(`/api/items/${item.id}/play/${episode.id}`, token, {
      supportedMimeTypes: ["audio/mpeg"],
    });
    assert.equal(session.episodeId, episode.id);
    assert.equal(session.displayTitle, "First episode");
    const media = await call(session.audioTracks[0].contentUrl, token);
    assert.equal(media.status, 200);
    assert.deepEqual(Buffer.from(await media.arrayBuffer()), audio);
    await json(
      `/api/me/progress/${item.id}/${episode.id}`,
      token,
      { currentTime: 3, updatedAt: Date.now() },
      "PATCH",
    );
    assert.equal((await json(`/api/me/progress/${item.id}/${episode.id}`, token)).currentTime, 3);
    assert.equal(
      (await call(`/api/me/progress/${item.id}`, token)).status,
      404,
      "podcast progress remains episode scoped",
    );
    await json(`/api/session/${session.id}/close`, token, {});
    const recent = await json(`/api/libraries/${library.id}/recent-episodes?limit=24&page=0`, token);
    assert.equal(recent.episodes[0].id, episode.id);
    await json(`/api/podcasts/${item.id}/episode/${episode.id}?hard=1`, token, undefined, "DELETE");
    assert.equal((await json(`/api/items/${item.id}`, token)).media.episodes.length, 0);
    assert.equal((await call(`/api/me/progress/${item.id}/${episode.id}`, token)).status, 404);
    await json(`/api/podcasts/${item.id}/download-episodes`, token, feed.podcast.episodes);
    await json(`/api/podcasts/${item.id}/clear-queue`, token);
    assert.equal((await json(`/api/items/${item.id}`, token)).episodeDownloadsQueued.length, 0);
    console.log(`Podcast fixture library ${library.id} item ${item.id}`);
  } finally {
    socket.disconnect();
    await new Promise((resolve) => fixture.close(resolve));
  }
});
