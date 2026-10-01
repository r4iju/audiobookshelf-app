// Serves a synthetic podcast RSS feed on loopback for the QA server (which reaches it as host.docker.internal), so
// adding podcasts and downloading episodes is exercised without any internet access.
import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const FEED_PORT = Number(process.env.ABS_QA_FEED_PORT ?? 19885);
const media = join(dirname(fileURLToPath(import.meta.url)), ".runtime", "feed");
const base = `http://host.docker.internal:${FEED_PORT}`;

function statSafe(name) {
  const path = join(media, name);
  return existsSync(path) ? statSync(path).size : 0;
}

// The slow variant holds each episode download open long enough for the server's download queue to be seen.
const SLOW_MEDIA_MS = 6000;
const shows = {
  "/feed.xml": { title: "QA Feed Show", media: "/media" },
  "/slow/feed.xml": { title: "QA Slow Show", media: "/slow/media" },
};

// Built per request: the media may be generated after this server starts.
const feed = (show) => {
  const episodes = [1, 2].map((n) => ({
    title: `Feed Episode ${n}`,
    guid: `qa-feed-episode-${n}`,
    date: new Date(Date.UTC(2026, 8, 10 + n)).toUTCString(),
    url: `${base}${show.media}/feed-episode-${n}.mp3`,
    length: statSafe(`feed-episode-${n}.mp3`),
  }));
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
<title>${show.title}</title>
<link>${base}/</link>
<description>A synthetic podcast served on loopback for browser QA.</description>
<language>en</language>
<itunes:author>QA Feed Studio</itunes:author>
<itunes:image href="${base}/media/cover.jpg"/>
<itunes:type>episodic</itunes:type>
${episodes
  .map(
    (episode) => `<item>
<title>${episode.title}</title>
<guid>${episode.guid}</guid>
<pubDate>${episode.date}</pubDate>
<description>${episode.title} of the QA feed.</description>
<itunes:duration>12</itunes:duration>
<enclosure url="${episode.url}" length="${episode.length}" type="audio/mpeg"/>
</item>`,
  )
  .join("\n")}
</channel>
</rss>`;
};

const server = createServer(async (request, response) => {
  const path = new URL(request.url ?? "/", base).pathname;
  if (Object.hasOwn(shows, path)) {
    response.writeHead(200, { "Content-Type": "application/rss+xml" });
    return response.end(feed(shows[path]));
  }
  const slow = path.startsWith("/slow/media/");
  if (slow) await new Promise((resolve) => setTimeout(resolve, SLOW_MEDIA_MS));
  const name = slow
    ? path.slice("/slow/media/".length)
    : path.startsWith("/media/")
      ? path.slice("/media/".length)
      : null;
  const file = name ? join(media, name) : null;
  if (file && dirname(file) === media && existsSync(file)) {
    response.writeHead(200, {
      "Content-Type": file.endsWith(".jpg") ? "image/jpeg" : "audio/mpeg",
      "Content-Length": statSync(file).size,
    });
    return createReadStream(file).pipe(response);
  }
  response.writeHead(404).end();
});

if (process.argv[1] === fileURLToPath(import.meta.url))
  server.listen(FEED_PORT, process.env.ABS_QA_FIXTURE_HOST ?? "127.0.0.1", () =>
    console.log(`QA feed on http://127.0.0.1:${FEED_PORT}/feed.xml`),
  );
