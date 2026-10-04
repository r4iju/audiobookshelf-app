import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, rename, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";

const base = process.env.LEAFWAKE_STREAM_TEST_URL || "http://127.0.0.1:19891";
const root = process.env.LEAFWAKE_STREAM_TEST_ROOT || "/Users/emanuel/.cache/leafwake/fullstack-media-154";
async function call(path, { method = "GET", data, token, headers = {} } = {}) {
  return fetch(base + path, {
    method,
    headers: {
      ...(data === undefined ? {} : { "content-type": "application/json" }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: data === undefined ? undefined : JSON.stringify(data),
    signal: AbortSignal.timeout(15000),
  });
}
async function login(username = "installation-owner") {
  const response = await call("/login", {
    method: "POST",
    data: { username, password: "synthetic-password-2026" },
  });
  assert.equal(response.status, 200);
  return (await response.json()).user;
}
test("real multi-file playback serves authorized ranges and binds sessions to their account", async () => {
  const folder = join(root, `stream-${Date.now()}`);
  await mkdir(folder, { recursive: true });
  for (let index = 1; index <= 2; index++)
    execFileSync("ffmpeg", [
      "-loglevel",
      "error",
      "-f",
      "lavfi",
      "-i",
      `sine=frequency=${index * 440}:duration=${index}`,
      "-y",
      join(folder, `${index}.mp3`),
    ]);
  await writeFile(join(folder, "metadata.json"), JSON.stringify({ title: "Multi file stream" }));
  const owner = await login();
  const token = owner.accessToken;
  const parts = token.split(".");
  assert.equal(parts.length, 3, "native media clients can determine access expiry before requesting a track");
  const expiry = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")).exp;
  assert.ok(expiry > Date.now() / 1000 && expiry <= Date.now() / 1000 + 16 * 60);
  const library = await (
    await call("/api/libraries", {
      method: "POST",
      token,
      data: { name: "Streaming QA", folders: [{ fullPath: folder }], mediaType: "book" },
    })
  ).json();
  assert.equal(
    (await call(`/api/libraries/${library.id}/scan`, { method: "POST", token, data: {} })).status,
    200,
  );
  const item = (await (await call(`/api/libraries/${library.id}/items`, { token })).json()).results[0];
  assert.ok(item);
  const native = await call(`/api/items/${item.id}/play`, {
    method: "POST",
    token,
    data: {
      forceDirectPlay: "1",
      forceTranscode: "",
      deviceInfo: { clientName: "ios-test", deviceName: "Synthetic device" },
      mediaPlayer: "AVPlayer",
    },
  });
  assert.equal(native.status, 200, "iOS string-valued play flags retain their consumed contract");
  const nativeSession = await native.json();
  assert.equal(nativeSession.timeListening, 0);
  assert.ok(nativeSession.mediaMetadata);
  assert.ok(nativeSession.deviceInfo);
  const played = await call(`/api/items/${item.id}/play`, {
    method: "POST",
    token,
    data: { supportedMimeTypes: ["audio/mpeg"], mediaPlayer: "html5" },
  });
  assert.equal(played.status, 200, "new backend opens real playback");
  const session = await played.json();
  assert.equal(session.libraryItemId, item.id);
  assert.equal(session.playMethod, 0);
  assert.equal(session.audioTracks.length, 2);
  assert.equal(session.chapters.length, 2);
  assert.equal(session.audioTracks[0].startOffset, 0);
  assert.equal(session.audioTracks[1].startOffset, session.audioTracks[0].duration);
  const source = await readFile(join(folder, "1.mp3"));
  const url = session.audioTracks[0].contentUrl;
  assert.equal((await call(url)).status, 401);
  const full = await call(url, { token });
  assert.equal(full.status, 200);
  assert.equal(full.headers.get("content-type"), "audio/mpeg");
  assert.deepEqual(Buffer.from(await full.arrayBuffer()), source);
  const head = await call(url, { method: "HEAD", token });
  assert.equal(head.status, 200);
  assert.equal(Number(head.headers.get("content-length")), source.length);
  assert.equal((await head.arrayBuffer()).byteLength, 0);
  const range = await call(url, { token, headers: { range: "bytes=10-29" } });
  assert.equal(range.status, 206);
  assert.equal(range.headers.get("content-range"), `bytes 10-29/${source.length}`);
  assert.deepEqual(Buffer.from(await range.arrayBuffer()), source.subarray(10, 30));
  const suffix = await call(url, { token, headers: { range: "bytes=-12" } });
  assert.equal(suffix.status, 206);
  assert.deepEqual(Buffer.from(await suffix.arrayBuffer()), source.subarray(-12));
  const invalid = await call(url, { token, headers: { range: `bytes=${source.length}-` } });
  assert.equal(invalid.status, 416);
  assert.equal(invalid.headers.get("content-range"), `bytes */${source.length}`);
  assert.equal((await call(url, { token, headers: { range: "bytes=0-1,3-4" } })).status, 416);
  const track = `/public/session/${session.id}/track/1`;
  assert.equal((await call(track)).status, 401);
  assert.equal((await call(`${track}?token=${token}`)).status, 200);
  const username = `stream-other-${Date.now()}`;
  assert.equal(
    (
      await call("/api/users", {
        method: "POST",
        token,
        data: { username, password: "synthetic-password-2026", type: "user" },
      })
    ).status,
    200,
  );
  const other = await login(username);
  assert.equal((await call(track, { token: other.accessToken })).status, 404);
  assert.equal((await call(`/api/items/${item.id}/file/../../etc/passwd`, { token })).status, 404);
  const moved = join(folder, "old.mp3");
  await rename(join(folder, "1.mp3"), moved);
  await symlink("/etc/passwd", join(folder, "1.mp3"));
  const container = process.env.LEAFWAKE_STREAM_TEST_CONTAINER;
  if (container) {
    // Colima's host-file sharing propagates fixture mutations asynchronously. Observe the image's view first.
    const started = Date.now();
    for (;;) {
      try {
        execFileSync(
          "docker",
          [
            "--host",
            process.env.DOCKER_HOST || "unix:///Users/emanuel/.colima/default/docker.sock",
            "exec",
            container,
            "node",
            "--input-type=module",
            "-e",
            "import {lstat} from 'node:fs/promises';if(!(await lstat(process.argv[1])).isSymbolicLink())process.exit(2)",
            join(folder, "1.mp3"),
          ],
          { stdio: "pipe" },
        );
        break;
      } catch (error) {
        if (Date.now() - started > 5000) throw error;
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }
  }
  assert.equal((await call(url, { token })).status, 404, "changed symlink cannot escape the media mount");
  assert.equal(
    (await call(`/api/session/${session.id}/close`, { method: "POST", token, data: {} })).status,
    200,
  );
  assert.equal((await call(track, { token })).status, 404, "closed session stops serving tracks");
});
