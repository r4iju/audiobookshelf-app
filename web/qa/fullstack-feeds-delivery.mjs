import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

const base = process.env.LEAFWAKE_FEED_TEST_URL || "http://127.0.0.1:19902";
async function request(path, token, value, method = value === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: value === undefined ? undefined : JSON.stringify(value),
  });
}
async function json(path, token, value, method) {
  const r = await request(path, token, value, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("intentional RSS publishing and permitted ebook SMTP delivery use real mounted bytes", async () => {
  const login = await json("/login", "", { username: "import-owner", password: "synthetic-password-2026" }),
    token = login.user.accessToken;
  const initialFeeds = await json("/api/feeds", token);
  assert.ok(Array.isArray(initialFeeds.feeds));
  const libraries = (await json("/api/libraries", token)).libraries;
  let audio, ebook;
  for (const library of libraries) {
    const items = (await json(`/api/libraries/${library.id}/items?limit=200`, token)).results;
    audio ??= items.find((i) => i.media.tracks?.length);
    ebook ??= items.find((i) => i.media.ebookFile);
    if (audio && ebook) break;
  }
  assert.ok(audio);
  assert.ok(ebook);
  const slug = "synthetic-" + randomUUID(),
    body = {
      serverAddress: base,
      slug,
      metadataDetails: {
        preventIndexing: true,
        ownerName: "Synthetic owner",
        ownerEmail: "owner@example.invalid",
      },
    };
  const { feed } = await json(`/api/feeds/item/${audio.id}/open`, token, body);
  assert.ok(feed.id);
  assert.equal(feed.feedUrl, `/feed/${slug}`);
  assert.equal((await request(`/api/feeds/item/${audio.id}/open`, token, body)).status, 409);
  assert.equal((await json(`/api/items/${audio.id}`, token)).rssFeed.id, feed.id);
  const rss = await fetch(base + feed.feedUrl);
  assert.equal(rss.status, 200);
  const xml = await rss.text();
  assert.ok(xml.includes("Synthetic owner"));
  assert.ok(xml.includes("<itunes:block>Yes</itunes:block>"));
  const enclosure = xml.match(/enclosure url="([^"]+)"/)[1].replaceAll("&amp;", "&");
  const bytes = await fetch(enclosure);
  assert.equal(bytes.status, 200);
  assert.ok((await bytes.arrayBuffer()).byteLength > 100);
  const range = await fetch(enclosure, { headers: { range: "bytes=0-15" } });
  assert.equal(range.status, 206);
  assert.equal((await range.arrayBuffer()).byteLength, 16);
  await json(`/api/feeds/${feed.id}/close`, token, {}, "POST");
  assert.equal((await fetch(base + feed.feedUrl)).status, 404);
  assert.equal((await fetch(enclosure)).status, 404);
  await json(
    "/api/emails/settings",
    token,
    {
      host: "host.docker.internal",
      port: 19906,
      secure: false,
      fromAddress: "leafwake@example.invalid",
      username: "",
      password: "synthetic-mail-secret",
    },
    "PATCH",
  );
  const settings = await json("/api/emails/settings", token);
  assert.equal(settings.password, undefined);
  assert.equal(settings.hasPassword, true);
  await json("/api/emails/ereader-devices", token, {
    ereaderDevices: [
      {
        name: "Synthetic Reader",
        email: "reader@example.invalid",
        availabilityOption: "userOrUp",
        users: [],
      },
      { name: "Bouncing Reader", email: "reader@bounce.invalid", availabilityOption: "adminOrUp", users: [] },
    ],
  });
  assert.ok(
    (await json("/api/authorize", token, {})).ereaderDevices.some((d) => d.name === "Synthetic Reader"),
  );
  await json("/api/emails/send-ebook-to-device", token, {
    libraryItemId: ebook.id,
    deviceName: "Synthetic Reader",
  });
  const files = readdirSync(new URL("./.runtime/mail", import.meta.url));
  const messages = files
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(new URL("./.runtime/mail/" + f, import.meta.url), "utf8")));
  assert.ok(
    messages.some(
      (m) => m.to.includes("<reader@example.invalid>") && m.data.includes("Content-Disposition: attachment"),
    ),
  );
  assert.equal(
    (
      await request("/api/emails/send-ebook-to-device", token, {
        libraryItemId: ebook.id,
        deviceName: "Bouncing Reader",
      })
    ).status,
    400,
  );
  console.log("Real RSS/media closure/ranges and SMTP attachment success/failure passed");
});
