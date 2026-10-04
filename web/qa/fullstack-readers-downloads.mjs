import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { copyFile, mkdir, writeFile } from "node:fs/promises";
import test from "node:test";

const base = process.env.LEAFWAKE_READERS_TEST_URL || "http://127.0.0.1:19902";
async function call(path, token, data, method = data === undefined ? "GET" : "POST", extra = {}) {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(data === undefined ? {} : { "content-type": "application/json" }),
      ...extra,
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, token, data, method) {
  const r = await call(path, token, data, method);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("real primary/supplementary documents, ranged authorized files and streamed ZIP64 downloads", async () => {
  const key = randomUUID(),
    root = `/Users/emanuel/.cache/leafwake/fullstack-media-154/readers-${key}`;
  await mkdir(`${root}/PDF book`, { recursive: true });
  const source =
    "/Users/emanuel/.cache/leafwake/fullstack-media-154/native-journeys/Field Guide to Quiet/Field Guide to Quiet.pdf";
  await copyFile(source, `${root}/PDF book/01-primary.pdf`);
  await copyFile(source, `${root}/PDF book/02-supplementary.pdf`);
  await mkdir(`${root}/EPUB book`, { recursive: true });
  await mkdir(`${root}/Comic book`, { recursive: true });
  execFileSync("python3", [
    "-c",
    `import zipfile,sys,base64
root=sys.argv[1]
with zipfile.ZipFile(root+'/EPUB book/book.epub','w') as z:
 z.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
 z.writestr('META-INF/container.xml','<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
 z.writestr('content.opf','<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Replacement reader acceptance</dc:title><dc:identifier id="id">synthetic</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>')
 z.writestr('chapter.xhtml','<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter one</title></head><body><h1>Replacement reader acceptance</h1><p>A quiet path through the trees.</p></body></html>')
with zipfile.ZipFile(root+'/Comic book/comic.cbz','w') as z:
 png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jHHkAAAAASUVORK5CYII=')
 z.writestr('01.png',png);z.writestr('02.png',png)
`,
    root,
  ]);
  const owner = (
    await json("/login", null, { username: "import-owner", password: "synthetic-password-2026" })
  ).user;
  const library = await json("/api/libraries", owner.accessToken, {
    name: `Readers ${key}`,
    mediaType: "book",
    folders: [{ fullPath: root }],
  });
  await json(`/api/libraries/${library.id}/scan`, owner.accessToken, {});
  const items = (await json(`/api/libraries/${library.id}/items`, owner.accessToken)).results;
  assert.equal(items.length, 3);
  const pdf = items.find((i) => i.media.ebookFormat === "pdf");
  assert.equal(
    pdf.libraryFiles.find((f) => f.ino !== pdf.media.ebookFile.ino).isSupplementary,
    true,
    "secondary documents are available without primary progress semantics",
  );
  for (const item of items) {
    const response = await call(`/api/items/${item.id}/ebook`, owner.accessToken);
    assert.equal(response.status, 200);
    const ext = item.media.ebookFormat;
    assert.equal(
      response.headers.get("content-type"),
      ext === "pdf"
        ? "application/pdf"
        : ext === "epub"
          ? "application/epub+zip"
          : "application/vnd.comicbook+zip",
    );
    assert.ok((await response.arrayBuffer()).byteLength > 100);
  }
  const extra = pdf.libraryFiles.find((f) => f.isSupplementary);
  assert.equal((await call(`/api/items/${pdf.id}/ebook/${extra.ino}`, owner.accessToken)).status, 200);
  const ranged = await call(`/api/items/${pdf.id}/ebook`, owner.accessToken, undefined, "GET", {
    range: "bytes=10-49",
  });
  assert.equal(ranged.status, 206);
  assert.equal((await ranged.arrayBuffer()).byteLength, 40);
  assert.equal(
    (
      await call(`/api/items/${pdf.id}/ebook`, owner.accessToken, undefined, "GET", {
        range: "bytes=999999999999-",
      })
    ).status,
    416,
  );
  await json(
    `/api/me/progress/${pdf.id}`,
    owner.accessToken,
    { ebookLocation: "4", ebookProgress: 0.25, updatedAt: Date.now() },
    "PATCH",
  );
  await (await call(`/api/items/${pdf.id}/ebook/${extra.ino}`, owner.accessToken)).arrayBuffer();
  assert.equal((await json(`/api/me/progress/${pdf.id}`, owner.accessToken)).ebookLocation, "4");
  const archive = await call(`/api/items/${pdf.id}/download?token=${owner.accessToken}`, null);
  assert.equal(archive.status, 200);
  assert.match(archive.headers.get("content-disposition"), /\.zip/);
  const target = `/tmp/leafwake-reader-archive-${key}.zip`;
  await writeFile(target, Buffer.from(await archive.arrayBuffer()));
  const names = JSON.parse(
    execFileSync(
      "python3",
      [
        "-c",
        "import zipfile,json,sys;z=zipfile.ZipFile(sys.argv[1]);assert z.testzip() is None;print(json.dumps(z.namelist()))",
        target,
      ],
      { encoding: "utf8" },
    ),
  );
  assert.equal(names.length, 2);
  assert.ok(names.every((n) => n.endsWith(".pdf") && !n.includes("..")));
  const user = await json("/api/users", owner.accessToken, {
    username: `no-download-${key}`,
    password: "synthetic-password-2026",
    type: "user",
    permissions: { download: false },
  });
  const account = (
    await json("/login", null, { username: user.username, password: "synthetic-password-2026" })
  ).user;
  assert.equal((await call(`/api/items/${pdf.id}/download`, account.accessToken)).status, 403);
  assert.equal(
    (await call(`/api/items/${pdf.id}/file/${pdf.media.ebookFile.ino}/download`, account.accessToken)).status,
    403,
  );
  assert.equal((await call(`/api/items/${pdf.id}/ebook`, account.accessToken)).status, 200);
  assert.equal((await call(`/api/items/${pdf.id}/ebook/absent`, owner.accessToken)).status, 404);
  console.log(
    "Reader fixtures",
    JSON.stringify(items.map((i) => ({ id: i.id, format: i.media.ebookFormat }))),
  );
});
