// Seeds the existing web QA stack on stock 2.30.0 (qa/server.mjs up --fresh), then replaces ONLY the owned main
// container with an actual packaged candidate image, keeping its volumes, published ports, extra hosts, env and library
// mount. It restarts the owned fixtures through `qa/server.mjs up` (no --fresh) so they join the new main container's
// network. No other container is touched. Cached local images only (--pull=never).
//   ABS_QA_CONTAINER=abs-server-browser-qa ABS_QA_PORT=19890 ABS_QA_OIDC_PORT=19894 ABS_QA_FEED_PORT=19895 \
//   ABS_QA_MAIL_PORT=19896 node swap-to-candidate.mjs <web dir> <evidence dir> stock|candidate|session
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";

const STOCK = "ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03";
// Each image is pinned by ID and by the files it replaces; anything else stops the run.
const images = {
  stock: {
    ref: STOCK,
    id: "sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03",
    files: {
      "/app/server/models/User.js": "2174eec7b50b43ed3e0da55c4e54edaa90f9f98c30cefb9b4819430b744f6a1d",
      "/app/server/managers/PlaybackSessionManager.js":
        "e196eea6e727fbe634a985ee475f5f50782069e6debc4a81f7a2517114885428",
    },
  },
  // Superseded: first progress created by PATCH within 10 s of the end is stored finished.
  candidate: {
    ref: "abs-server-candidate:2.30.0-usercache-firstprogress",
    id: "sha256:c649a2bd3bd177a79e414a08729009f9f1a50156271d008c35a4bb52e81d9abd",
    files: { "/app/server/models/User.js": "15ee2c33d88fab0e6e8e43d9ffe3c7eddb272ea6ba3f11906cabeb455c0ffac4" },
  },
  session: {
    ref: "abs-server-candidate:2.30.0-usercache-firstprogress-session",
    id: "sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4",
    files: {
      "/app/server/models/User.js": "d36db80057337ae071a436a7753cb3aa024e97373e8d4cc9e805d1c048486097",
      "/app/server/managers/PlaybackSessionManager.js":
        "a140b5679a81e8b48b3485f6bd7e2bee0c20fb6bd79819a61279e465c8f685ae",
    },
  },
};

const [webDir, evidence, mode] = process.argv.slice(2);
const wanted = images[mode];
if (!webDir || !evidence || !wanted) throw new Error("usage: <web dir> <evidence dir> stock|candidate|session");
const env = {
  ...process.env,
  DOCKER_HOST: process.env.DOCKER_HOST ?? `unix://${process.env.HOME}/.colima/default/docker.sock`,
};
const container = env.ABS_QA_CONTAINER;
const port = Number(env.ABS_QA_PORT);
if (container !== "abs-server-browser-qa" || port !== 19890) throw new Error("owned container/port env not set");
const clientOrigins = ["http://127.0.0.1:3191", "http://localhost:3191"];
const docker = (...args) => execFileSync("docker", args, { env, encoding: "utf8" }).trim();
const node = (...args) => execFileSync("node", args, { env, cwd: webDir, stdio: "inherit" });
const log = (...m) => console.log("[runner]", ...m);

// Fail before anything starts if an image is missing or not the pinned one; never pull.
for (const image of new Set([images.stock, wanted])) {
  const id = docker("image", "inspect", "--format", "{{.Id}}", image.ref);
  if (id !== image.id) throw new Error(`${image.ref} is ${id}, not ${image.id}`);
}

log("seeding fresh owned stock stack");
node("qa/server.mjs", "up", "--fresh");

const before = JSON.parse(docker("inspect", container))[0];
writeFileSync(join(evidence, "main-container-stock-inspect.json"), JSON.stringify(before, null, 2));

if (wanted !== images.stock) {
  const imageEnv = new Set(JSON.parse(docker("image", "inspect", "--format", "{{json .Config.Env}}", STOCK)));
  const runEnv = before.Config.Env.filter((entry) => !imageEnv.has(entry));
  const ports = Object.entries(before.HostConfig.PortBindings).flatMap(([inner, binds]) =>
    binds.map((b) => ["-p", `${b.HostIp}:${b.HostPort}:${inner.replace("/tcp", "")}`]),
  );
  const mounts = before.Mounts.map((m) => [
    "-v",
    `${m.Type === "volume" ? m.Name : m.Source}:${m.Destination}${m.RW ? "" : ":ro"}`,
  ]);
  const hosts = (before.HostConfig.ExtraHosts ?? []).map((h) => ["--add-host", h]);
  const args = [
    "run",
    "-d",
    "--pull=never",
    "--name",
    container,
    ...ports.flat(),
    ...runEnv.flatMap((e) => ["-e", e]),
    ...hosts.flat(),
    ...mounts.flat(),
    wanted.ref,
  ];
  log("replacing owned main container:", args.join(" "));
  docker("rm", "-f", container);
  docker(...args);
  log("restarting owned fixtures on the new main container's network (up, no --fresh)");
  node("qa/server.mjs", "up");
}

const after = JSON.parse(docker("inspect", container))[0];
writeFileSync(join(evidence, `main-container-${mode}-inspect.json`), JSON.stringify(after, null, 2));
if (after.Image !== wanted.id) throw new Error(`running image ${after.Image}, not ${wanted.id}`);
const runningFiles = {};
for (const [file, sha] of Object.entries(wanted.files)) {
  runningFiles[file] = docker("exec", container, "sha256sum", file).split(/\s+/)[0];
  if (runningFiles[file] !== sha) throw new Error(`running ${file} ${runningFiles[file]}, not ${sha}`);
}

// The production client on 3191 is a separate origin: add it on this synthetic server only, as qa-admin.
const origin = `http://127.0.0.1:${port}`;
const login = await fetch(`${origin}/login`, {
  method: "POST",
  headers: { "Content-Type": "application/json", "x-return-tokens": "true" },
  body: JSON.stringify({ username: "qa-admin", password: "qa-admin-pass" }),
});
const session = await login.json();
const auth = { Authorization: `Bearer ${session.user.accessToken}` };
const allowedOrigins = [...new Set([...(session.serverSettings.allowedOrigins ?? []), ...clientOrigins])];
const patched = await fetch(`${origin}/api/settings`, {
  method: "PATCH",
  headers: { ...auth, "Content-Type": "application/json" },
  body: JSON.stringify({ allowedOrigins }),
});
if (!patched.ok) throw new Error(`PATCH settings ${patched.status}`);
const status = await (await fetch(`${origin}/status`)).json();
const record = {
  mode,
  container,
  requestedImage: wanted.ref,
  runningImageId: after.Image,
  runningFiles,
  serverVersion: status.serverVersion,
  allowedOrigins,
  fixtures: docker("ps", "--filter", `name=^${container}-`, "--format", "{{.Names}} {{.Image}}").split("\n"),
  recordedAt: new Date().toISOString(),
};
writeFileSync(join(evidence, `actual-server-${mode}.json`), JSON.stringify(record, null, 2));
log(JSON.stringify(record, null, 2));
