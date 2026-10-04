import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { chmod, copyFile, mkdir, readFile, stat } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { hashSync } from "bcryptjs";

const base = process.env.LEAFWAKE_DELIVERY_IMPORT_TEST_URL || "http://127.0.0.1:19907";
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
test("original feed GUIDs, enclosure routes and specific-user device rules survive atomic safe-retry import", async () => {
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
  const collectionId = randomUUID(),
    playlistId = randomUUID();
  source.exec(
    'CREATE TABLE collections(id TEXT,name TEXT,description TEXT,libraryId TEXT,createdAt TEXT,updatedAt TEXT); CREATE TABLE collectionBooks(id TEXT,collectionId TEXT,bookId TEXT,"order" INTEGER); CREATE TABLE playlists(id TEXT,name TEXT,description TEXT,libraryId TEXT,userId TEXT,createdAt TEXT,updatedAt TEXT); CREATE TABLE playlistMediaItems(id TEXT,playlistId TEXT,mediaItemId TEXT,mediaItemType TEXT,"order" INTEGER)',
  );
  source
    .prepare("INSERT INTO collections VALUES(?,?,?,?,?,?)")
    .run(collectionId, "Original collection", null, ids.library, date, updated);
  source
    .prepare("INSERT INTO collectionBooks VALUES(?,?,?,?)")
    .run(randomUUID(), collectionId, secondBook, 0);
  source.prepare("INSERT INTO collectionBooks VALUES(?,?,?,?)").run(randomUUID(), collectionId, ids.book, 1);
  source
    .prepare("INSERT INTO playlists VALUES(?,?,?,?,?,?,?)")
    .run(playlistId, "Original private playlist", null, ids.library, ids.user, date, updated);
  source
    .prepare("INSERT INTO playlistMediaItems VALUES(?,?,?,?,?)")
    .run(randomUUID(), playlistId, ids.book, "book", 0);
  source.exec(
    "CREATE TABLE feeds(id TEXT,slug TEXT,entityType TEXT,entityId TEXT,userId TEXT,serverAddress TEXT,title TEXT,ownerName TEXT,ownerEmail TEXT,preventIndexing INTEGER); CREATE TABLE feedEpisodes(id TEXT,feedId TEXT,title TEXT,filePath TEXT,enclosureType TEXT,enclosureSize INTEGER,pubDate TEXT,duration REAL); CREATE TABLE settings(id TEXT,value TEXT)",
  );
  source
    .prepare("INSERT INTO feeds VALUES(?,?,?,?,?,?,?,?,?,?)")
    .run(
      "original-feed",
      "original-slug",
      "libraryItem",
      ids.item,
      ids.owner,
      "https://old.example.invalid",
      "Original RSS",
      "Original owner",
      "owner@example.invalid",
      1,
    );
  source
    .prepare("INSERT INTO feedEpisodes VALUES(?,?,?,?,?,?,?,?)")
    .run(
      "original-episode",
      "original-feed",
      "Original episode",
      oldDir + "/01.mp3",
      "audio/mpeg",
      size,
      date,
      60,
    );
  source.prepare("INSERT INTO settings VALUES(?,?)").run(
    "email-settings",
    JSON.stringify({
      id: "email-settings",
      host: "smtp.example.invalid",
      port: 465,
      secure: true,
      rejectUnauthorized: true,
      user: "synthetic-user",
      pass: "synthetic-private-password",
      fromAddress: "owner@example.invalid",
      ereaderDevices: [
        {
          name: "Original reader",
          email: "reader@example.invalid",
          availabilityOption: "specificUsers",
          users: [ids.user],
        },
      ],
    }),
  );
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
  const listReport = await json("/api/admin/migrations/lists/inspect", { digest }, owner.accessToken);
  assert.equal(listReport.canImport, true);
  assert.equal(listReport.counts.collections, 1);
  assert.equal(listReport.counts.playlists, 1);
  const listCommit = await json("/api/admin/migrations/lists", { digest }, owner.accessToken);
  assert.deepEqual(await json("/api/admin/migrations/lists", { digest }, owner.accessToken), listCommit);
  const importedCollection = await json(`/api/collections/${collectionId}`, undefined, user.accessToken);
  assert.deepEqual(
    importedCollection.books.map((b) => b.id),
    [secondItem, ids.item],
  );
  const importedPlaylist = await json(`/api/playlists/${playlistId}`, undefined, user.accessToken);
  assert.equal(importedPlaylist.userId, ids.user);
  assert.deepEqual(
    importedPlaylist.items.map((i) => i.libraryItemId),
    [ids.item],
  );
  assert.equal((await call(`/api/playlists/${playlistId}`, undefined, owner.accessToken)).status, 404);
  const deliveryInput = { digest, serverAddress: base };
  const delivery = await json("/api/admin/migrations/delivery/inspect", deliveryInput, owner.accessToken);
  assert.equal(delivery.canImport, true);
  assert.deepEqual(delivery.counts, { feeds: 1, episodes: 1, devices: 1, smtp: 1 });
  assert.ok(!JSON.stringify(delivery).includes("synthetic-private-password"));
  const committed = await json("/api/admin/migrations/delivery", deliveryInput, owner.accessToken);
  assert.deepEqual(await json("/api/admin/migrations/delivery", deliveryInput, owner.accessToken), committed);
  const rss = await fetch(base + "/feed/original-slug");
  assert.equal(rss.status, 200);
  const xml = await rss.text();
  assert.ok(xml.includes("original-episode"));
  assert.ok(xml.includes("/feed/original-slug/item/original-episode/media.mp3"));
  const enclosure = await fetch(base + "/feed/original-slug/item/original-episode/media.mp3", {
    headers: { range: "bytes=0-15" },
  });
  assert.equal(enclosure.status, 206);
  assert.equal((await enclosure.arrayBuffer()).byteLength, 16);
  const smtp = await json("/api/emails/settings", undefined, owner.accessToken);
  assert.equal(smtp.hasPassword, true);
  assert.ok(!JSON.stringify(smtp).includes("synthetic-private-password"));
  assert.deepEqual((await json("/api/authorize", {}, user.accessToken)).ereaderDevices, [
    { name: "Original reader" },
  ]);
  assert.deepEqual(
    (await json("/api/authorize", {}, owner.accessToken)).ereaderDevices,
    [],
    "specificUsers must not implicitly grant admins access",
  );
  assert.equal(await sha(filename), digest);
});
