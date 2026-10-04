import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";

const base = process.env.LEAFWAKE_STATS_TEST_URL || "http://127.0.0.1:19902";
async function call(path, token, body, method = body === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
async function json(path, token, body, method) {
  const r = await call(path, token, body, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("personal and server year summaries partition UTC boundaries and deduplicate numeric cumulative reports", async () => {
  const { user: owner } = await json("/login", "", {
      username: "import-owner",
      password: "synthetic-password-2026",
    }),
    token = owner.accessToken;
  const username = `stats-${randomUUID()}`;
  await json("/api/users", token, { username, password: "synthetic-password-2026", type: "user" });
  const { user } = await json("/login", "", { username, password: "synthetic-password-2026" }),
    reader = user.accessToken;
  const empty = await json("/api/me/stats/year/2024", reader);
  assert.equal(empty.totalListeningTime, 0);
  const libraries = (await json("/api/libraries", reader)).libraries;
  let item;
  for (const library of libraries) {
    const books = (await json(`/api/libraries/${library.id}/items?limit=200`, reader)).results;
    item = books.find((b) => b.media.metadata.title === "Salt and Signal" && b.media.duration >= 50);
    if (item) break;
  }
  assert.ok(item);
  const id = randomUUID(),
    startedAt = Date.parse("2024-12-31T23:59:40Z");
  const report = {
    id,
    libraryItemId: item.id,
    duration: "60",
    currentTime: "40",
    timeListening: "40",
    startedAt,
    updatedAt: Date.parse("2025-01-01T00:00:20Z"),
    revision: 1,
  };
  const accepted = await json("/api/session/local-all", reader, { sessions: [report] });
  assert.equal(accepted.results[0].success, true);
  await json("/api/session/local-all", reader, { sessions: [report] });
  const oldYear = await json("/api/me/stats/year/2024", reader),
    newYear = await json("/api/me/stats/year/2025", reader);
  assert.equal(oldYear.totalListeningTime, 20);
  assert.equal(newYear.totalListeningTime, 20);
  assert.equal(oldYear.totalListeningSessions, 1);
  assert.equal(newYear.numBooksListened, 1);
  const updated = {
    ...report,
    revision: 2,
    updatedAt: Date.parse("2025-01-01T00:00:30Z"),
    currentTime: 50,
    timeListening: 50,
  };
  await json("/api/session/local-all", reader, { sessions: [updated] });
  await json("/api/session/local-all", reader, { sessions: [report] });
  const after = await json("/api/me/stats/year/2025", reader);
  assert.equal(after.totalListeningTime, 30);
  assert.equal((await json("/api/me/listening-stats", reader)).totalTime, 50);
  assert.equal((await call("/api/stats/year/2025", reader)).status, 403);
  assert.equal((await call("/api/me/stats/year/invalid", reader)).status, 400);
  const server = await json("/api/stats/year/2025", token);
  assert.ok(server.totalListeningTime >= 30);
  assert.equal(typeof server.totalBooksSize, "number");
  assert.equal(server.users, undefined);
  const recent = await json("/api/me/listening-sessions?limit=1&page=0", reader);
  assert.equal(recent.total, 1);
  assert.equal(recent.sessions[0].id, id);
  assert.equal(recent.sessions[0].timeListening, 50);
  console.log(
    JSON.stringify({
      username,
      itemId: item.id,
      sessionId: id,
      oldYearTime: 20,
      newYearTime: 30,
      totalTime: 50,
    }),
  );
});
