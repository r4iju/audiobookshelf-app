import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import test from "node:test";

const base = process.env.LEAFWAKE_TRANSCODE_TEST_URL || "http://127.0.0.1:19896";
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
async function json(path, token, data) {
  const r = await call(path, token, data);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("authenticated HLS negotiation seeks across real source files and closes durably", async () => {
  const key = randomUUID();
  const root = `/Users/emanuel/.cache/leafwake/fullstack-media-154/transcode-${key}`;
  await mkdir(`${root}/Boundary book`, { recursive: true });
  for (const [name, frequency, duration] of [
    ["01.wav", 440, 7],
    ["02.wav", 880, 9],
  ])
    execFileSync("ffmpeg", [
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      `sine=frequency=${frequency}:duration=${duration}`,
      "-c:a",
      "pcm_s16le",
      `${root}/Boundary book/${name}`,
    ]);
  await writeFile(`${root}/Boundary book/metadata.json`, JSON.stringify({ title: "Boundary book" }));
  const owner = (
    await json("/login", null, { username: "import-owner", password: "synthetic-password-2026" })
  ).user;
  const library = await json("/api/libraries", owner.accessToken, {
    name: `Transcode ${key}`,
    mediaType: "book",
    folders: [{ fullPath: root }],
  });
  await json(`/api/libraries/${library.id}/scan`, owner.accessToken, {});
  const item = (await json(`/api/libraries/${library.id}/items`, owner.accessToken)).results[0];
  const session = await json(`/api/items/${item.id}/play`, owner.accessToken, { forceTranscode: true });
  assert.equal(session.playMethod, 1);
  assert.equal(session.audioTracks.length, 1);
  assert.ok(Math.abs(session.duration - 16) < 0.1);
  const manifest = session.audioTracks[0].contentUrl;
  assert.match(manifest, /^\/hls\//);
  assert.equal((await call(manifest, null)).status, 401);
  const playlistUrl = `${base}${manifest}?token=${owner.accessToken}`;
  const playlist = await (await fetch(playlistUrl)).text();
  assert.match(playlist, /#EXT-X-ENDLIST/);
  const segments = playlist.split("\n").filter((line) => line && !line.startsWith("#"));
  assert.equal(segments.length, 3);
  for (const [index, uri] of segments.entries()) {
    const url = new URL(uri, playlistUrl);
    assert.equal((await fetch(new URL(url.pathname, base))).status, 401);
    const response = await fetch(url);
    assert.equal(response.status, 200, await response.clone().text());
    const filename = `/tmp/leafwake-transcode-${key}-${index}.ts`;
    await writeFile(filename, Buffer.from(await response.arrayBuffer()));
    const probe = JSON.parse(
      execFileSync("ffprobe", ["-v", "error", "-show_streams", "-show_format", "-of", "json", filename], {
        encoding: "utf8",
      }),
    );
    assert.equal(probe.streams[0].codec_name, "aac");
    assert.ok(Math.abs(Number(probe.format.duration) - (index === 2 ? 4 : 6)) < 0.2);
    const decoded = execFileSync("ffmpeg", [
      "-v",
      "error",
      "-i",
      filename,
      "-f",
      "s16le",
      "-ac",
      "1",
      "-ar",
      "8000",
      "pipe:1",
    ]);
    assert.ok(decoded.length > 60000);
    if (index === 1) {
      const frequencyAt = (seconds) => {
        let crossings = 0;
        const start = Math.floor(seconds * 8000),
          end = start + 4000;
        for (let i = start + 1; i < end; i++)
          if (decoded.readInt16LE((i - 1) * 2) < 0 && decoded.readInt16LE(i * 2) >= 0) crossings++;
        return crossings * 2;
      };
      assert.ok(Math.abs(frequencyAt(0.1) - 440) < 20, "first source at boundary");
      assert.ok(Math.abs(frequencyAt(2) - 880) < 20, "second source at boundary");
    }
  }
  const negotiated = await json(`/api/items/${item.id}/play`, owner.accessToken, {
    supportedMimeTypes: ["audio/aac"],
  });
  assert.equal(negotiated.playMethod, 1);
  const other = await json("/api/users", owner.accessToken, {
    username: `transcode-${key}`,
    password: "synthetic-password-2026",
    type: "user",
  });
  const otherLogin = (
    await json("/login", null, { username: other.username, password: "synthetic-password-2026" })
  ).user;
  assert.equal((await call(manifest, otherLogin.accessToken)).status, 404);
  await json(`/api/session/${session.id}/close`, owner.accessToken, {});
  assert.equal((await call(manifest, owner.accessToken)).status, 404);
  console.log("Closed persisted transcode session", session.id);
});
