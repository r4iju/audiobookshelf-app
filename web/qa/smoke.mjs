// Read-only check of a deployed client and the server behind the same origin (docs/DEPLOYMENT.md). It only sends
// GET requests, signs in to nothing and changes nothing, so it may be pointed at a real deployment.
//   node qa/smoke.mjs <origin> [base path, default /web]     for example: node qa/smoke.mjs https://abs.example
const [origin, basePath = "/web"] = process.argv.slice(2);
if (!origin) {
  console.error("usage: node qa/smoke.mjs <origin> [base path]");
  process.exit(2);
}
const base = new URL(origin).origin;

const checks = [
  [
    `the client's sign-in page at ${basePath}/connect`,
    async () => {
      const response = await fetch(`${base}${basePath}/connect`);
      if (response.status !== 200) return `answered ${response.status}`;
      if (response.headers.get("x-powered-by"))
        return `sends x-powered-by: ${response.headers.get("x-powered-by")}`;
      const html = await response.text();
      const script = html.match(/<script[^>]+src="([^"]+\/_next\/static\/[^"]+\.js)"/)?.[1];
      if (!script) return "names no script of the client";
      const asset = new URL(script, base);
      if (asset.origin !== base) return `loads its scripts from ${asset.origin}`;
      const loaded = await fetch(asset);
      return loaded.status === 200 ? null : `its script ${asset.pathname} answered ${loaded.status}`;
    },
  ],
  [
    "the server's status on the same origin",
    async () => {
      const response = await fetch(`${base}/status`);
      if (response.status !== 200) return `answered ${response.status}`;
      const status = await response.json().catch(() => null);
      if (!status?.serverVersion) return "is not an Audiobookshelf status";
      console.log(`  server ${status.serverVersion}`);
      return null;
    },
  ],
  [
    "the live updates channel through the proxy",
    async () => {
      const response = await fetch(`${base}/socket.io/?EIO=4&transport=polling`);
      const body = await response.text();
      return response.status === 200 && body.includes('"sid"') ? null : `answered ${response.status}`;
    },
  ],
  [
    "the server's own interface at /",
    async () => {
      const response = await fetch(`${base}/`, { redirect: "manual" });
      return response.status < 400 ? null : `answered ${response.status}`;
    },
  ],
];

let failed = 0;
for (const [name, check] of checks) {
  const problem = await check().catch((error) => error.cause?.code ?? error.message);
  console.log(`${problem ? "FAIL" : "ok  "} ${name}${problem ? `: ${problem}` : ""}`);
  if (problem) failed += 1;
}
console.log(
  failed
    ? `${failed} of ${checks.length} checks failed`
    : `All ${checks.length} checks passed. Now by hand: sign in at ${base}${basePath}, play a book for a minute, and see its progress in the server's own interface.`,
);
process.exit(failed ? 1 : 0);
