import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { chmod, copyFile, mkdir, readFile, stat } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { hashSync } from "bcryptjs";

const base = process.env.LEAFWAKE_MEDIA_IMPORT_TEST_URL || "http://127.0.0.1:19896";
const host = "/Users/emanuel/.cache/leafwake/fullstack-import-153";
const mediaRoot = "/Users/emanuel/.cache/leafwake/fullstack-media-154/native-journeys";
async function call(path, data, token, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(data === undefined ? {} : { "content-type": "application/json" }),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, data, token, method) {
  const r = await call(path, data, token, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
async function sha(path) {
  return createHash("sha256")
    .update(await readFile(path))
    .digest("hex");
}
test("read-only media import preserves original identities, files, progress, bookmarks and cumulative history across safe retry", async () => {
  await mkdir(host, { recursive: true });
  const name = `media-${randomUUID()}.sqlite`,
    filename = `${host}/${name}`,
    sourcePath = `/imports/${name}`;
  const ids = Object.fromEntries(
    [
      "owner",
      "user",
      "library",
      "folder",
      "item",
      "book",
      "file",
      "author",
      "series",
      "progress",
      "session",
    ].map((k) => [k, randomUUID()]),
  );
  const staging = `/tmp/leafwake-${name}`;
  const source = new DatabaseSync(staging);
  source.exec(
    `CREATE TABLE users(id TEXT PRIMARY KEY,username TEXT,pash TEXT,type TEXT,isActive INTEGER,isLocked INTEGER,permissions TEXT,bookmarks TEXT,extraData TEXT,createdAt TEXT);CREATE TABLE libraries(id TEXT PRIMARY KEY,name TEXT,mediaType TEXT,displayOrder INTEGER,settings TEXT);CREATE TABLE libraryFolders(id TEXT PRIMARY KEY,libraryId TEXT,path TEXT);CREATE TABLE libraryItems(id TEXT PRIMARY KEY,libraryId TEXT,libraryFolderId TEXT,mediaId TEXT,mediaType TEXT,path TEXT,isFile INTEGER,isMissing INTEGER,isInvalid INTEGER,libraryFiles TEXT,createdAt TEXT,updatedAt TEXT);CREATE TABLE books(id TEXT PRIMARY KEY,title TEXT,duration REAL,audioFiles TEXT,ebookFile TEXT,chapters TEXT,tags TEXT,genres TEXT,narrators TEXT,explicit INTEGER);CREATE TABLE authors(id TEXT PRIMARY KEY,name TEXT);CREATE TABLE series(id TEXT PRIMARY KEY,name TEXT);CREATE TABLE bookAuthors(id TEXT PRIMARY KEY,bookId TEXT,authorId TEXT);CREATE TABLE bookSeries(id TEXT PRIMARY KEY,bookId TEXT,seriesId TEXT,sequence TEXT);CREATE TABLE mediaProgresses(id TEXT PRIMARY KEY,userId TEXT,mediaItemId TEXT,mediaItemType TEXT,duration REAL,currentTime REAL,isFinished INTEGER,hideFromContinueListening INTEGER,ebookLocation TEXT,ebookProgress REAL,extraData TEXT,createdAt TEXT,updatedAt TEXT);CREATE TABLE playbackSessions(id TEXT PRIMARY KEY,userId TEXT,libraryId TEXT,mediaItemId TEXT,mediaItemType TEXT,duration REAL,currentTime REAL,timeListening REAL,startTime REAL,extraData TEXT,mediaMetadata TEXT,createdAt TEXT,updatedAt TEXT);CREATE TABLE unsupportedNotes(id TEXT PRIMARY KEY,value TEXT);INSERT INTO unsupportedNotes VALUES('note','report this datum');`,
  );
  const date = "2025-01-01T00:00:00.000Z",
    updated = "2025-01-02T00:00:00.000Z";
  const permissions = {
    download: true,
    update: true,
    delete: true,
    upload: true,
    accessExplicitContent: true,
    accessAllLibraries: true,
    accessAllTags: true,
    selectedTagsNotAccessible: false,
    librariesAccessible: [],
    itemTagsSelected: [],
  };
  const bookmark = {
    libraryItemId: ids.item,
    title: "Original bookmark",
    time: 21,
    createdAt: Date.parse(date),
  };
  for (const [id, name, type, marks] of [
    [ids.owner, "import-owner", "root", []],
    [ids.user, "import-user", "user", [bookmark]],
  ])
    source
      .prepare("INSERT INTO users VALUES(?,?,?,?,1,0,?,?,?,?)")
      .run(
        id,
        name,
        hashSync("synthetic-password-2026", 8),
        type,
        JSON.stringify(permissions),
        JSON.stringify(marks),
        "{}",
        date,
      );
  source
    .prepare("INSERT INTO libraries VALUES(?,?,?,?,?)")
    .run(ids.library, "Imported synthetic", "book", 0, "{}");
  source
    .prepare("INSERT INTO libraryFolders VALUES(?,?,?)")
    .run(ids.folder, ids.library, "/old/synthetic/books");
  const oldDir = "/old/synthetic/books/Salt and Signal";
  const size = (await stat(`${mediaRoot}/Salt and Signal/01.mp3`)).size;
  const file = {
    ino: ids.file,
    index: 1,
    duration: 60,
    mimeType: "audio/mpeg",
    metadata: { filename: "01.mp3", ext: ".mp3", path: oldDir + "/01.mp3", relPath: "01.mp3", size },
    exclude: false,
  };
  source
    .prepare("INSERT INTO libraryItems VALUES(?,?,?,?,?,?,0,0,0,?,?,?)")
    .run(
      ids.item,
      ids.library,
      ids.folder,
      ids.book,
      "book",
      oldDir,
      JSON.stringify([{ ...file, fileType: "audio", isSupplementary: false }]),
      date,
      updated,
    );
  source
    .prepare("INSERT INTO books VALUES(?,?,?,?,?,?,?,?,?,0)")
    .run(ids.book, "Salt and Signal", 60, JSON.stringify([file]), null, "[]", '["original-tag"]', "[]", "[]");
  source.prepare("INSERT INTO authors VALUES(?,?)").run(ids.author, "Original author");
  source.prepare("INSERT INTO series VALUES(?,?)").run(ids.series, "Original series");
  source.prepare("INSERT INTO bookAuthors VALUES(?,?,?)").run(randomUUID(), ids.book, ids.author);
  source.prepare("INSERT INTO bookSeries VALUES(?,?,?,?)").run(randomUUID(), ids.book, ids.series, "2");
  source
    .prepare("INSERT INTO mediaProgresses VALUES(?,?,?,?,?,?,0,0,?,?,?,?,?)")
    .run(
      ids.progress,
      ids.user,
      ids.book,
      "book",
      60,
      23,
      "page-4",
      0.25,
      JSON.stringify({ libraryItemId: ids.item, progress: 0.73 }),
      date,
      updated,
    );
  source
    .prepare("INSERT INTO playbackSessions VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)")
    .run(
      ids.session,
      ids.user,
      ids.library,
      ids.book,
      "book",
      60,
      23,
      47,
      0,
      JSON.stringify({ libraryItemId: ids.item }),
      '{"title":"Salt and Signal"}',
      date,
      updated,
    );
  const secondItem = randomUUID(),
    secondBook = randomUUID();
  const secondDir = "/old/synthetic/books/A Very Long Story Title";
  const secondFile = {
    ...file,
    duration: 20,
    metadata: {
      ...file.metadata,
      path: `${secondDir}/01.mp3`,
      size: (await stat(`${mediaRoot}/A Very Long Story Title/01.mp3`)).size,
    },
  };
  source.prepare("INSERT INTO libraryItems VALUES(?,?,?,?,?,?,0,0,0,?,?,?)").run(
    secondItem,
    ids.library,
    ids.folder,
    secondBook,
    "book",
    secondDir,
    JSON.stringify([
      {
        ...secondFile,
        fileType: "audio",
        isSupplementary: process.env.LEAFWAKE_MEDIA_IMPORT_TEST_DEFECT === "compound" ? false : null,
      },
    ]),
    date,
    updated,
  );
  source
    .prepare("INSERT INTO books VALUES(?,?,?,?,?,?,?,?,?,0)")
    .run(
      secondBook,
      "A Very Long Story Title",
      20,
      JSON.stringify([secondFile]),
      null,
      "[]",
      "[]",
      "[]",
      "[]",
    );
  if (process.env.LEAFWAKE_MEDIA_IMPORT_TEST_DEFECT === "compound")
    source.exec("ALTER TABLE mediaProgresses DROP COLUMN hideFromContinueListening");
  source
    .prepare("INSERT INTO books VALUES(?,?,?,?,?,?,?,?,?,0)")
    .run("unmapped-book", "Unmapped book", 0, "[]", null, "[]", "[]", "[]", "[]");
  source.close();
  await copyFile(staging, filename);
  await chmod(filename, 0o444);
  const digest = await sha(filename);
  const accounts = await json("/api/setup/import/inspect", {
    setupKey: "synthetic-import-operator-2026",
    sourcePath,
  });
  assert.equal(accounts.canImport, true, "bookmarks can be archived safely during account stage");
  await json("/api/setup/import", {
    setupKey: "synthetic-import-operator-2026",
    sourcePath,
    expectedDigest: digest,
  });
  const owner = (await json("/login", { username: "import-owner", password: "synthetic-password-2026" }))
    .user;
  const input = { sourcePath, mappings: [{ from: "/old/synthetic/books", to: mediaRoot }] };
  const report = await json("/api/admin/migrations/media/inspect", input, owner.accessToken);
  assert.equal(report.canImport, true);
  assert.equal(report.canCutover, false);
  assert.equal(report.counts.items, 2);
  assert.equal(report.counts.progress, 1);
  assert.ok(
    report.remainingData.some(
      (entry) => entry.table === "books" && entry.recordIds?.includes("unmapped-book"),
    ),
    "report unconsumed records in known tables",
  );
  assert.equal(report.counts.listeningSeconds, 47);
  assert.ok(report.remainingData.some((t) => t.table === "unsupportedNotes" && t.rows === 1));
  assert.equal(
    (
      await call(
        "/api/admin/migrations/media",
        { ...input, expectedDigest: "0".repeat(64) },
        owner.accessToken,
      )
    ).status,
    409,
  );
  assert.equal(
    (await json("/api/libraries", undefined, owner.accessToken)).libraries.length,
    0,
    "failure leaves destination empty",
  );
  const completed = await json(
    "/api/admin/migrations/media",
    { ...input, expectedDigest: digest },
    owner.accessToken,
  );
  assert.equal(completed.scope, "media");
  assert.deepEqual(
    await json("/api/admin/migrations/media", { ...input, expectedDigest: digest }, owner.accessToken),
    completed,
  );
  const user = (await json("/login", { username: "import-user", password: "synthetic-password-2026" })).user;
  assert.equal(user.id, ids.user);
  assert.ok(user.bookmarks.some((b) => b.title === "Original bookmark"));
  const item = await json(`/api/items/${ids.item}`, undefined, user.accessToken);
  assert.equal(item.media.id, ids.book);
  assert.equal(item.media.metadata.authors[0].id, ids.author);
  assert.equal(item.media.metadata.series[0].id, ids.series);
  assert.equal(item.libraryFiles[0].ino, ids.file);
  const fileResponse = await call(`/api/items/${ids.item}/file/${ids.file}`, undefined, user.accessToken);
  assert.equal(fileResponse.status, 200);
  assert.equal((await fileResponse.arrayBuffer()).byteLength, size);
  const progress = await json(`/api/me/progress/${ids.item}`, undefined, user.accessToken);
  assert.equal(progress.id, ids.progress);
  assert.equal(progress.currentTime, 23);
  assert.equal(progress.progress, 0.73, "preserve the original manual fraction");
  assert.equal(progress.ebookLocation, "page-4");
  const stats = await json("/api/me/listening-stats", undefined, user.accessToken);
  assert.equal(stats.totalTime, 47);
  const scan = await json(`/api/libraries/${ids.library}/scan`, {}, owner.accessToken);
  assert.equal(scan.status, "complete");
  const rescanned = await json(`/api/items/${ids.item}`, undefined, user.accessToken);
  assert.equal(rescanned.media.id, ids.book, "rescan retains imported media identity");
  assert.equal(rescanned.libraryFiles[0].ino, ids.file, "rescan retains imported native file association");
  assert.equal(await sha(filename), digest, "original source remains byte-for-byte unchanged");
  console.log(
    "Preserved import IDs and history; source",
    sourcePath,
    "library",
    ids.library,
    "item",
    ids.item,
  );
});
