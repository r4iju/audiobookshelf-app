import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

const base = process.env.LEAFWAKE_ADOPTION_URL || "http://127.0.0.1:29970";
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

test("legacy closed-session adoption retains server identity and adds the pending cumulative total once", async () => {
  const admin = (await json("/login", null, { username: "qa-admin", password: "qa-admin-pass" })).user
    .accessToken;
  const user = await json("/api/users", admin, {
    username: "adoption-" + randomUUID(),
    password: "synthetic-password-2026",
    type: "user",
  });
  const token = (await json("/login", null, { username: user.username, password: "synthetic-password-2026" }))
    .user.accessToken;
  const library = (await json("/api/libraries", token)).libraries.find((x) => x.mediaType === "book");
  const item = (await json(`/api/libraries/${library.id}/items?limit=200`, token)).results.find(
    (x) => x.media.metadata.title === "Salt and Signal",
  );
  const now = Date.now() - 10000;
  const original = {
    id: randomUUID(),
    libraryItemId: item.id,
    currentTime: 10,
    timeListening: 10,
    duration: item.media.duration,
    startedAt: now - 600000,
    updatedAt: now,
  };
  assert.ok((await json("/api/session/local-all", token, { sessions: [original] })).results[0].success);
  const pending = {
    ...original,
    currentTime: 25,
    timeListening: 25,
    startedAt: now - 500000,
    updatedAt: now + 1000,
  };
  const result = await json("/api/session/local-all", token, { sessions: [pending] });
  assert.ok(result.results[0].success, JSON.stringify(result));
  assert.ok((await json("/api/session/local-all", token, { sessions: [pending] })).results[0].success);
  const history = await json(`/api/me/item/listening-sessions/${item.id}`, token);
  assert.equal(history.total, 1);
  assert.equal(history.sessions[0].timeListening, 25);
  assert.equal(history.sessions[0].startedAt, original.startedAt);
  const conflicting = { ...pending, libraryItemId: randomUUID() };
  assert.equal(
    (await json("/api/session/local-all", token, { sessions: [conflicting] })).results[0].success,
    false,
  );
});
test("legacy progress timestamps are accepted while newer positions win", async () => {
  const admin = (await json("/login", null, { username: "qa-admin", password: "qa-admin-pass" })).user
    .accessToken;
  const user = await json("/api/users", admin, {
    username: "legacy-position-" + randomUUID(),
    password: "synthetic-password-2026",
    type: "user",
  });
  const token = (await json("/login", null, { username: user.username, password: "synthetic-password-2026" }))
    .user.accessToken;
  const library = (await json("/api/libraries", token)).libraries.find((x) => x.mediaType === "book");
  const item = (await json(`/api/libraries/${library.id}/items?limit=200`, token)).results.find(
    (x) => x.media.metadata.title === "Salt and Signal",
  );
  const path = `/api/me/progress/${item.id}`,
    now = Date.now();
  const legacy = {
    currentTime: 2,
    duration: item.media.duration,
    progress: 2 / item.media.duration,
    isFinished: false,
    lastUpdate: now - 30000,
    startedAt: now - 86400000,
  };
  const saved = await json(path, token, legacy, "PATCH");
  assert.equal(saved.currentTime, 2);
  assert.equal(saved.startedAt, legacy.startedAt);
  await json(path, token, { currentTime: 3, updatedAt: now }, "PATCH");
  const stale = await json(path, token, { ...legacy, currentTime: 1 }, "PATCH");
  assert.equal(stale.currentTime, 3);
  assert.equal(
    (await call(path, token, { currentTime: 4, lastUpdate: now, updatedAt: now + 1 }, "PATCH")).status,
    400,
  );
  assert.equal((await call(path, token, { ...legacy, lastUpdate: now + 600000 }, "PATCH")).status, 400);
});

test("unfinishing an old server row does not supersede the pending legacy position", async () => {
  const admin = (await json("/login", null, { username: "qa-admin", password: "qa-admin-pass" })).user
    .accessToken;
  const user = await json("/api/users", admin, {
    username: "unfinished-" + randomUUID(),
    password: "synthetic-password-2026",
    type: "user",
  });
  const token = (await json("/login", null, { username: user.username, password: "synthetic-password-2026" }))
    .user.accessToken;
  const library = (await json("/api/libraries", token)).libraries.find((x) => x.mediaType === "book");
  const item = (await json(`/api/libraries/${library.id}/items?limit=200`, token)).results.find(
    (x) => x.media.metadata.title === "Salt and Signal",
  );
  const path = `/api/me/progress/${item.id}`,
    localTime = Date.now() - 30000;
  await json(
    path,
    token,
    { isFinished: true, lastUpdate: localTime - 1000, startedAt: localTime - 86400000 },
    "PATCH",
  );
  await json(path, token, { isFinished: false, lastUpdate: localTime - 1 }, "PATCH");
  const preliminary = await json(path, token);
  assert.ok(
    preliminary.lastUpdate < localTime,
    "preliminary unfinish must remain older than the pending position on retry",
  );
  assert.equal(preliminary.isFinished, false);
  const pending = {
    currentTime: 2,
    isFinished: false,
    lastUpdate: localTime,
    startedAt: localTime - 86400000,
  };
  const saved = await json(path, token, pending, "PATCH");
  assert.equal(saved.currentTime, 2);
  assert.equal(saved.lastUpdate, localTime);
  await json(path, token, { currentTime: 3, updatedAt: Date.now() }, "PATCH");
  assert.equal((await json(path, token, pending, "PATCH")).currentTime, 3);
});

test("legacy finish dates remain ordered and unfinished progress has no completion date", async () => {
  const admin = (await json("/login", null, { username: "qa-admin", password: "qa-admin-pass" })).user
    .accessToken;
  const user = await json("/api/users", admin, {
    username: "finish-time-" + randomUUID(),
    password: "synthetic-password-2026",
    type: "user",
  });
  const token = (await json("/login", null, { username: user.username, password: "synthetic-password-2026" }))
    .user.accessToken;
  const library = (await json("/api/libraries", token)).libraries.find((x) => x.mediaType === "book");
  const item = (await json(`/api/libraries/${library.id}/items?limit=200`, token)).results.find(
    (x) => x.media.metadata.title === "Salt and Signal",
  );
  const path = `/api/me/progress/${item.id}`,
    stamp = Date.now() - 30000,
    start = stamp - 10000;
  await json(path, token, { currentTime: 2, startedAt: start, lastUpdate: stamp - 10 }, "PATCH");
  const unfinished = await json(path, token, { finishedAt: stamp - 5, lastUpdate: stamp - 5 }, "PATCH");
  assert.equal(unfinished.finishedAt, null);
  assert.equal(
    (await call(path, token, { isFinished: true, finishedAt: start - 1, lastUpdate: stamp }, "PATCH")).status,
    400,
  );
  assert.equal(
    (await call(path, token, { isFinished: true, finishedAt: stamp + 1, lastUpdate: stamp }, "PATCH")).status,
    400,
  );
  const finished = await json(path, token, { isFinished: true, lastUpdate: stamp }, "PATCH");
  assert.equal(finished.finishedAt, stamp);
  assert.equal((await call(path, token, { startedAt: Date.now() + 600000 }, "PATCH")).status, 400);
});
