import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const base = process.env.LEAFWAKE_ITEMS_TEST_URL || "http://127.0.0.1:19902";
async function call(path, token, value, method = value === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: value === undefined ? undefined : JSON.stringify(value),
  });
}
async function json(path, token, value, method) {
  const r = await call(path, token, value, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("uploaded media, metadata and cover edits preserve identity and progress while removal retains source bytes", async () => {
  const { user: owner } = await json("/login", "", {
      username: "import-owner",
      password: "synthetic-password-2026",
    }),
    token = owner.accessToken;
  const library = await json("/api/libraries", token, {
    name: `Upload ${randomUUID()}`,
    mediaType: "book",
    folders: [{ fullPath: "/data/media" }],
  });
  const pdf = await readFile(
    "/Users/emanuel/.cache/leafwake/fullstack-media-154/native-journeys/Field Guide to Quiet/Field Guide to Quiet.pdf",
  );
  const response = await fetch(`${base}/api/libraries/${library.id}/upload?filename=Original%20upload.pdf`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/octet-stream" },
    body: pdf,
  });
  assert.equal(response.status, 200, await response.clone().text());
  const { item } = await response.json();
  assert.ok(item.id);
  const reader = await json("/api/users", token, {
    username: `limited-${randomUUID()}`,
    password: "synthetic-password-2026",
    type: "user",
  });
  const { user: limited } = await json("/login", "", {
    username: reader.username,
    password: "synthetic-password-2026",
  });
  assert.equal(
    (
      await call(
        `/api/items/${item.id}/media`,
        limited.accessToken,
        { metadata: { title: "Denied" } },
        "PATCH",
      )
    ).status,
    403,
  );
  await json(`/api/me/progress/${item.id}`, token, { ebookLocation: "page-3", ebookProgress: 0.4 }, "PATCH");
  await json(
    `/api/items/${item.id}/media`,
    token,
    {
      metadata: {
        title: "Edited title",
        description: "Edited description",
        authors: [{ name: "New author" }],
        genres: ["History"],
      },
      tags: ["edited-tag"],
    },
    "PATCH",
  );
  const cover = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0xkAAAAASUVORK5CYII=",
    "base64",
  );
  const savedCover = await fetch(`${base}/api/items/${item.id}/cover`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "image/png" },
    body: cover,
  });
  assert.equal(savedCover.status, 200);
  assert.equal((await call(`/api/items/${item.id}/cover`, limited.accessToken)).status, 200);
  assert.equal(
    (
      await fetch(`${base}/api/items/${item.id}/cover`, { headers: { authorization: `Bearer ${token}` } })
    ).headers.get("content-type"),
    "image/png",
  );
  await json(`/api/libraries/${library.id}/scan`, token, {});
  const edited = await json(`/api/items/${item.id}`, token);
  assert.equal(edited.media.metadata.title, "Edited title");
  assert.equal(edited.media.metadata.authors[0].name, "New author");
  assert.equal(edited.media.ebookFile.ino, item.media.ebookFile.ino);
  assert.equal((await json(`/api/me/progress/${item.id}`, token)).ebookLocation, "page-3");
  assert.equal((await call(`/api/items/${item.id}`, token, { confirmation: "wrong" }, "DELETE")).status, 400);
  assert.equal(
    (await call(`/api/items/${item.id}`, limited.accessToken, { confirmation: "REMOVE" }, "DELETE")).status,
    403,
  );
  const removed = await json(`/api/items/${item.id}`, token, { confirmation: "REMOVE" }, "DELETE");
  assert.equal(removed.mediaDeleted, false);
  assert.equal(removed.historyRetained, true);
  assert.equal((await call(`/api/items/${item.id}`, token)).status, 404);
  await json(`/api/libraries/${library.id}/scan`, token, {});
  assert.equal((await call(`/api/items/${item.id}`, token)).status, 404);
  await json(`/api/items/${item.id}/restore`, token, {});
  assert.equal((await json(`/api/me/progress/${item.id}`, token)).ebookLocation, "page-3");
  const file = await fetch(`${base}/api/items/${item.id}/file/${item.media.ebookFile.ino}`, {
    headers: { authorization: `Bearer ${token}` },
  });
  assert.deepEqual(Buffer.from(await file.arrayBuffer()), pdf);
  console.log(
    JSON.stringify({
      itemId: item.id,
      libraryId: library.id,
      identityAndProgressRetained: true,
      originalBytesRetained: true,
    }),
  );
});
