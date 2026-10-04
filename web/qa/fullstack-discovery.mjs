import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { copyFile, mkdir, writeFile } from "node:fs/promises";
import test from "node:test";

const base = process.env.LEAFWAKE_DISCOVERY_TEST_URL || "http://127.0.0.1:19902";
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
test("permission-filtered author/series discovery, collapsed pages and committed personalized shelves", async () => {
  const key = randomUUID(),
    root = `/Users/emanuel/.cache/leafwake/fullstack-media-154/discovery-${key}`;
  await mkdir(root, { recursive: true });
  const audio = `/tmp/leafwake-discovery-${key}.wav`;
  execFileSync("ffmpeg", [
    "-v",
    "error",
    "-f",
    "lavfi",
    "-i",
    "sine=frequency=440:duration=1",
    "-c:a",
    "pcm_s16le",
    audio,
  ]);
  for (let index = 0; index < 40; index++) {
    const name = `Book ${String(index).padStart(2, "0")}`;
    await mkdir(`${root}/${name}`, { recursive: true });
    await copyFile(audio, `${root}/${name}/01.wav`);
    await writeFile(
      `${root}/${name}/metadata.json`,
      JSON.stringify({
        title: name,
        authors: [index === 39 ? "Secret author" : "Shared author"],
        series:
          index < 24
            ? [{ name: index < 12 ? "Cycle A" : "Cycle B", sequence: String((index % 12) + 1) }]
            : [],
        tags: [index === 39 ? "private" : "public"],
        publishedYear: String(2000 + index),
        language: "en",
        publisher: "Synthetic publisher",
      }),
    );
  }
  const owner = (
    await json("/login", null, { username: "import-owner", password: "synthetic-password-2026" })
  ).user;
  const library = await json("/api/libraries", owner.accessToken, {
    name: `Discovery ${key}`,
    folders: [{ fullPath: root }],
  });
  await json(`/api/libraries/${library.id}/scan`, owner.accessToken, {});
  const authors = await json(`/api/libraries/${library.id}/authors`, owner.accessToken);
  assert.equal(authors.authors.length, 2);
  const shared = authors.authors.find((a) => a.name === "Shared author");
  assert.equal(shared.numBooks, 39);
  const series = await json(`/api/libraries/${library.id}/series?limit=10000&sort=name`, owner.accessToken);
  assert.equal(series.total, 2);
  assert.equal(series.results[0].books.length, 12);
  const group = await json(
    `/api/libraries/${library.id}/series/${series.results[0].id}?include=progress`,
    owner.accessToken,
  );
  assert.deepEqual(
    group.books.map((b) => b.media.metadata.title),
    Array.from({ length: 12 }, (_, i) => `Book ${String(i).padStart(2, "0")}`),
  );
  const detail = await json(
    `/api/authors/${shared.id}?include=items,series&library=${library.id}`,
    owner.accessToken,
  );
  assert.equal(detail.libraryItems.length, 39);
  assert.equal(detail.series.length, 2);
  const first = await json(
      `/api/libraries/${library.id}/items?limit=7&page=0&sort=media.metadata.title`,
      owner.accessToken,
    ),
    second = await json(
      `/api/libraries/${library.id}/items?limit=7&page=1&sort=media.metadata.title`,
      owner.accessToken,
    );
  assert.equal(first.total, 40);
  assert.equal(new Set([...first.results, ...second.results].map((i) => i.id)).size, 14);
  const collapsed = await json(
    `/api/libraries/${library.id}/items?collapseseries=1&limit=200&sort=media.metadata.title`,
    owner.accessToken,
  );
  assert.equal(collapsed.total, 18);
  assert.equal(collapsed.results.filter((i) => i.collapsedSeries).length, 2);
  assert.equal(
    collapsed.results.find((i) => i.collapsedSeries?.id === group.id).collapsedSeries.numBooks,
    12,
  );
  const book = first.results[0];
  await json(
    `/api/me/progress/${book.id}`,
    owner.accessToken,
    { currentTime: 0.5, updatedAt: Date.now() },
    "PATCH",
  );
  let shelves = await json(`/api/libraries/${library.id}/personalized?limit=12`, owner.accessToken);
  assert.ok(shelves.find((s) => s.id === "continue-listening").entities.some((i) => i.id === book.id));
  await json(
    `/api/me/progress/${book.id}`,
    owner.accessToken,
    { isFinished: true, updatedAt: Date.now() + 1 },
    "PATCH",
  );
  shelves = await json(`/api/libraries/${library.id}/personalized?limit=12`, owner.accessToken);
  assert.ok(!shelves.find((s) => s.id === "continue-listening").entities.some((i) => i.id === book.id));
  assert.ok(shelves.find((s) => s.id === "recently-finished").entities.some((i) => i.id === book.id));
  await json(`/api/libraries/${library.id}/scan`, owner.accessToken, {});
  assert.equal(
    (await json(`/api/libraries/${library.id}/authors`, owner.accessToken)).authors.find(
      (a) => a.name === "Shared author",
    ).id,
    shared.id,
  );
  assert.equal(
    (await json(`/api/libraries/${library.id}/series?limit=10000`, owner.accessToken)).results.find(
      (s) => s.name === "Cycle A",
    ).id,
    group.id,
  );
  const account = await json("/api/users", owner.accessToken, {
    username: `discovery-${key}`,
    password: "synthetic-password-2026",
    type: "user",
    permissions: { accessAllTags: false },
    itemTagsSelected: ["public"],
  });
  const reader = (
    await json("/login", null, { username: account.username, password: "synthetic-password-2026" })
  ).user;
  assert.equal((await json(`/api/libraries/${library.id}/authors`, reader.accessToken)).authors.length, 1);
  const secret = authors.authors.find((a) => a.name === "Secret author");
  assert.equal((await call(`/api/authors/${secret.id}`, reader.accessToken)).status, 404);
  const search = await json(`/api/libraries/${library.id}/search?q=Secret`, reader.accessToken);
  assert.equal(search.authors.length, 0);
  assert.equal(search.book.length, 0);
  console.log(
    "Discovery fixture library",
    library.id,
    "author",
    shared.id,
    "series",
    group.id,
    "book",
    book.id,
  );
});
