import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, rename, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";

const origin = process.env.LEAFWAKE_CATALOG_TEST_URL || "http://127.0.0.1:19889";
const root = process.env.LEAFWAKE_CATALOG_TEST_ROOT || "/Users/emanuel/.cache/leafwake/fullstack-media-154";
async function call(path, method = "GET", data, token) {
  return fetch(origin + path, {
    method,
    headers: {
      ...(data === undefined ? {} : { "content-type": "application/json" }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
    signal: AbortSignal.timeout(30000),
  });
}
async function login(username = "installation-owner") {
  const r = await call("/login", "POST", { username, password: "synthetic-password-2026" });
  assert.equal(r.status, 200);
  return (await r.json()).user.accessToken;
}
test("mounted media scans into stable paginated records and enforces account content policies", async () => {
  const directory = join(root, `run-${Date.now()}`);
  for (const [title, explicit, tags] of [
    ["Safe book", false, ["safe"]],
    ["Explicit book", true, ["safe"]],
    ["Other tag", false, ["other"]],
  ]) {
    const folder = join(directory, title);
    await mkdir(folder, { recursive: true });
    execFileSync("ffmpeg", [
      "-loglevel",
      "error",
      "-f",
      "lavfi",
      "-i",
      `sine=frequency=440:duration=${explicit ? 2 : tags[0] === "other" ? 3 : 1}`,
      "-y",
      join(folder, "chapter.mp3"),
    ]);
    await writeFile(
      join(folder, "metadata.json"),
      JSON.stringify({ title, explicit, tags, authors: ["Synthetic author"] }),
    );
  }
  const escaped = join(directory, "Escaped metadata");
  await mkdir(escaped);
  await copyFile(join(directory, "Other tag", "chapter.mp3"), join(escaped, "chapter.mp3"));
  const outsideMetadata = `/tmp/leafwake-outside-metadata-${Date.now()}.json`;
  await writeFile(outsideMetadata, JSON.stringify({ title: "OUTSIDE ROOT SECRET" }));
  await symlink(outsideMetadata, join(escaped, "metadata.json"));
  await symlink("/etc", join(directory, "escape"));
  const owner = await login();
  const forbidden = await call(
    "/api/libraries",
    "POST",
    { name: "Outside", folders: [{ fullPath: "/etc" }], mediaType: "book" },
    owner,
  );
  assert.equal(forbidden.status, 400, "library folders must stay inside configured media roots");
  const duplicate = await call(
    "/api/libraries",
    "POST",
    { name: "Duplicates", mediaType: "book", folders: [{ fullPath: directory }, { fullPath: directory }] },
    owner,
  );
  assert.equal(duplicate.status, 400, "duplicate or overlapping scan roots are rejected");
  const created = await call(
    "/api/libraries",
    "POST",
    { name: "Synthetic catalog", folders: [{ fullPath: directory }], mediaType: "book" },
    owner,
  );
  assert.equal(created.status, 200, "administrator can create a mounted library");
  const library = await created.json();
  assert.ok(library.id);
  const scan = await call(`/api/libraries/${library.id}/scan`, "POST", {}, owner);
  assert.equal(scan.status, 200);
  const report = await scan.json();
  assert.ok(report.errors.some((e) => /symlink/i.test(e.message)));
  const listing = await call(`/api/libraries/${library.id}/items?limit=2&page=0`, "GET", undefined, owner);
  assert.equal(listing.status, 200);
  const page = await listing.json();
  assert.equal(page.total, 3);
  assert.equal(page.results.length, 2);
  const all = await (
    await call(`/api/libraries/${library.id}/items?limit=10`, "GET", undefined, owner)
  ).json();
  const safe = all.results.find((item) => item.media.metadata.title === "Safe book");
  assert.ok(safe);
  const detail = await (await call(`/api/items/${safe.id}`, "GET", undefined, owner)).json();
  assert.ok(detail.media.duration > 0);
  assert.equal(detail.media.tracks.length, 1);
  assert.ok(detail.media.tracks[0].contentUrl);
  await call(`/api/libraries/${library.id}/scan`, "POST", {}, owner);
  const rescanned = await (
    await call(`/api/libraries/${library.id}/items?limit=10`, "GET", undefined, owner)
  ).json();
  assert.deepEqual(rescanned.results.map((i) => i.id).sort(), all.results.map((i) => i.id).sort());
  const username = `catalog-limited-${Date.now()}`;
  const user = await call(
    "/api/users",
    "POST",
    {
      username,
      password: "synthetic-password-2026",
      type: "user",
      permissions: { accessAllLibraries: false, accessAllTags: false, accessExplicitContent: false },
      librariesAccessible: [library.id],
      itemTagsSelected: ["safe"],
    },
    owner,
  );
  assert.equal(user.status, 200);
  const restricted = await login(username);
  const visible = await (
    await call(`/api/libraries/${library.id}/items?limit=10`, "GET", undefined, restricted)
  ).json();
  assert.equal(visible.total, 1);
  assert.equal(visible.results[0].id, safe.id);
  const explicit = all.results.find((i) => i.media.metadata.explicit);
  assert.equal((await call(`/api/items/${explicit.id}`, "GET", undefined, restricted)).status, 404);
  const filters = await (
    await call(`/api/libraries/${library.id}?include=filterdata`, "GET", undefined, owner)
  ).json();
  assert.ok(
    filters.filterdata.tags.includes("safe"),
    "consumed library response provides scan-derived filters",
  );
  const sorted = await (
    await call(
      `/api/libraries/${library.id}/items?sort=media.duration&desc=0&limit=10`,
      "GET",
      undefined,
      owner,
    )
  ).json();
  assert.equal(sorted.results[0].id, safe.id, "requested duration sort controls result order");
  const tagFilter = encodeURIComponent(`tags.${Buffer.from("other").toString("base64")}`);
  const filtered = await (
    await call(`/api/libraries/${library.id}/items?filter=${tagFilter}`, "GET", undefined, owner)
  ).json();
  assert.equal(filtered.total, 1);
  assert.equal(filtered.results[0].media.metadata.title, "Other tag");
  await rename(join(directory, "Safe book"), join(root, `missing-${Date.now()}`));
  await call(`/api/libraries/${library.id}/scan`, "POST", {}, owner);
  const missing = await (await call(`/api/items/${safe.id}`, "GET", undefined, owner)).json();
  assert.equal(missing.isMissing, true, "rescan retains missing records instead of destroying user history");
});
