import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import test from "node:test";

const base = process.env.LEAFWAKE_PROGRESS_TEST_URL || "http://127.0.0.1:19892";
const statePath = process.env.LEAFWAKE_PROGRESS_TEST_STATE || "/tmp/leafwake-progress-state.json";
const itemId = process.env.LEAFWAKE_PROGRESS_TEST_ITEM || "a4d52e4c-869b-409b-8f2c-8c9c664775fb";
if (!process.env.LEAFWAKE_PROGRESS_TEST_PHASE)
  test("reset without progress fences unseen offline writes and retry increments once", async () => {
    const owner = await login("installation-owner");
    const username = `empty-reset-${Date.now()}`;
    await call("/api/users", owner, { username, password: "synthetic-password-2026", type: "user" });
    const token = await login(username);
    const resetId = randomUUID();
    const first = await call(`/api/me/progress/${itemId}/reset`, token, { resetId });
    assert.equal(first.status, 200);
    assert.equal((await first.json()).progressGeneration, 1);
    assert.equal(
      (await (await call(`/api/me/progress/${itemId}/reset`, token, { resetId })).json()).progressGeneration,
      1,
    );
    const now = Date.now() - 1000;
    const report = {
      id: randomUUID(),
      libraryItemId: itemId,
      duration: 60,
      currentTime: 10,
      timeListening: 10,
      startedAt: now,
      updatedAt: now,
    };
    const answer = await call("/api/session/local-all", token, { sessions: [report] });
    assert.equal((await answer.json()).results[0].progressSynced, false);
    assert.equal((await call(`/api/me/progress/${itemId}`, token)).status, 404);
    await call("/api/session/local-all", token, {
      sessions: [{ ...report, id: randomUUID(), progressGeneration: 1 }],
    });
    assert.equal((await (await call(`/api/me/progress/${itemId}`, token)).json()).currentTime, 10);
  });
if (!process.env.LEAFWAKE_PROGRESS_TEST_PHASE)
  test("manual ownership and session revisions order equal clocks and clock rollback", async () => {
    const owner = await login("installation-owner");
    const username = `revision-${Date.now()}`;
    await call("/api/users", owner, { username, password: "synthetic-password-2026", type: "user" });
    const token = await login(username);
    const now = Date.now() - 10000;
    const report = {
      id: randomUUID(),
      libraryItemId: itemId,
      duration: 60,
      startTime: 0,
      currentTime: 10,
      timeListening: 10,
      startedAt: now,
      updatedAt: now + 2000,
      revision: 1,
    };
    const publish = (value) => call("/api/session/local-all", token, { sessions: [value] });
    await publish(report);
    await publish({ ...report, revision: 2, currentTime: 20, timeListening: 20, updatedAt: now + 1000 });
    assert.equal(
      (await (await call(`/api/me/progress/${itemId}`, token)).json()).currentTime,
      20,
      "revision survives a clock rollback",
    );
    await call(`/api/me/progress/${itemId}`, token, { currentTime: 25, updatedAt: now + 2000 }, "PATCH");
    await publish({ ...report, revision: 3, currentTime: 5, timeListening: 21 });
    assert.equal(
      (await (await call(`/api/me/progress/${itemId}`, token)).json()).currentTime,
      25,
      "manual intent owns equal-time arbitration",
    );
  });
if (!process.env.LEAFWAKE_PROGRESS_TEST_PHASE)
  test("a delayed patch cannot supersede a later listening position", async () => {
    const owner = await login("installation-owner");
    const username = `patch-order-${Date.now()}`;
    await call("/api/users", owner, { username, password: "synthetic-password-2026", type: "user" });
    const token = await login(username);
    const now = Date.now() - 10000;
    await call(`/api/me/progress/${itemId}`, token, { currentTime: 5, updatedAt: now }, "PATCH");
    await call("/api/session/local-all", token, {
      sessions: [
        {
          id: randomUUID(),
          libraryItemId: itemId,
          duration: 60,
          startTime: 5,
          currentTime: 30,
          timeListening: 25,
          startedAt: now,
          updatedAt: now + 2000,
        },
      ],
    });
    await call(`/api/me/progress/${itemId}`, token, { currentTime: 10, updatedAt: now + 1000 }, "PATCH");
    const response = await call(`/api/me/progress/${itemId}`, token);
    assert.equal((await response.json()).currentTime, 30);
  });
