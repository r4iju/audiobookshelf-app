// Runs an isolated, unmodified Audiobookshelf server container (the image the owner runs, 2.30.0) on loopback with a
// synthetic library and synthetic accounts. Never targets the production container or its data.
//   node qa/server.mjs up [--fresh]   start (or reuse) and seed, and (re)start the feed, mail and OpenID fixtures beside
//                                     it; prints qa/.runtime/state.json
//   node qa/server.mjs down           remove the containers and the server's config/metadata volumes
import { execFileSync } from "node:child_process";
import { existsSync, rmSync, writeFileSync } from "node:fs";
import { connect } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { FEED_PORT } from "./feed.mjs";
import { MAIL_PORT } from "./mail.mjs";
import { OIDC_PORT } from "./oidc.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const runtime = join(here, ".runtime");
export const container = process.env.ABS_QA_CONTAINER ?? "abs-web-qa";
export const image =
  "ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03";
export const QA_PORT = Number(process.env.ABS_QA_PORT ?? 19880);
const origin = `http://127.0.0.1:${QA_PORT}`;
const devOrigins = ["http://127.0.0.1:19881", "http://localhost:19881"];
const fixtures = { feed: FEED_PORT, mail: MAIL_PORT, oidc: OIDC_PORT };
const fixtureHost = "host.docker.internal:127.0.0.1";
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
      // The fixtures share this container's network (startFixtures); the browser reaches them on the same loopback ports.
      ...Object.values(fixtures).flatMap((port) => ["-p", `127.0.0.1:${port}:${port}`]),
      "-e",
      "TZ=UTC",
      // Test journeys sign in far more often than people do; only this QA server disables the login rate limit.
      "-e",
      "RATE_LIMIT_AUTH_MAX=0",
      // The server reaches its fixtures by the name they publish (host.docker.internal), resolved to its own loopback.
      // Through the host gateway, the VM's user-mode network drops connection attempts whenever ten of its outbound
      // connections from any container are still being set up, which stalled journeys for 10-68 s
      // (node qa/fixture-network.mjs). Only this name is exempt from the server's SSRF filter.
      "--add-host",
      fixtureHost,
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
  } else if (
    !docker("inspect", "--format", "{{json .HostConfig.ExtraHosts}}", container).includes(fixtureHost)
  ) {
    throw new Error(`${container} still reaches its fixtures through the host; recreate it with up --fresh`);
  } else if (!running.startsWith("Up")) {
    docker("start", container);
  }
  await startFixtures();
  const status = await waitForStatus();
  let state;
  if (!status.isInit) {
    state = { ...(await seed()), serverVersion: status.serverVersion, image };
    writeFileSync(join(runtime, "state.json"), JSON.stringify(state, null, 2));
  }
  console.log(JSON.stringify(state ?? { origin, serverVersion: status.serverVersion, reused: true }));
}

const fixtureContainer = (name) => `${container}-${name}`;

// A published port accepts connections before the fixture behind it does, so readiness is the fixture's own answer.
const greetings = { feed: "HTTP/1.1 200", mail: "220", oidc: "HTTP/1.1 200" };
const requests = { feed: "/feed.xml", oidc: "/.well-known/openid-configuration" };

function answers(name, port) {
  return new Promise((resolve) => {
    let received = "";
    const socket = connect({ host: "127.0.0.1", port }, () => {
      if (requests[name])
        socket.write(`GET ${requests[name]} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n`);
    });
    const finish = (ok) => {
      socket.destroy();
      resolve(ok);
    };
    socket.setTimeout(2000, () => finish(false));
    socket.on("data", (chunk) => {
      received += chunk;
      if (received.length >= greetings[name].length) finish(received.startsWith(greetings[name]));
    });
    socket.on("error", () => finish(false));
    socket.on("end", () => finish(false));
  });
}

// Recreated on every start: a container sharing the server's network loses it when the server container restarts.
async function startFixtures() {
  for (const [name, port] of Object.entries(fixtures)) {
    try {
      docker("rm", "-f", fixtureContainer(name));
    } catch {}
    docker(
      "run",
      "-d",
      "--name",
      fixtureContainer(name),
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
  for (const [name, port] of Object.entries(fixtures)) {
    let attempt = 0;
    while (!(await answers(name, port))) {
      if (++attempt === 60) throw new Error(`QA ${name} fixture did not start on 127.0.0.1:${port}`);
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }
}

function down() {
  for (const args of [
    ["rm", "-f", ...Object.keys(fixtures).map(fixtureContainer)],
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
