import "server-only";
import { z } from "zod";
import {
  accountResponse,
  authenticate,
  createOwner,
  credentialsSchema,
  DomainError,
  passwordLogin,
  refreshSession,
  setupSchema,
} from "./accounts";
import { database, initialized, setupKey } from "./data";

const MAX_BODY = 16_384;
export function json(value: unknown, status = 200) {
  return Response.json(value, { status, headers: { "cache-control": "no-store" } });
}
export async function boundary(work: () => Promise<Response> | Response) {
  try {
    return await work();
  } catch (error) {
    if (error instanceof DomainError) return new Response(error.message, { status: error.status });
    if (error instanceof z.ZodError || error instanceof SyntaxError)
      return new Response("Invalid request", { status: 400 });
    console.error("Leafwake request failed", error instanceof Error ? error.name : "UnknownError");
    return new Response("The server could not complete this request", { status: 500 });
  }
}
function sameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin) return;
  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    throw new DomainError(403, "This browser origin is not allowed");
  }
  // Next constructs request.url with the internal listener address. Browsers use the public Host.
  if (
    origin !== parsed.origin ||
    !["http:", "https:"].includes(parsed.protocol) ||
    parsed.host !== request.headers.get("host")
  ) {
    throw new DomainError(403, "This browser origin is not allowed");
  }
}
async function body(request: Request): Promise<unknown> {
  sameOrigin(request);
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))
    throw new DomainError(415, "JSON request required");
  if (Number(request.headers.get("content-length")) > MAX_BODY)
    throw new DomainError(413, "Request too large");
  const reader = request.body?.getReader();
  if (!reader) throw new DomainError(400, "JSON request required");
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BODY) {
      await reader.cancel();
      throw new DomainError(413, "Request too large");
    }
    chunks.push(value);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}
export function serverStatus() {
  const ready = initialized();
  if (!ready) setupKey();
  return json({
    app: "Leafwake",
    serverVersion: "1.0.0-dev",
    isInit: ready,
    language: "en",
    authMethods: ["local"],
    authFormData: {},
  });
}
export function health() {
  database().prepare("SELECT 1").get();
  return json({ status: "ready", app: "Leafwake" });
}
export async function login(request: Request) {
  return boundary(async () => json(await passwordLogin(credentialsSchema.parse(await body(request)))));
}
export function refresh(request: Request) {
  return boundary(() => {
    sameOrigin(request);
    return json(refreshSession(request.headers.get("x-refresh-token")));
  });
}
export function bearer(request: Request) {
  const value = request.headers.get("authorization");
  return value?.startsWith("Bearer ") ? value.slice(7) : null;
}
export async function api(request: Request) {
  return boundary(async () => {
    const path = new URL(request.url).pathname;
    if (path === "/api/setup" && request.method === "POST") {
      if (initialized()) throw new DomainError(409, "This server is already initialized");
      const input = await body(request);
      // Missing bootstrap authority is a denied setup attempt, not malformed owner credentials.
      if (!input || typeof input !== "object" || !("setupKey" in input))
        throw new DomainError(403, "The setup key is required");
      await createOwner(setupSchema.parse(input));
      return json({ initialized: true }, 201);
    }
    const user = authenticate(bearer(request));
    if (path === "/api/me" && request.method === "GET") return json(accountResponse(user));
    if (path === "/api/authorize" && request.method === "POST")
      return json({ user: accountResponse(user), ereaderDevices: [] });
    if (path === "/api/libraries" && request.method === "GET") return json({ libraries: [] });
    throw new DomainError(404, "Not found");
  });
}
