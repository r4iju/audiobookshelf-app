import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import next from "next";
import { attachRealtime } from "./realtime.mjs";

const port = Number(process.env.PORT || 19881);
const hostname = process.env.HOSTNAME || "127.0.0.1";
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid PORT");
const dev = process.env.NODE_ENV !== "production";
// The custom entry point is explicitly packaged; Next's generated standalone server is not used.
const conf = dev
  ? undefined
  : JSON.parse(await readFile(new URL("./.next/required-server-files.json", import.meta.url), "utf8")).config;
const app = next({ dev, hostname, port, conf });
await app.prepare();
const handle = app.getRequestHandler();
const server = createServer((request, response) => {
  const origin = request.headers.origin;
  const allowedOrigin = origin && globalThis.leafwakeOriginAllowed?.(origin, request.headers.host ?? "");
  if (allowedOrigin) {
    response.setHeader("access-control-allow-origin", origin);
    response.setHeader("vary", "Origin");
    response.setHeader("access-control-allow-methods", "GET,HEAD,POST,PATCH,DELETE,OPTIONS");
    response.setHeader("access-control-allow-headers", "authorization,content-type,x-refresh-token,range");
    response.setHeader("access-control-expose-headers", "content-length,content-range,accept-ranges");
  }
  if (request.method === "OPTIONS") {
    response.statusCode = allowedOrigin ? 204 : 403;
    response.end();
    return;
  }
  handle(request, response).catch(() => {
    if (!response.headersSent) {
      response.statusCode = 500;
      response.end("Request failed");
    } else response.destroy();
  });
});
// The application bounds upload bodies to ten minutes and JSON bodies to twenty seconds.
server.requestTimeout = 660_000;
server.headersTimeout = 60_000;
let realtimeReady = false;
const basePath = conf?.basePath ?? process.env.ABS_WEB_BASE_PATH?.replace(/\/+$/, "") ?? "";
globalThis.leafwakeBasePath = basePath;
const stopRealtime = attachRealtime(server, () => realtimeReady, `${basePath}/socket.io`);
server.listen(port, hostname, async () => {
  try {
    // Load the domain through its public Next route before accepting socket authentication.
    const warmHost = hostname === "0.0.0.0" ? "127.0.0.1" : hostname === "::" ? "::1" : hostname;
    const warmAddress = warmHost.includes(":") ? `[${warmHost}]` : warmHost;
    const response = await fetch(`http://${warmAddress}:${port}${basePath}/healthz`);
    if (!response.ok || !globalThis.leafwakeRealtimeSnapshot) throw new Error("Domain not ready");
    realtimeReady = true;
    console.log(`Leafwake listening on port ${port}`);
  } catch {
    console.error("Leafwake initialization failed");
    process.exit(1);
  }
});
let stopping = false;
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    if (stopping) return;
    stopping = true;
    stopRealtime();
    const deadline = setTimeout(() => process.exit(1), 10_000);
    deadline.unref();
    server.close(async () => {
      await app.close();
      clearTimeout(deadline);
      process.exit(0);
    });
    server.closeIdleConnections();
  });
