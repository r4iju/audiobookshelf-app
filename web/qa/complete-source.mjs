import { randomUUID } from "node:crypto";
import { chmod, copyFile, mkdir, stat, writeFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import { hashSync } from "bcryptjs";

const host = "/Users/emanuel/.cache/leafwake/fullstack-import-153";
const mediaRoot = "/Users/emanuel/.cache/leafwake/fullstack-media-154/native-journeys";
export async function completeSource({ unsupported = false } = {}) {
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

  source.exec(
    "DELETE FROM unsupportedNotes; DELETE FROM books WHERE id='unmapped-book'; ALTER TABLE settings RENAME COLUMN id TO key; ALTER TABLE books ADD COLUMN coverPath TEXT",
  );
  if (unsupported === true)
    source
      .prepare("INSERT INTO unsupportedNotes VALUES('note','must report and block this unknown datum')")
      .run();
  source
    .prepare("UPDATE users SET pash=NULL,extraData=? WHERE id=?")
    .run(JSON.stringify({ authOpenIDSub: "qa-openid-subject" }), ids.user);
  const cover = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNwaDgAAAKEAYEml6crAAAAAElFTkSuQmCC",
    "base64",
  );
  await mkdir(host + "/metadata/items/" + ids.item, { recursive: true });
  await writeFile(host + "/metadata/items/" + ids.item + "/cover.png", cover);
  source
    .prepare("UPDATE books SET coverPath=? WHERE id=?")
    .run("/old/metadata/items/" + ids.item + "/cover.png", ids.book);
  source.prepare("INSERT INTO settings VALUES(?,?)").run(
    "server-settings",
    JSON.stringify({
      id: "server-settings",
      language: "en-us",
      authLoginCustomMessage: "Original sign-in notice",
      allowedOrigins: [],
      rateLimitLoginRequests: 9,
      rateLimitLoginWindow: 600000,
      authActiveAuthMethods: ["local", "openid"],
      authOpenIDIssuerURL: "http://host.docker.internal:19884",
      authOpenIDClientID: "abs-web-qa",
      authOpenIDClientSecret: "abs-web-qa-secret",
      authOpenIDAutoRegister: false,
      authOpenIDAutoLaunch: false,
      authOpenIDButtonText: "Original provider",
      authOpenIDMobileRedirectURIs: ["audiobookshelf-native-preview://oauth"],
      podcastEpisodeSchedule: "0 * * * *",
      backupSchedule: false,
      backupsToKeep: 2,
      logLevel: 2,
      loggerDailyLogsToKeep: 7,
      loggerScannerLogsToKeep: 2,
    }),
  );

  if (unsupported === "nested") {
    source
      .prepare("UPDATE mediaProgresses SET extraData=?")
      .run(JSON.stringify({ libraryItemId: ids.item, progress: 0.73, customReaderState: { position: 42 } }));
  }
  const podcastRoot = "/Users/emanuel/.cache/leafwake/fullstack-media-154/migration-podcasts";
  const podcastId = randomUUID(),
    podcastItemId = randomUUID(),
    podcastLibraryId = randomUUID(),
    podcastFolderId = randomUUID(),
    downloadedEpisodeId = randomUUID(),
    remoteEpisodeId = randomUUID(),
    episodeFileId = randomUUID();
  await mkdir(podcastRoot + "/Migration Podcast", { recursive: true });
  await copyFile(mediaRoot + "/Salt and Signal/01.mp3", podcastRoot + "/Migration Podcast/episode.mp3");
  source.exec(
    "CREATE TABLE podcasts(id TEXT PRIMARY KEY,title TEXT,description TEXT,feedURL TEXT,tags TEXT,genres TEXT,explicit INTEGER,autoDownloadEpisodes INTEGER,autoDownloadSchedule TEXT,maxEpisodesToKeep INTEGER,maxNewEpisodesToDownload INTEGER); CREATE TABLE podcastEpisodes(id TEXT PRIMARY KEY,podcastId TEXT,title TEXT,audioFile TEXT,enclosure TEXT,publishedAt TEXT,chapters TEXT)",
  );
  source
    .prepare("INSERT INTO libraries VALUES(?,?,?,?,?)")
    .run(podcastLibraryId, "Original podcast library", "podcast", 1, "{}");
  source
    .prepare("INSERT INTO libraryFolders VALUES(?,?,?)")
    .run(podcastFolderId, podcastLibraryId, "/old/synthetic/podcasts");
  const episodeFile = {
    ...file,
    ino: episodeFileId,
    metadata: {
      ...file.metadata,
      path: "/old/synthetic/podcasts/Migration Podcast/episode.mp3",
      filename: "episode.mp3",
      relPath: "episode.mp3",
    },
  };
  source
    .prepare("INSERT INTO libraryItems VALUES(?,?,?,?,?,?,0,0,0,?,?,?)")
    .run(
      podcastItemId,
      podcastLibraryId,
      podcastFolderId,
      podcastId,
      "podcast",
      "/old/synthetic/podcasts/Migration Podcast",
      JSON.stringify([{ ...episodeFile, fileType: "audio" }]),
      date,
      updated,
    );
  source
    .prepare("INSERT INTO podcasts VALUES(?,?,?,?,?,?,0,0,?,?,?)")
    .run(
      podcastId,
      "Original podcast",
      "Original description",
      "https://feed.example.invalid/rss",
      "[]",
      "[]",
      "0 * * * *",
      0,
      0,
    );
  source
    .prepare("INSERT INTO podcastEpisodes VALUES(?,?,?,?,?,?,?)")
    .run(
      downloadedEpisodeId,
      podcastId,
      "Original downloaded episode",
      JSON.stringify(episodeFile),
      JSON.stringify({ url: "https://feed.example.invalid/episode.mp3", type: "audio/mpeg", length: size }),
      date,
      "[]",
    );
  source
    .prepare("INSERT INTO podcastEpisodes VALUES(?,?,?,?,?,?,?)")
    .run(
      remoteEpisodeId,
      podcastId,
      "Original remote episode",
      null,
      JSON.stringify({ url: "https://feed.example.invalid/new.mp3", type: "audio/mpeg", length: size }),
      updated,
      "[]",
    );
  source.close();
  await copyFile(staging, filename);
  await chmod(filename, 0o444);
  return {
    filename,
    sourcePath,
    ids,
    collectionId,
    playlistId,
    mediaRoot,
    cover,
    podcastRoot,
    podcastItemId,
    remoteEpisodeId,
  };
}
