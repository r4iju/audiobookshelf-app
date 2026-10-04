import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

const base = process.env.LEAFWAKE_ITEM_HISTORY_URL || "http://127.0.0.1:29970";
async function call(path, token, data, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: "Bearer " + token } : {}) },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, token, data, method) {
  const response = await call(path, token, data, method);
  assert.ok(response.ok, `${path}: ${response.status}`);
  return response.json();
}
test("original item history preserves measured listening, filters before pagination and applies current account policy", async () => {
  const admin = (await json("/login", null, { username: "qa-admin", password: "qa-admin-pass" })).user
    .accessToken;
  const user = await json("/api/users", admin, {
    username: "history-" + randomUUID(),
    password: "synthetic-password-2026",
    type: "user",
  });
  const token = (await json("/login", null, { username: user.username, password: "synthetic-password-2026" }))
    .user.accessToken;
  const libraries = (await json("/api/libraries", token)).libraries;
  const library = libraries.find((x) => x.mediaType === "book");
  const items = (await json(`/api/libraries/${library.id}/items?limit=200`, token)).results;
  const first = items.find((x) => x.media.metadata.title === "The Long Tide"),
    second = items.find((x) => x.media.metadata.title === "Salt and Signal");
  const path = `/api/me/item/${first.id}/listening-sessions`;
  const empty = await json(path + "?itemsPerPage=1&page=0", token);
  assert.equal(empty.total, 0);
  assert.deepEqual(empty.sessions, []);
  const now = Date.now() - 10000;
  const make = (item, time, listened) => ({
    id: randomUUID(),
    libraryItemId: item.id,
    currentTime: time,
    timeListening: listened,
    duration: item.media.duration,
    startedAt: now,
    updatedAt: now + time * 100,
  });
  const earlier = make(first, 10, 3),
    other = make(second, 12, 7),
    later = make(first, 14, 5);
  const synced = await json("/api/session/local-all", token, { sessions: [earlier, other, later] });
  assert.ok(synced.results.every((x) => x.success));
  const page0 = await json(path + "?itemsPerPage=1&page=0", token),
    page1 = await json(path + "?itemsPerPage=1&page=1", token);
  assert.equal(page0.total, 2);
  assert.equal(page0.itemsPerPage, 1);
  assert.equal(page0.numPages, 2);
  assert.equal(page0.page, 0);
  assert.equal(page0.sessions[0].id, later.id);
  assert.equal(page0.sessions[0].timeListening, 5);
  assert.equal(page1.sessions[0].id, earlier.id);
  assert.ok(page0.sessions.every((x) => x.libraryItemId === first.id));
  assert.equal((await json(path + "?limit=1&page=2", token)).sessions.length, 0);
  assert.equal((await call(path + "?itemsPerPage=100001", token)).status, 400);
  assert.equal((await call(path, null)).status, 401);
  assert.equal((await call("/api/me/item/" + randomUUID() + "/listening-sessions", token)).status, 404);
  await json(
    "/api/users/" + user.id,
    admin,
    { permissions: { accessAllLibraries: false }, librariesAccessible: [] },
    "PATCH",
  );
  assert.equal((await call(path, token)).status, 401);
  const restricted = (
    await json("/login", null, { username: user.username, password: "synthetic-password-2026" })
  ).user.accessToken;
  assert.equal((await call(path, restricted)).status, 404);
});

test("native adoption route pages only the selected account and episode", async () => {
  const admin = (await json("/login", null, { username: "qa-admin", password: "qa-admin-pass" })).user
    .accessToken;
  const create = async () => {
    const user = await json("/api/users", admin, {
      username: "native-history-" + randomUUID(),
      password: "synthetic-password-2026",
      type: "user",
    });
    return (await json("/login", null, { username: user.username, password: "synthetic-password-2026" })).user
      .accessToken;
  };
  const token = await create(),
    otherToken = await create();
  const libraries = (await json("/api/libraries", token)).libraries;
  const library = libraries.find((x) => x.mediaType === "podcast");
  const item = (await json(`/api/libraries/${library.id}/items?limit=200`, token)).results[0];
  const expanded = await json(`/api/items/${item.id}?expanded=1`, token);
  const episodes = expanded.media.episodes;
  assert.ok(episodes.length >= 2);
  const path = `/api/me/item/listening-sessions/${item.id}`;
  const now = Date.now() - 10000;
  const make = (episode, time, listened) => ({
    id: randomUUID(),
    libraryItemId: item.id,
    episodeId: episode.id,
    currentTime: time,
    timeListening: listened,
    duration: episode.duration || episode.audioFile?.duration || 60,
    startedAt: now,
    updatedAt: now + time * 100,
  });
  const earlier = make(episodes[0], 10, 3),
    otherEpisode = make(episodes[1], 16, 7),
    later = make(episodes[0], 14, 5),
    otherAccount = make(episodes[0], 18, 11);
  assert.ok(
    (await json("/api/session/local-all", token, { sessions: [earlier, otherEpisode, later] })).results.every(
      (x) => x.success,
    ),
  );
  assert.ok(
    (await json("/api/session/local-all", otherToken, { sessions: [otherAccount] })).results.every(
      (x) => x.success,
    ),
  );
  const all = await json(path + "?itemsPerPage=1&page=0", token);
  assert.equal(all.total, 3);
  assert.equal(all.numPages, 3);
  const selected = path + "/" + episodes[0].id;
  const page0 = await json(selected + "?itemsPerPage=1&page=0", token),
    page1 = await json(selected + "?itemsPerPage=1&page=1", token);
  assert.equal(page0.total, 2);
  assert.equal(page0.numPages, 2);
  assert.equal(page0.sessions[0].id, later.id);
  assert.equal(page0.sessions[0].timeListening, 5);
  assert.equal(page1.sessions[0].id, earlier.id);
  assert.equal((await json(selected + "?itemsPerPage=1&page=2", token)).sessions.length, 0);
  const own = await json(selected, otherToken);
  assert.equal(own.total, 1);
  assert.equal(own.sessions[0].id, otherAccount.id);
  assert.equal((await json(path + "/" + randomUUID(), token)).total, 0);
  assert.equal((await call(selected, null)).status, 401);
});
