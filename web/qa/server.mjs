// Runs the Leafwake product image on one listener with a private synthetic volume and read-only library.
// QA fixtures use the same image as bounded local helpers; no original backend is launched.
// node qa/server.mjs up [--fresh] | down
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { hashSync } from "bcryptjs";
import { FEED_PORT } from "./feed.mjs";
import { MAIL_PORT } from "./mail.mjs";
import { OIDC_PORT } from "./oidc.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const runtime = join(here, ".runtime");
export const container = process.env.ABS_QA_CONTAINER ?? "leafwake-web-qa";
const stateFile = join(runtime, `state-${container}.json`);
export const image = process.env.LEAFWAKE_QA_IMAGE ?? "leafwake:qa";
export const QA_PORT = Number(process.env.ABS_QA_PORT ?? 19880);
const origin = `http://127.0.0.1:${QA_PORT}${process.env.ABS_WEB_BASE_PATH ?? ""}`;
const setupKey = "synthetic-leafwake-qa-setup-2026";
const fixtures = { feed: FEED_PORT, mail: MAIL_PORT, oidc: OIDC_PORT };
export const env = {
  ...process.env,
  DOCKER_HOST: process.env.DOCKER_HOST ?? `unix://${process.env.HOME}/.colima/default/docker.sock`,
};
export const accounts = {
  admin: { username: "qa-admin", password: "qa-admin-pass" },
  user: { username: "qa", password: "qa-pass" },
  other: { username: "qa-other", password: "qa-other-pass" },
  limited: { username: "qa-limited", password: "qa-limited-pass" },
};
export const docker = (...args) => execFileSync("docker", args, { env, encoding: "utf8" }).trim();
async function call(path, { token, method = "GET", body } = {}) {
  const r = await fetch(origin + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`${path}: ${r.status} ${await r.text()}`);
  return r.json();
}
async function ready() {
  for (let n = 0; n < 200; n++) {
    try {
      const r = await fetch(`${origin}/healthz`);
      if (r.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("QA image did not become ready");
}
function accountSnapshot() {
  const imports = join(runtime, "imports");
  mkdirSync(imports, { recursive: true });
  const name = `qa-accounts-${randomUUID()}.sqlite`,
    filename = join(imports, name);
  const db = new DatabaseSync(filename),
    users = {};
  db.exec(
    "CREATE TABLE users(id TEXT PRIMARY KEY,username TEXT,pash TEXT,type TEXT,isActive INTEGER,isLocked INTEGER,permissions TEXT,bookmarks TEXT,extraData TEXT,createdAt TEXT)",
  );
  const flags = {
    download: true,
    update: true,
    delete: false,
    upload: false,
    accessAllLibraries: true,
    accessAllTags: true,
    accessExplicitContent: true,
    selectedTagsNotAccessible: false,
    librariesAccessible: [],
    itemTagsSelected: [],
  };
  for (const [key, account] of Object.entries(accounts)) {
    const id = randomUUID();
    users[key] = id;
    db.prepare("INSERT INTO users VALUES(?,?,?,?,?,?,?,?,?,?)").run(
      id,
      account.username,
      hashSync(account.password, 10),
      key === "admin" ? "root" : "user",
      1,
      0,
      JSON.stringify(key === "admin" ? { ...flags, delete: true } : flags),
      "[]",
      "{}",
      new Date().toISOString(),
    );
  }
  db.close();
  chmodSync(filename, 0o444);
  return {
    sourcePath: `/imports/${name}`,
    expectedDigest: createHash("sha256").update(readFileSync(filename)).digest("hex"),
    users,
  };
}
async function seed(snapshot) {
  await call("/api/setup/import", {
    method: "POST",
    body: { setupKey, sourcePath: snapshot.sourcePath, expectedDigest: snapshot.expectedDigest },
  });
  const token = (await call("/login", { method: "POST", body: accounts.admin })).user.accessToken;
  await call("/api/settings", {
    token,
    method: "PATCH",
    body: {
      ...(await call("/api/settings", { token })),
      allowedOrigins: ["http://127.0.0.1:19881", "http://localhost:19881"],
      rateLimitLoginRequests: 50,
      rateLimitLoginWindow: 60000,
    },
  });
  const podcastSettings = await call("/api/admin/podcasts/settings", { token });
  await call("/api/admin/podcasts/settings", {
    token,
    method: "PATCH",
    body: { ...podcastSettings, maxConcurrent: 1 },
  });
  const books = await call("/api/libraries", {
    token,
    method: "POST",
    body: { name: "Audiobooks", mediaType: "book", folders: [{ fullPath: "/library/books" }] },
  });
  const podcasts = await call("/api/libraries", {
    token,
    method: "POST",
    body: {
      name: "Podcasts",
      mediaType: "podcast",
      folders: [{ fullPath: "/library/podcasts" }, { fullPath: "/data/media" }],
    },
  });
  await call(`/api/users/${snapshot.users.limited}`, {
    token,
    method: "PATCH",
    body: {
      permissions: { download: false, update: false, accessAllLibraries: false },
      librariesAccessible: [books.id],
    },
  });
  for (const library of [books, podcasts]) {
    const scan = await call(`/api/libraries/${library.id}/scan`, { token, method: "POST", body: {} });
    if (scan.status !== "complete") throw new Error("QA library scan did not complete");
  }
  // Keep the original journey catalog titles; ComicInfo still names the issue inside the reader.
  const catalog = await call(`/api/libraries/${books.id}/items?limit=0`, { token });
  for (const issue of [1, 2]) {
    const comic = catalog.results.find((item) => item.media.metadata.title === `Skyline Issue ${issue}`);
    if (!comic) throw new Error(`Missing comic fixture ${issue}`);
    await call(`/api/items/${comic.id}/media`, {
      token,
      method: "PATCH",
      body: { metadata: { title: `Skyline ${issue}` } },
    });
  }
  return {
    origin,
    serverVersion: (await call("/status")).serverVersion,
    libraries: { books: books.id, podcasts: podcasts.id },
    users: { user: snapshot.users.user, other: snapshot.users.other, limited: snapshot.users.limited },
    image,
  };
}
export async function startFixtures() {
  for (const [name, port] of Object.entries(fixtures)) {
    try {
      docker("rm", "-f", `${container}-${name}`);
    } catch {}
    docker(
      "run",
      "-d",
      "--name",
      `${container}-${name}`,
      "--user",
      `${process.getuid()}:${process.getgid()}`,
      "--network",
      `container:${container}`,
      "-e",
      "ABS_QA_FIXTURE_HOST=0.0.0.0",
      "-e",
      `ABS_QA_${name.toUpperCase()}_PORT=${port}`,
      "-v",
      `${here}:/qa`,
      "--entrypoint",
      "node",
      image,
      `/qa/${name}.mjs`,
    );
  }
}
export function stop() {
  for (const args of [
    ["rm", "-f", ...Object.keys(fixtures).map((name) => `${container}-${name}`)],
    ["rm", "-f", container],
  ]) {
    try {
      docker(...args);
    } catch {}
  }
}
export function down() {
  for (const args of [
    ["rm", "-f", ...Object.keys(fixtures).map((name) => `${container}-${name}`)],
    ["rm", "-f", container],
    ["volume", "rm", `${container}-data`],
  ]) {
    try {
      docker(...args);
    } catch {}
  }
  rmSync(stateFile, { force: true });
}
export async function up({ fresh = false } = {}) {
  execFileSync(join(here, "make-library.sh"), { stdio: "inherit" });
  if (fresh) down();
  let existing = docker("ps", "-a", "--filter", `name=^${container}$`, "--format", "{{.Status}}");
  if (existing && existsSync(stateFile)) {
    const state = JSON.parse(readFileSync(stateFile, "utf8"));
    const currentImage = docker("inspect", "--format", "{{.Image}}", container);
    const requestedImage = docker("image", "inspect", "--format", "{{.Id}}", image);
    if (state.origin !== origin || currentImage !== requestedImage) {
      stop();
      existing = "";
      process.env.LEAFWAKE_QA_REUSE_VOLUME = "1";
    }
  }
  if (!existing) {
    if (!process.env.LEAFWAKE_QA_IMAGE)
      execFileSync("docker", ["build", "-t", image, join(here, "..")], { env, stdio: "inherit" });
    const snapshot = accountSnapshot();
    docker(
      "run",
      "-d",
      "--name",
      container,
      "-p",
      `127.0.0.1:${QA_PORT}:3000`,
      ...Object.values(fixtures).flatMap((port) => ["-p", `127.0.0.1:${port}:${port}`]),
      "--add-host",
      "host.docker.internal:127.0.0.1",
      "-e",
      `LEAFWAKE_SETUP_KEY=${setupKey}`,
      "-e",
      "LEAFWAKE_MEDIA_ROOTS=/library",
      "-e",
      "LEAFWAKE_OPENID_ALLOWED_HOSTS=127.0.0.1,host.docker.internal",
      "-e",
      "LEAFWAKE_FEED_ALLOWED_HOSTS=127.0.0.1,host.docker.internal",
      "-e",
      "LEAFWAKE_SMTP_ALLOWED_HOSTS=127.0.0.1,host.docker.internal",
      "-v",
      `${join(runtime, "library")}:/library:ro`,
      "-v",
      `${join(runtime, "imports")}:/imports:ro`,
      "-v",
      `${container}-data:/data`,
      image,
    );
    await ready();
    const state =
      process.env.LEAFWAKE_QA_REUSE_VOLUME === "1"
        ? {
            ...JSON.parse(readFileSync(stateFile, "utf8")),
            origin,
            image,
            serverVersion: (await call("/status")).serverVersion,
          }
        : await seed(snapshot);
    writeFileSync(stateFile, JSON.stringify(state, null, 2));
  } else {
    if (!existing.startsWith("Up")) docker("start", container);
    await ready();
  }
  await startFixtures();
  console.log(JSON.stringify(JSON.parse(readFileSync(stateFile, "utf8"))));
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command = "up", ...flags] = process.argv.slice(2);
  if (command === "down") down();
  else if (command === "up") await up({ fresh: flags.includes("--fresh") || !existsSync(stateFile) });
  else throw new Error(`Unknown command ${command}`);
}
