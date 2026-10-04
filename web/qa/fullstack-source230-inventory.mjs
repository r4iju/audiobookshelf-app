import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { chmod, readFile } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { completeSource } from "./complete-source.mjs";

const base = process.env.LEAFWAKE_SOURCE230_URL || "http://127.0.0.1:19942";
async function call(path, data, token) {
  const response = await fetch(base + path, {
    method: "POST",
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(data),
  });
  assert.ok(response.ok, `${path}: ${response.status} ${await response.clone().text()}`);
  return response.json();
}
test("stock 2.30 bookkeeping is explicitly archived without reactivating legacy sessions or executing triggers", async () => {
  const fixture = await completeSource();
  await chmod(fixture.filename, 0o600);
  const db = new DatabaseSync(fixture.filename);
  for (const [table, fields] of Object.entries({
    authors: ["lastFirst", "libraryId"],
    books: ["titleIgnorePrefix"],
    libraries: ["lastScan", "lastScanVersion", "extraData"],
    libraryItems: [
      "title",
      "titleIgnorePrefix",
      "authorNamesFirstLast",
      "authorNamesLastFirst",
      "birthtime",
      "ctime",
      "mtime",
      "lastScan",
      "lastScanVersion",
    ],
    mediaProgresses: ["podcastId"],
    playbackSessions: ["coverPath", "deviceId"],
  }))
    for (const field of fields) db.exec(`ALTER TABLE ${table} ADD COLUMN ${field} TEXT`);
  db.exec(
    "UPDATE libraries SET extraData='{}'; CREATE TABLE devices(id TEXT,deviceId TEXT,clientName TEXT,clientVersion TEXT,ipAddress TEXT,deviceName TEXT,deviceVersion TEXT,extraData TEXT,createdAt TEXT,updatedAt TEXT,userId TEXT); CREATE TABLE sessions(id TEXT,userId TEXT,refreshToken TEXT,ipAddress TEXT,userAgent TEXT,expiresAt TEXT,createdAt TEXT,updatedAt TEXT); CREATE TABLE migrationsMeta(key TEXT,value TEXT)",
  );
  const device = randomUUID(),
    oldSession = randomUUID(),
    date = "2025-01-01T00:00:00.000Z";
  db.prepare("INSERT INTO devices VALUES(?,?,?,?,?,?,?,?,?,?,?)").run(
    device,
    "original-device-uuid",
    "Leafwake",
    "1",
    "127.0.0.1",
    "Synthetic phone",
    null,
    JSON.stringify({
      manufacturer: "Synthetic",
      model: "Fixture",
      osName: "Android",
      osVersion: "16",
      browserName: null,
    }),
    date,
    date,
    fixture.ids.user,
  );
  db.prepare("INSERT INTO sessions VALUES(?,?,?,?,?,?,?,?)").run(
    oldSession,
    fixture.ids.user,
    "synthetic-retired-refresh-token",
    "127.0.0.1",
    "Fixture",
    "2030-01-01T00:00:00.000Z",
    date,
    date,
  );
  db.prepare("INSERT INTO migrationsMeta VALUES(?,?)").run("version", "2.30.0");
  db.prepare("UPDATE playbackSessions SET deviceId=?").run(device);
  db.prepare("UPDATE libraries SET extraData=?").run(
    JSON.stringify({ lastScanMetadataPrecedence: ["folderStructure", "metadataFile", "audioMetatags"] }),
  );
  for (const row of db.prepare("SELECT id,audioFiles FROM books").all()) {
    const files = JSON.parse(row.audioFiles);
    for (const file of files) {
      file.language = "eng";
      file.manuallyVerified = false;
      file.metaTags = { tagEncoder: "Synthetic encoder" };
    }
    db.prepare("UPDATE books SET audioFiles=?,titleIgnorePrefix=? WHERE id=?").run(
      JSON.stringify(files),
      "Cached title",
      row.id,
    );
  }
  db.exec(`CREATE TRIGGER update_library_items_title
        AFTER UPDATE OF title ON books
        FOR EACH ROW
        BEGIN
          UPDATE libraryItems
            SET title = NEW.title
          WHERE libraryItems.mediaId = NEW.id;
        END`);
  const unsupported = process.env.LEAFWAKE_SOURCE230_UNKNOWN_TRIGGER === "1";
  if (unsupported)
    db.exec("CREATE TRIGGER custom_unsupported_trigger AFTER UPDATE ON books BEGIN SELECT 1; END");
  db.close();
  await chmod(fixture.filename, 0o444);
  const digest = createHash("sha256")
    .update(await readFile(fixture.filename))
    .digest("hex");
  await call("/api/setup/import", {
    setupKey: "synthetic-source230-import-2026",
    sourcePath: fixture.sourcePath,
    expectedDigest: digest,
  });
  const owner = (await call("/login", { username: "import-owner", password: "synthetic-password-2026" }))
    .user;
  const token = owner.accessToken;
  await call(
    "/api/admin/migrations/media",
    {
      sourcePath: fixture.sourcePath,
      expectedDigest: digest,
      mappings: [
        { from: "/old/synthetic/books", to: fixture.mediaRoot },
        { from: "/old/synthetic/podcasts", to: fixture.podcastRoot },
      ],
    },
    token,
  );
  await call("/api/admin/migrations/lists", { digest }, token);
  await call("/api/admin/migrations/delivery", { digest, serverAddress: base }, token);
  const input = {
    digest,
    sourcePath: fixture.sourcePath,
    publicUrl: base,
    coverMappings: [{ from: "/old/metadata", to: "/imports/metadata" }],
    redirectUris: [base + "/oauth", "leafwake://oauth", "audiobookshelf-native-preview://oauth"],
  };
  const report = await call("/api/admin/migrations/complete/inspect", input, token);
  assert.equal(
    report.canCutover,
    !unsupported,
    JSON.stringify({ unsupported: report.unsupported, errors: report.errors }),
  );
  assert.equal(report.canImport, !unsupported);
  if (unsupported) {
    assert.ok(report.unsupported.some((row) => row.table === "custom_unsupported_trigger"));
    return;
  }
  for (const table of ["devices", "sessions", "migrationsMeta", "update_library_items_title"]) {
    const entry = report.inventory.find((row) => row.table === table);
    assert.equal(entry.disposition, "archived");
  }
  assert.ok(
    report.inventory
      .find((row) => row.table === "books")
      .fields.some((field) => field.name === "titleIgnorePrefix" && field.disposition === "archived"),
  );
  assert.ok(!JSON.stringify(report).includes("synthetic-retired-refresh-token"));
  await call("/api/admin/migrations/complete", input, token);
  assert.equal(
    createHash("sha256")
      .update(await readFile(fixture.filename))
      .digest("hex"),
    digest,
  );
  const rejected = await fetch(base + "/api/me", {
    headers: { authorization: "Bearer synthetic-retired-refresh-token" },
  });
  assert.equal(rejected.status, 401);
});
