import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { copyFile, mkdir, writeFile } from "node:fs/promises";
import test from "node:test";

const base = process.env.LEAFWAKE_SEARCH_TEST_URL || "http://127.0.0.1:19892";
const root = "/Users/emanuel/.cache/leafwake/fullstack-media-154";
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
async function login(username) {
  const response = await call("/login", null, { username, password: "synthetic-password-2026" });
  assert.equal(response.status, 200);
  return (await response.json()).user.accessToken;
}
test("search returns only authorized media and denies an inaccessible library without metadata", async () => {
  const owner = await login("installation-owner");
  const key = randomUUID();
  const directory = `${root}/search-${key}`;
  for (const [title, explicit, tags] of [
    ["public", false, ["safe"]],
    ["explicit", true, ["safe"]],
    ["tagged", false, ["secret"]],
  ]) {
    const path = `${directory}/${title}`;
    await mkdir(path, { recursive: true });
    await copyFile(`${root}/native-playback/1.mp3`, `${path}/chapter.mp3`);
    await writeFile(
      `${path}/metadata.json`,
      JSON.stringify({ title: `Needle ${key} ${title}`, explicit, tags, authors: ["Search author"] }),
    );
  }
  const library = await (
    await call("/api/libraries", owner, {
      name: `Search ${key}`,
      mediaType: "book",
      folders: [{ fullPath: directory }],
    })
  ).json();
  assert.ok(library.id);
  assert.equal((await call(`/api/libraries/${library.id}/scan`, owner, {})).status, 200);
  const search = `/api/libraries/${library.id}/search?q=${encodeURIComponent(`Needle ${key}`)}&limit=10`;
  const response = await call(search, owner);
  assert.equal(response.status, 200, "consumed search contract exists");
  assert.equal((await response.json()).book.length, 3);
  assert.equal(
    (await call(search.replace("limit=10", "limit=513"), owner)).status,
    200,
    "More remains within the consumed contract",
  );
  const username = `search-${key}`;
  await call("/api/users", owner, {
    username,
    password: "synthetic-password-2026",
    type: "user",
    permissions: { accessExplicitContent: false, accessAllTags: false },
    itemTagsSelected: ["safe"],
  });
  const token = await login(username);
  const allowed = await (await call(search, token)).json();
  assert.equal(allowed.book.length, 1);
  assert.match(allowed.book[0].libraryItem.media.metadata.title, /public$/);
  assert.equal(JSON.stringify(allowed).includes("secret"), false);
  const deniedUsername = `denied-${key}`;
  await call("/api/users", owner, {
    username: deniedUsername,
    password: "synthetic-password-2026",
    type: "user",
    permissions: { accessAllLibraries: false },
    librariesAccessible: [],
  });
  const denied = await call(search, await login(deniedUsername));
  assert.equal(denied.status, 404);
  assert.equal((await denied.text()).includes("Needle"), false);
});
