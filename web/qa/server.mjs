// Runs an isolated, unmodified Audiobookshelf server container (the image the owner runs, 2.30.0) on loopback with a
// synthetic library and synthetic accounts. Never targets the production container or its data.
//   node qa/server.mjs up [--fresh]   start (or reuse) and seed; prints qa/.runtime/state.json
//   node qa/server.mjs down           remove the container and its config/metadata volumes
import { execFileSync } from "node:child_process";
import { existsSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const runtime = join(here, ".runtime");
const container = "abs-web-qa";
const image =
  "ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03";
export const QA_PORT = Number(process.env.ABS_QA_PORT ?? 19880);
const origin = `http://127.0.0.1:${QA_PORT}`;
const devOrigins = ["http://127.0.0.1:19881", "http://localhost:19881"];
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
  const response = await fetch(origin + path, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw new Error(`${method} ${path} -> ${response.status} ${await response.text()}`);
  const text = await response.text();
  return text && text !== "OK" ? JSON.parse(text) : null;
}

async function waitForStatus() {
  for (let attempt = 0; attempt < 120; attempt++) {
    try {
      return await call("/status");
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }
  throw new Error("QA server did not start");
}

async function login({ username, password }) {
  const response = await fetch(`${origin}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-return-tokens": "true" },
    body: JSON.stringify({ username, password }),
  });
  if (!response.ok) throw new Error(`login ${username} -> ${response.status}`);
  return (await response.json()).user.accessToken;
}

async function seed() {
  await call("/init", { method: "POST", body: { newRoot: accounts.admin } });
  const token = await login(accounts.admin);
  // Cross-origin browser access (the dev server on another port) uses the server's own allowedOrigins setting.
  await call("/api/settings", { token, method: "PATCH", body: { allowedOrigins: devOrigins } });
  const books = await call("/api/libraries", {
    token,
    method: "POST",
    body: {
      name: "Audiobooks",
      mediaType: "book",
      provider: "audible",
      folders: [{ fullPath: "/library/books" }],
      settings: { audiobooksOnly: false },
    },
  });
  const podcasts = await call("/api/libraries", {
    token,
    method: "POST",
    body: {
      name: "Podcasts",
      mediaType: "podcast",
      provider: "itunes",
      // The scanned fixtures are read-only; podcasts created through the client are written to a separate volume.
      folders: [{ fullPath: "/library/podcasts" }, { fullPath: "/podcasts" }],
    },
  });
  for (const library of [books, podcasts])
    await call(`/api/libraries/${library.id}/scan`, { token, method: "POST" });
  for (let attempt = 0; attempt < 120; attempt++) {
    const { total } = await call(`/api/libraries/${books.id}/items?limit=1`, { token });
    const podcastItems = await call(`/api/libraries/${podcasts.id}/items?limit=1`, { token });
    if (total >= 67 && podcastItems.total >= 1) break;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  const permissions = {
    download: true,
    update: true,
    delete: false,
    upload: false,
    accessAllLibraries: true,
    accessAllTags: true,
    accessExplicitContent: true,
  };
  const users = {};
  for (const [key, account] of Object.entries({ user: accounts.user, other: accounts.other })) {
    users[key] = await call("/api/users", {
      token,
      method: "POST",
      body: { ...account, type: "user", isActive: true, permissions },
    });
  }
  users.limited = await call("/api/users", {
    token,
    method: "POST",
    body: {
      ...accounts.limited,
      type: "user",
      isActive: true,
      permissions: { ...permissions, download: false, update: false, accessAllLibraries: false },
      librariesAccessible: [books.id],
    },
  });
  return {
    origin,
    libraries: { books: books.id, podcasts: podcasts.id },
    users: Object.fromEntries(Object.entries(users).map(([key, value]) => [key, value.user?.id ?? value.id])),
  };
}

async function up({ fresh }) {
  execFileSync(join(here, "make-library.sh"), { stdio: "inherit" });
  const running = docker("ps", "-a", "--filter", `name=^${container}$`, "--format", "{{.Status}}");
  if (fresh && running) down();
  if (!running || fresh) {
    docker(
      "run",
      "-d",
      "--name",
      container,
      "-p",
      `127.0.0.1:${QA_PORT}:80`,
      "-e",
      "TZ=UTC",
      // Test journeys sign in far more often than people do; only this QA server disables the login rate limit.
      "-e",
      "RATE_LIMIT_AUTH_MAX=0",
      // The local RSS feed (qa/feed.mjs) runs on the host; only that host is exempt from the server's SSRF filter.
      "--add-host",
      "host.docker.internal:host-gateway",
      "-e",
      "SSRF_REQUEST_FILTER_WHITELIST=host.docker.internal",
      "-v",
      `${join(runtime, "library")}:/library:ro`,
      "-v",
      `${container}-podcasts:/podcasts`,
      // Named volumes: SQLite on a bind mount through the VM's file sharing fails to open after the directory is recreated.
      "-v",
      `${container}-config:/config`,
      "-v",
      `${container}-metadata:/metadata`,
      image,
    );
  } else if (!running.startsWith("Up")) {
    docker("start", container);
  }
  const status = await waitForStatus();
  let state;
  if (!status.isInit) {
    state = { ...(await seed()), serverVersion: status.serverVersion, image };
    writeFileSync(join(runtime, "state.json"), JSON.stringify(state, null, 2));
  }
  console.log(JSON.stringify(state ?? { origin, serverVersion: status.serverVersion, reused: true }));
}

function down() {
  for (const args of [
    ["rm", "-f", container],
    ["volume", "rm", "-f", `${container}-config`, `${container}-metadata`, `${container}-podcasts`],
  ]) {
    try {
      docker(...args);
    } catch {}
  }
  for (const leftover of ["config", "metadata", "state.json"])
    rmSync(join(runtime, leftover), { recursive: true, force: true });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command = "up", ...flags] = process.argv.slice(2);
  if (command === "down") down();
  else if (command === "up")
    await up({ fresh: flags.includes("--fresh") || !existsSync(join(runtime, "state.json")) });
  else throw new Error(`Unknown command ${command}`);
}
