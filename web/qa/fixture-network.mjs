// Checks that the QA server reaches its synthetic fixtures (OpenID, feed, mail) without stalls, from inside the server's
// own network namespace and through the same addresses the server uses. Runs repeated concurrent requests and fails on
// any that take a second or more: Linux retransmits an unanswered connection attempt after one second, so a single
// dropped connection attempt on the way to a fixture shows up here instead of as a 10-68 s timeout in a journey.
//   node qa/fixture-network.mjs [seconds]   the QA server (qa/server.mjs up) and its fixtures must be running
import { execFileSync, spawn } from "node:child_process";
import { connect } from "node:net";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const STALL_MS = 1000;
const GIVE_UP_MS = 15_000;
const LOOPS_PER_FIXTURE = 2;
// Paced like real fixture traffic: unpaced loops exhaust the Mac's ephemeral ports and measure that instead.
const PAUSE_MS = 100;
const host = "host.docker.internal";
const ports = {
  oidc: Number(process.env.ABS_QA_OIDC_PORT ?? 19884),
  feed: Number(process.env.ABS_QA_FEED_PORT ?? 19885),
  mail: Number(process.env.ABS_QA_MAIL_PORT ?? 19886),
};
const http = (path) => `GET ${path} HTTP/1.1\r\nHost: ${host}\r\nConnection: close\r\n\r\n`;
const fixtures = [
  { name: "oidc", port: ports.oidc, send: http("/.well-known/openid-configuration"), expect: "HTTP/1.1 200" },
  { name: "feed", port: ports.feed, send: http("/feed.xml"), expect: "HTTP/1.1 200" },
  { name: "mail", port: ports.mail, send: null, expect: "220" },
];

function attempt({ port, send, expect }) {
  const started = performance.now();
  return new Promise((resolve) => {
    let received = "";
    const socket = connect({ host, port });
    const finish = (error) => {
      socket.destroy();
      resolve({ ms: performance.now() - started, error });
    };
    socket.setTimeout(GIVE_UP_MS, () => finish("timed out"));
    socket.on("error", (error) => finish(error.code ?? error.message));
    socket.on("connect", () => send && socket.write(send));
    socket.on("data", (chunk) => {
      received += chunk;
      if (received.length >= expect.length)
        finish(
          received.startsWith(expect) ? undefined : `unexpected ${JSON.stringify(received.slice(0, 40))}`,
        );
    });
    socket.on("end", () => finish(`closed after ${JSON.stringify(received.slice(0, 40))}`));
  });
}

async function probe(seconds) {
  const deadline = performance.now() + seconds * 1000;
  const results = Object.fromEntries(fixtures.map(({ name }) => [name, []]));
  await Promise.all(
    fixtures.flatMap((fixture) =>
      Array.from({ length: LOOPS_PER_FIXTURE }, async () => {
        while (performance.now() < deadline) {
          results[fixture.name].push(await attempt(fixture));
          await new Promise((resolve) => setTimeout(resolve, PAUSE_MS));
        }
      }),
    ),
  );
  let failed = false;
  for (const [name, runs] of Object.entries(results)) {
    const sorted = runs.map((run) => run.ms).sort((a, b) => a - b);
    const bad = runs.filter((run) => run.error || run.ms >= STALL_MS);
    failed ||= bad.length > 0 || runs.length === 0;
    const kinds = {};
    for (const run of bad) {
      const kind = run.error ?? `slow ${2 ** Math.floor(Math.log2(run.ms / 1000))}s+`;
      kinds[kind] = (kinds[kind] ?? 0) + 1;
    }
    console.log(
      `${name} ${host}:${ports[name]} attempts ${runs.length} median ${Math.round(sorted[sorted.length >> 1] ?? 0)} ms` +
        ` max ${Math.round(sorted.at(-1) ?? 0)} ms failed ${bad.length} ${JSON.stringify(kinds)}`,
    );
  }
  return failed;
}

if (process.argv[2] === "--inside") {
  process.exit((await probe(Number(process.argv[3]))) ? 1 : 0);
} else if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { container, docker, env, image } = await import("./server.mjs");
  const seconds = Number(process.argv[2] ?? 60);
  if (!docker("ps", "--filter", `name=^${container}$`, "--format", "{{.Names}}"))
    throw new Error(`${container} is not running; start it with node qa/server.mjs up`);
  const name = `${container}-network-probe`;
  const child = spawn(
    "docker",
    [
      "run",
      "--rm",
      "--name",
      name,
      // The server's namespace: its loopback, its /etc/hosts entries and its route to the fixtures.
      "--network",
      `container:${container}`,
      ...Object.entries(ports).flatMap(([key, port]) => ["-e", `ABS_QA_${key.toUpperCase()}_PORT=${port}`]),
      "-v",
      `${here}:/qa:ro`,
      "--entrypoint",
      "node",
      image,
      "/qa/fixture-network.mjs",
      "--inside",
      String(seconds),
    ],
    { env, stdio: "inherit" },
  );
  const stop = () => {
    try {
      execFileSync("docker", ["rm", "-f", name], { env, stdio: "ignore" });
    } catch {}
  };
  process.on("SIGINT", () => {
    stop();
    process.exit(130);
  });
  const code = await new Promise((resolve) => child.on("exit", resolve));
  console.log(code === 0 ? "No fixture stalls" : "Fixture stalls or failures (see above)");
  process.exit(code ?? 1);
}
