import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { chmod, readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { hashSync } from "bcryptjs";
import { completeSource } from "./complete-source.mjs";

const base = process.env.LEAFWAKE_HISTORICAL_IMPORT_URL || "http://127.0.0.1:19937";
async function call(path, data, token, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, data, token, method) {
  const response = await call(path, data, token, method);
  assert.ok(response.ok, `${path}: ${response.status} ${await response.clone().text()}`);
  return response.json();
}
test("read-only migration retains missing file identity and deleted-item history without exposing playable tombstones or inventing listening time", async () => {
  const fixture = await completeSource();
  await chmod(fixture.filename, 0o600);
  const source = new DatabaseSync(fixture.filename);
  source
    .prepare("UPDATE users SET pash=? WHERE id=?")
    .run(hashSync("synthetic-password-2026", 8), fixture.ids.user);
  const missingItem = randomUUID(),
    missingBook = randomUUID(),
    deletedItem = randomUUID(),
    deletedBook = randomUUID(),
    measured = randomUUID(),
    unknown = randomUUID();
  const date = "2025-01-01T00:00:00.000Z",
    updated = "2025-01-02T00:00:00.000Z";
  const missing = {
    metadata: {
      filename: "missing.mp3",
      ext: ".mp3",
      path: "/old/synthetic/books/Missing/missing.mp3",
      relPath: "missing.mp3",
      size: null,
    },
    fileType: "audio",
    isSupplementary: null,
  };
  source
    .prepare(
      "INSERT INTO books(id,title,duration,audioFiles,ebookFile,chapters,tags,genres,narrators,explicit) VALUES(?,?,?,?,?,?,?,?,?,0)",
    )
    .run(missingBook, "Missing synthetic", 0, "[]", null, "[]", "[]", "[]", "[]");
  source
    .prepare("INSERT INTO libraryItems VALUES(?,?,?,?,?,?,0,1,0,?,?,?)")
    .run(
      missingItem,
      fixture.ids.library,
      fixture.ids.folder,
      missingBook,
      "book",
      "/old/synthetic/books/Missing",
      JSON.stringify([missing]),
      date,
      updated,
    );
  for (const [session, time] of [
    [measured, 12],
    [unknown, null],
  ])
    source
      .prepare(
        "INSERT INTO playbackSessions(id,userId,libraryId,mediaItemId,mediaItemType,duration,currentTime,timeListening,startTime,extraData,mediaMetadata,createdAt,updatedAt) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
      )
      .run(
        session,
        fixture.ids.user,
        fixture.ids.library,
        deletedBook,
        "book",
        60,
        20,
        time,
        0,
        JSON.stringify({ libraryItemId: deletedItem }),
        JSON.stringify({
          title: "Deleted synthetic",
          explicit: session === unknown,
          narrators: [],
          genres: [],
        }),
        date,
        updated,
      );
  source.close();
  await chmod(fixture.filename, 0o444);
  const digest = createHash("sha256")
    .update(await readFile(fixture.filename))
    .digest("hex");
  const setup = { setupKey: "synthetic-history-import-2026", sourcePath: fixture.sourcePath };
  await json("/api/setup/import", { ...setup, expectedDigest: digest });
  const login = async (username) =>
    (await json("/login", { username, password: "synthetic-password-2026" })).user;
  const owner = await login("import-owner"),
    token = owner.accessToken;
  const input = {
    sourcePath: fixture.sourcePath,
    mappings: [
      { from: "/old/synthetic/books", to: fixture.mediaRoot },
      { from: "/old/synthetic/podcasts", to: fixture.podcastRoot },
    ],
  };
  const report = await json("/api/admin/migrations/media/inspect", input, token);
  assert.equal(
    report.canImport,
    true,
    "missing inode/size, deleted history and null measurement must have explicit supported mappings",
  );
  assert.equal(report.counts.listeningSeconds, 59);
  await json("/api/admin/migrations/media", { ...input, expectedDigest: digest }, token);
  const item = await json(`/api/items/${missingItem}`, undefined, token);
  assert.equal(item.isMissing, true);
  assert.equal(item.libraryFiles[0].metadata.size, null);
  assert.ok(item.libraryFiles[0].ino);
  assert.equal((await call(`/api/items/${missingItem}/play`, {}, token)).status, 404);
  assert.equal((await call(`/api/items/${deletedItem}`, undefined, token)).status, 404);
  assert.equal((await call(`/api/items/${deletedItem}/restore`, {}, token)).status, 409);
  const user = await login("import-user");
  const stats = await json("/api/me/listening-stats", undefined, user.accessToken);
  assert.equal(stats.totalTime, 59);
  const archived = stats.recentSessions.filter((s) => s.libraryItemId === deletedItem);
  assert.equal(archived.length, 2);
  assert.ok(
    archived.some((s) => s.id === unknown && s.timeListening === 0 && s.timeListeningUnavailable === true),
  );
  assert.ok(archived.some((s) => s.id === measured && s.timeListening === 12));
  assert.ok(
    !JSON.stringify(await json("/api/me/listening-stats", undefined, token)).includes("Deleted synthetic"),
  );
  const listed = await json(
    `/api/libraries/${fixture.ids.library}/items?limit=100`,
    undefined,
    user.accessToken,
  );
  assert.ok(!listed.results.some((i) => i.id === deletedItem));
  await json(`/api/users/${user.id}`, { permissions: { accessExplicitContent: false } }, token, "PATCH");
  assert.ok(
    !JSON.stringify(
      await json("/api/me/listening-stats", undefined, (await login("import-user")).accessToken),
    ).includes("Deleted synthetic"),
    "deleted source item has no authoritative explicit-content policy",
  );
  await json(
    `/api/users/${user.id}`,
    { permissions: { accessAllTags: false, accessExplicitContent: true }, itemTagsSelected: ["safe"] },
    token,
    "PATCH",
  );
  const limited = await login("import-user");
  assert.ok(
    !JSON.stringify(await json("/api/me/listening-stats", undefined, limited.accessToken)).includes(
      "Deleted synthetic",
    ),
    "unknown historical tags must fail closed under tag restrictions",
  );
  assert.equal(
    createHash("sha256")
      .update(await readFile(fixture.filename))
      .digest("hex"),
    digest,
  );
});

test("orphan book sessions cannot migrate into a podcast library", async () => {
  const fixture = await completeSource();
  await chmod(fixture.filename, 0o600);
  const source = new DatabaseSync(fixture.filename);
  const session = randomUUID(),
    deletedBook = randomUUID(),
    deletedItem = randomUUID();
  source
    .prepare(
      "UPDATE playbackSessions SET id=?,mediaItemId=?,libraryId=(SELECT id FROM libraries WHERE mediaType='podcast' LIMIT 1),extraData=? WHERE id=?",
    )
    .run(session, deletedBook, JSON.stringify({ libraryItemId: deletedItem }), fixture.ids.session);
  source.close();
  await chmod(fixture.filename, 0o444);
  const invalidBase = process.env.LEAFWAKE_HISTORICAL_INVALID_URL || "http://127.0.0.1:19939";
  const request = async (path, data, token) => {
    const response = await fetch(invalidBase + path, {
      method: "POST",
      headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(data),
    });
    assert.ok(response.ok, `${path}: ${response.status}`);
    return response.json();
  };
  const digest = createHash("sha256")
    .update(await readFile(fixture.filename))
    .digest("hex");
  await request("/api/setup/import", {
    setupKey: "synthetic-history-import-2026",
    sourcePath: fixture.sourcePath,
    expectedDigest: digest,
  });
  const owner = (await request("/login", { username: "import-owner", password: "synthetic-password-2026" }))
    .user;
  const report = await request(
    "/api/admin/migrations/media/inspect",
    {
      sourcePath: fixture.sourcePath,
      mappings: [
        { from: "/old/synthetic/books", to: fixture.mediaRoot },
        { from: "/old/synthetic/podcasts", to: fixture.podcastRoot },
      ],
    },
    owner.accessToken,
  );
  assert.equal(report.canImport, false, "orphan book history must reference a book library");
  assert.ok(report.errors.some((error) => error.table === "playbackSessions" && error.id === session));
});
