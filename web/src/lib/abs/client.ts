import { z } from "zod";
import { type AuthState, bearerOf, type Connection } from "./connection";

export type AbsErrorKind =
  | "network"
  | "unauthorized"
  | "forbidden"
  | "not-found"
  | "http"
  | "invalid-response";

export class AbsError extends Error {
  constructor(
    readonly kind: AbsErrorKind,
    message: string,
    readonly status?: number,
    /** The server's own plain-text explanation, when it gives one. */
    readonly detail?: string,
  ) {
    super(message);
    this.name = "AbsError";
  }
}

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export interface AbsClientOptions {
  connection: Connection;
  fetcher?: Fetcher;
  /** Persists rotated credentials before any request uses them. */
  saveAuth: (auth: AuthState) => void;
  /** Re-reads credentials another tab may have rotated meanwhile. */
  loadAuth?: () => AuthState | null;
}

const refreshResponseSchema = z.object({
  user: z.object({
    accessToken: z.string().nullish(),
    refreshToken: z.string().nullish(),
    token: z.string().nullish(),
  }),
});

interface RequestOptions {
  method?: "GET" | "POST" | "PATCH" | "DELETE";
  body?: unknown;
  file?: Blob;
  signal?: AbortSignal;
  /** Runs before the request is sent again with a renewed sign-in; throwing stops it. */
  beforeRetry?: () => Promise<void>;
}

export type AbsClient = ReturnType<typeof createAbsClient>;

export function createAbsClient({
  connection,
  fetcher = (...args) => fetch(...args),
  saveAuth,
  loadAuth,
}: AbsClientOptions) {
  let auth = connection.auth;
  let refreshing: Promise<AuthState> | null = null;

  const url = (path: string) => (/^https?:\/\//.test(path) ? path : `${connection.serverUrl}${path}`);

  async function transport(path: string, options: RequestOptions, bearer: string) {
    try {
      return await fetcher(url(path), {
        method: options.method ?? "GET",
        headers: {
          Authorization: `Bearer ${bearer}`,
          ...(options.file
            ? { "Content-Type": options.file.type || "application/octet-stream" }
            : options.body === undefined
              ? {}
              : { "Content-Type": "application/json" }),
        },
        body: options.file ?? (options.body === undefined ? undefined : JSON.stringify(options.body)),
        // Bearer tokens only: the server answers cross-origin preflights with a wildcard that browsers reject for
        // credentialed requests.
        credentials: "omit",
        signal: options.signal,
      });
    } catch (error) {
      if (options.signal?.aborted) throw error;
      throw new AbsError("network", `Could not reach ${connection.serverUrl}`);
    }
  }

  async function rotate(failedBearer: string): Promise<AuthState> {
    const stored = loadAuth?.();
    if (stored && bearerOf(stored) !== failedBearer) return stored;
    const current = stored ?? auth;
    if (current.kind === "legacy")
      throw new AbsError("unauthorized", "The server no longer accepts this sign-in.", 401);
    let response: Response;
    try {
      response = await fetcher(url("/auth/refresh"), {
        method: "POST",
        headers: { "x-refresh-token": current.refreshToken },
        credentials: "omit",
      });
    } catch {
      throw new AbsError("network", `Could not reach ${connection.serverUrl}`);
    }
    if (response.status === 401 || response.status === 403) {
      throw new AbsError("unauthorized", "The server no longer accepts this sign-in.", response.status);
    }
    if (!response.ok)
      throw new AbsError("http", `Token renewal failed (${response.status})`, response.status);
    const parsed = refreshResponseSchema.safeParse(await response.json().catch(() => null));
    const accessToken = parsed.success ? parsed.data.user.accessToken : null;
    if (!accessToken) throw new AbsError("invalid-response", "Token renewal returned no access token");
    const next: AuthState = {
      kind: "token",
      accessToken,
      refreshToken: parsed.data?.user.refreshToken ?? current.refreshToken,
    };
    saveAuth(next);
    return next;
  }

  function refresh(failedBearer: string) {
    refreshing ??= withLock(`abs-refresh:${connection.id}`, () => rotate(failedBearer)).finally(() => {
      refreshing = null;
    });
    return refreshing;
  }

  async function send(path: string, options: RequestOptions = {}): Promise<Response> {
    const bearer = bearerOf(auth);
    let response = await transport(path, options, bearer);
    if (response.status === 401) {
      auth = await refresh(bearer);
      await options.beforeRetry?.();
      response = await transport(path, options, bearerOf(auth));
    }
    if (response.ok) return response;
    if (response.status === 401)
      throw new AbsError("unauthorized", "The server no longer accepts this sign-in.", 401);
    if (response.status === 403)
      throw new AbsError("forbidden", "This account is not allowed to do that.", 403);
    if (response.status === 404) throw new AbsError("not-found", "Not found on the server.", 404);
    const detail = response.headers.get("Content-Type")?.startsWith("text/plain")
      ? (await response.text()).slice(0, 300)
      : undefined;
    throw new AbsError(
      "http",
      `The server responded with ${response.status}.`,
      response.status,
      detail || undefined,
    );
  }

  async function parse<T extends z.ZodType>(response: Response, schema: T): Promise<z.infer<T>> {
    const text = await response.text();
    let value: unknown = null;
    try {
      value = text ? JSON.parse(text) : null;
    } catch {
      throw new AbsError("invalid-response", "The server returned something other than JSON.");
    }
    const parsed = schema.safeParse(value);
    if (!parsed.success)
      throw new AbsError(
        "invalid-response",
        `Unexpected server response: ${parsed.error.issues[0]?.message}`,
      );
    return parsed.data;
  }

  return {
    connection,
    get bearer() {
      return bearerOf(auth);
    },
    url,
    get: async <T extends z.ZodType>(path: string, schema: T, signal?: AbortSignal) =>
      parse(await send(path, { signal }), schema),
    send: async <T extends z.ZodType>(
      method: "POST" | "PATCH" | "DELETE",
      path: string,
      body: unknown,
      schema: T,
      signal?: AbortSignal,
      beforeRetry?: () => Promise<void>,
    ) => parse(await send(path, { method, body, signal, beforeRetry }), schema),
    /** For endpoints that answer "OK" or nothing. */
    command: async (
      method: "GET" | "POST" | "PATCH" | "DELETE",
      path: string,
      body?: unknown,
      beforeRetry?: () => Promise<void>,
    ) => {
      await send(path, { method, body, beforeRetry });
    },
    upload: async <T extends z.ZodType>(path: string, file: Blob, schema: T, signal?: AbortSignal) =>
      parse(await send(path, { method: "POST", file, signal }), schema),
    blob: async (path: string, signal?: AbortSignal) => (await send(path, { signal })).blob(),
  };
}

/** Runs the task while holding a lock shared by this origin's tabs, where the browser offers one. */
export async function withLock<T>(name: string, task: () => Promise<T>): Promise<T> {
  if (typeof navigator !== "undefined" && navigator.locks) return navigator.locks.request(name, task);
  return task();
}
