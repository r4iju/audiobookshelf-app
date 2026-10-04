import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import next from "next";

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
  handle(request, response).catch(() => {
    if (!response.headersSent) {
      response.statusCode = 500;
      response.end("Request failed");
    } else response.destroy();
  });
});
server.requestTimeout = 60_000;
server.listen(port, hostname, () => console.log(`Leafwake listening on port ${port}`));
let stopping = false;
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    if (stopping) return;
    stopping = true;
    const deadline = setTimeout(() => process.exit(1), 10_000);
    deadline.unref();
    server.close(async () => {
      await app.close();
      clearTimeout(deadline);
      process.exit(0);
    });
    server.closeIdleConnections();
  });
