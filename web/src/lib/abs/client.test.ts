import { describe, expect, it } from "vitest";
import { z } from "zod";
import { AbsError, createAbsClient } from "./client";
import type { Connection } from "./connection";

const connection: Connection = {
  id: "c1",
  serverUrl: "https://abs.example/sub",
  username: "qa",
  userId: "u1",
  auth: { kind: "token", accessToken: "old", refreshToken: "r1" },
};

type Handler = (request: Request) => Response | Promise<Response>;

function server(handler: Handler) {
  const seen: Request[] = [];
  const fetcher = async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init);
    seen.push(request);
    return handler(request);
  };
  return { seen, fetcher };
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const ok = z.object({ ok: z.boolean() });

describe("AbsClient", () => {
  it("keeps the server's own explanation of a refused request", async () => {
    const { fetcher } = server(
      () => new Response("Slug already in use", { status: 400, headers: { "Content-Type": "text/plain" } }),
    );
    const client = createAbsClient({ connection, fetcher, saveAuth: () => {} });
    const error = await client.command("POST", "/api/feeds/item/i1/open", {}).catch((caught) => caught);
    expect(error).toBeInstanceOf(AbsError);
    expect(error).toMatchObject({ kind: "http", status: 400, detail: "Slug already in use" });
  });

  it("resolves paths under the server subpath with the bearer token", async () => {
    const { seen, fetcher } = server(() => json(200, { ok: true }));
    const client = createAbsClient({ connection, fetcher, saveAuth: () => {} });
    await expect(client.get("/api/me", ok)).resolves.toEqual({ ok: true });
    expect(seen[0]?.url).toBe("https://abs.example/sub/api/me");
    expect(seen[0]?.headers.get("Authorization")).toBe("Bearer old");
  });

  it("refreshes once for concurrent expired requests and persists the rotated tokens before retrying", async () => {
    let refreshes = 0;
    const saved: unknown[] = [];
    const { seen, fetcher } = server(async (request) => {
      if (request.url.endsWith("/auth/refresh")) {
        refreshes++;
        expect(request.headers.get("x-refresh-token")).toBe("r1");
        await new Promise((resolve) => setTimeout(resolve, 10));
        return json(200, { user: { accessToken: "new", refreshToken: "r2" } });
      }
      return request.headers.get("Authorization") === "Bearer new" ? json(200, { ok: true }) : json(401, {});
    });
    const client = createAbsClient({ connection, fetcher, saveAuth: (auth) => saved.push(auth) });
    const results = await Promise.all([client.get("/api/a", ok), client.get("/api/b", ok)]);
    expect(results).toEqual([{ ok: true }, { ok: true }]);
    expect(refreshes).toBe(1);
    expect(saved).toEqual([{ kind: "token", accessToken: "new", refreshToken: "r2" }]);
    expect(seen.filter((request) => request.headers.get("Authorization") === "Bearer new")).toHaveLength(2);
  });

  it("reports a rejected refresh as unauthorized without discarding the connection", async () => {
    const saved: unknown[] = [];
    const { fetcher } = server((request) =>
      request.url.endsWith("/auth/refresh") ? json(401, { error: "Invalid" }) : json(401, {}),
    );
    const client = createAbsClient({ connection, fetcher, saveAuth: (auth) => saved.push(auth) });
    const error = await client.get("/api/me", ok).catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(AbsError);
    expect((error as AbsError).kind).toBe("unauthorized");
    expect(saved).toEqual([]);
  });

  it("treats a transport failure as offline, not as a sign-out", async () => {
    const { fetcher } = server(() => {
      throw new TypeError("Failed to fetch");
    });
    const client = createAbsClient({ connection, fetcher, saveAuth: () => {} });
    const error = await client.get("/api/me", ok).catch((caught: unknown) => caught);
    expect((error as AbsError).kind).toBe("network");
  });

  it("rejects a response that does not match the expected contract", async () => {
    const { fetcher } = server(() => json(200, { items: [] }));
    const client = createAbsClient({ connection, fetcher, saveAuth: () => {} });
    const error = await client.get("/api/me", ok).catch((caught: unknown) => caught);
    expect((error as AbsError).kind).toBe("invalid-response");
  });
});