async function call(path, token, data, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(data === undefined ? {} : { "content-type": "application/json" }),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
    signal: AbortSignal.timeout(15000),
  });
}
async function login(username) {
  const response = await call("/login", null, { username, password: "synthetic-password-2026" });
  assert.equal(response.status, 200);
  return (await response.json()).user.accessToken;
}
if (process.env.LEAFWAKE_PROGRESS_TEST_PHASE === "restart") {
  test("listening history, finish flags and reader places survive image restart", async () => {
    const saved = JSON.parse(await readFile(statePath, "utf8"));
    const token = await login(saved.username);
    const progress = await (await call(`/api/me/progress/${itemId}`, token)).json();
    assert.equal(progress.id, saved.progressId);
    assert.equal(progress.isFinished, true);
    assert.equal(progress.ebookLocation, "chapter-2");
    assert.equal((await (await call("/api/me/listening-stats", token)).json()).totalTime, saved.total);
  });
} else
  test("cumulative listening is idempotent and ordered, first completion finishes, reset prevents resurrection", async () => {
    const owner = await login("installation-owner");
    const username = `progress-${Date.now()}`;
    assert.equal(
      (await call("/api/users", owner, { username, password: "synthetic-password-2026", type: "user" }))
        .status,
      200,
    );
    const token = await login(username);
    const item = await (await call(`/api/items/${itemId}`, token)).json();
    const duration = item.media.duration;
    const now = Date.now() - 10000;
    const report = {
      id: randomUUID(),
      libraryItemId: itemId,
      episodeId: null,
      mediaType: "book",
      duration,
      startTime: 0,
      currentTime: duration,
      timeListening: duration,
      startedAt: now,
      updatedAt: now + 1000,
      playMethod: 3,
      mediaPlayer: "exo-player",
    };
    const publish = async (reports) => {
      const response = await call("/api/session/local-all", token, {
        sessions: reports,
        deviceInfo: { deviceId: "progress-qa" },
      });
      assert.equal(response.status, 200, "replacement accepts durable cumulative reports");
      return (await response.json()).results;
    };
    assert.equal((await publish([report]))[0].success, true);
    const progress = async () => call(`/api/me/progress/${itemId}`, token);
    let record = await (await progress()).json();
    assert.equal(record.isFinished, true, "first offline completion creates finished progress");
    assert.equal(record.currentTime, duration);
    await publish([report, report]);
    const stats = async () => (await (await call("/api/me/listening-stats", token)).json()).totalTime;
    assert.equal(await stats(), duration, "duplicate absolute reports never inflate listening");
    await publish([{ ...report, timeListening: duration + 1 }]);
    assert.equal(
      await stats(),
      duration + 1,
      "equal-time revisions retain a larger absolute listening total",
    );
    await publish([{ ...report, currentTime: 1, timeListening: 1, updatedAt: now }]);
    assert.equal((await (await progress()).json()).currentTime, duration);
    assert.equal(await stats(), duration + 1);
    const competing = {
      ...report,
      id: randomUUID(),
      currentTime: 15,
      timeListening: 5,
      updatedAt: now + 3000,
    };
    await publish([competing]);
    await publish([{ ...report, currentTime: 7, timeListening: duration + 2, updatedAt: now + 2000 }]);
    assert.equal(
      (await (await progress()).json()).currentTime,
      15,
      "older device progress cannot rewind a newer device",
    );
    assert.equal(await stats(), duration + 7);
    record = await (await progress()).json();
    assert.equal((await call(`/api/me/progress/${record.id}`, token, undefined, "DELETE")).status, 200);
    await publish([{ ...report, updatedAt: Date.now(), currentTime: 30, timeListening: duration + 3 }]);
    assert.equal((await progress()).status, 404, "pre-reset sessions cannot resurrect discarded progress");
    const resetItem = await (await call(`/api/items/${itemId}`, token)).json();
    assert.equal(
      resetItem.progressGeneration,
      1,
      "reset exposes a durable generation for new playback and reader intents",
    );
    const stalePatch = await call(
      `/api/me/progress/${itemId}`,
      token,
      { ebookLocation: "old-place", updatedAt: now },
      "PATCH",
    );
    assert.equal(
      stalePatch.status,
      409,
      "a fenced-out reader intent remains recoverable instead of recreating progress",
    );
    assert.equal((await progress()).status, 404);
    const future = {
      ...report,
      id: randomUUID(),
      startedAt: Date.now() + 240000,
      updatedAt: Date.now() + 240000,
    };
    assert.equal(
      (await publish([future]))[0].progressSynced,
      false,
      "future device times cannot bypass a reset fence",
    );
    assert.equal((await progress()).status, 404);
    await new Promise((resolve) => setTimeout(resolve, 5));
    const after = {
      ...report,
      id: randomUUID(),
      startedAt: Date.now(),
      updatedAt: Date.now(),
      currentTime: 10,
      timeListening: 2,
      progressGeneration: resetItem.progressGeneration,
    };
    await publish([after]);
    const newRecord = await (await progress()).json();
    assert.notEqual(newRecord.id, record.id);
    assert.equal((await call(`/api/me/progress/${record.id}`, token, undefined, "DELETE")).status, 200);
    assert.equal(
      (await (await progress()).json()).id,
      newRecord.id,
      "retrying an old delete leaves new progress intact",
    );
    assert.equal(
      (
        await call(
          `/api/me/progress/${itemId}`,
          token,
          {
            ebookLocation: "chapter-2",
            ebookProgress: 0.4,
            updatedAt: Date.now(),
            progressGeneration: resetItem.progressGeneration,
          },
          "PATCH",
        )
      ).status,
      200,
    );
    assert.equal(
      (
        await call(
          `/api/me/progress/${itemId}`,
          token,
          { isFinished: true, updatedAt: Date.now(), progressGeneration: resetItem.progressGeneration },
          "PATCH",
        )
      ).status,
      200,
    );
    const finished = await (await progress()).json();
    assert.equal(finished.isFinished, true);
    assert.equal(finished.ebookLocation, "chapter-2");
    const me = await (await call("/api/me", token)).json();
    assert.ok(me.mediaProgress.some((entry) => entry.id === finished.id));
    const playback = await (await call(`/api/items/${itemId}/play`, token, { forceDirectPlay: true })).json();
    assert.equal(playback.currentTime, duration, "opening playback restores the persisted position");
    await writeFile(statePath, JSON.stringify({ username, progressId: finished.id, total: await stats() }), {
      mode: 0o600,
    });
  });
