import { z } from "zod";
import { type AuthState, type Connection, connectionId, normalizeServerAddress } from "./connection";
import { type LoginResponse, loginResponseSchema, type ServerStatus, statusSchema } from "./schemas";
import { sha256 } from "./sha256";

type Fetcher = typeof fetch;

export type ProbeFailure = "invalid-address" | "unreachable" | "not-audiobookshelf" | "not-initialized";
export type ProbeResult =
  | { ok: true; serverUrl: string; status: ServerStatus }
  | { ok: false; reason: ProbeFailure; serverUrl?: string };

async function fetchStatus(serverUrl: string, fetcher: Fetcher): Promise<ProbeResult> {
  let response: Response;
  try {
    response = await fetcher(`${serverUrl}/status`, {
      credentials: "omit",
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    return { ok: false, reason: "unreachable", serverUrl };
  }
  const parsed = statusSchema.safeParse(await response.json().catch(() => null));
  if (!response.ok || !parsed.success) return { ok: false, reason: "not-audiobookshelf", serverUrl };
  if (!parsed.data.isInit) return { ok: false, reason: "not-initialized", serverUrl };
  return { ok: true, serverUrl, status: parsed.data };
}

/** Like the legacy app: an address typed without a scheme tries https first, then http on a transport failure. */
export async function probeServer(input: string, fetcher: Fetcher = fetch): Promise<ProbeResult> {
  const address = normalizeServerAddress(input);
  if (!address.ok) return { ok: false, reason: "invalid-address" };
  const result = await fetchStatus(address.url, fetcher);
  if (!result.ok && result.reason === "unreachable" && address.assumedScheme) {
    return fetchStatus(address.url.replace(/^https:/, "http:"), fetcher);
  }
  return result;
}

export type LoginFailure =
  | "invalid-credentials"
  | "rate-limited"
  | "unreachable"
  | "server-error"
  | "invalid-response";
export type LoginResult =
  | { ok: true; connection: Connection; login: LoginResponse }
  | { ok: false; reason: LoginFailure; status?: number };

function toConnection(
  serverUrl: string,
  login: LoginResponse,
  serverVersion: string | undefined,
): Connection | null {
  const { user } = login;
  let auth: AuthState;
  if (user.accessToken && user.refreshToken)
    auth = { kind: "token", accessToken: user.accessToken, refreshToken: user.refreshToken };
  else if (user.token) auth = { kind: "legacy", token: user.token };
  else return null;
  return {
    id: connectionId(serverUrl, user.username),
    serverUrl,
    username: user.username,
    userId: user.id,
    serverVersion: login.serverSettings?.version ?? serverVersion,
    serverLanguage: login.serverSettings?.language ?? undefined,
    auth,
  };
}

async function readLogin(
  response: Response,
  serverUrl: string,
  serverVersion?: string,
): Promise<LoginResult> {
  if (response.status === 401) return { ok: false, reason: "invalid-credentials", status: 401 };
  if (response.status === 429) return { ok: false, reason: "rate-limited", status: 429 };
  if (!response.ok) return { ok: false, reason: "server-error", status: response.status };
  const parsed = loginResponseSchema.safeParse(await response.json().catch(() => null));
  const connection = parsed.success ? toConnection(serverUrl, parsed.data, serverVersion) : null;
  if (!parsed.success || !connection) return { ok: false, reason: "invalid-response" };
  return { ok: true, connection, login: parsed.data };
}

export async function passwordLogin(
  serverUrl: string,
  username: string,
  password: string,
  serverVersion?: string,
  fetcher: Fetcher = fetch,
) {
  let response: Response;
  try {
    response = await fetcher(`${serverUrl}/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-return-tokens": "true" },
      body: JSON.stringify({ username, password }),
      credentials: "omit",
    });
  } catch {
    return { ok: false, reason: "unreachable" } satisfies LoginResult;
  }
  return readLogin(response, serverUrl, serverVersion);
}

// OpenID uses the server's PKCE ("mobile") flow: the browser is sent to the provider through the server, the
// provider returns to the server, and the server redirects to this client's callback page, which must be listed in
// the server's "Allowed mobile redirect URIs". The final exchange needs the server's session cookie, so it only works
// when this client is served from the server's origin.
export const pendingOpenIdSchema = z.object({
  serverUrl: z.string(),
  state: z.string(),
  verifier: z.string(),
  redirectUri: z.string(),
  returnTo: z.string().default("/"),
});
export type PendingOpenId = z.infer<typeof pendingOpenIdSchema>;

function base64Url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

export async function startOpenId(
  serverUrl: string,
  redirectUri: string,
  returnTo: string,
): Promise<{ url: string; pending: PendingOpenId }> {
  const verifier = base64Url(crypto.getRandomValues(new Uint8Array(32)));
  const state = base64Url(crypto.getRandomValues(new Uint8Array(16)));
  const bytes = new TextEncoder().encode(verifier);
  const challenge = base64Url(
    crypto.subtle ? new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)) : sha256(bytes),
  );
  const query = new URLSearchParams({
    code_challenge: challenge,
    code_challenge_method: "S256",
    redirect_uri: redirectUri,
    client_id: "Audiobookshelf-Web",
    response_type: "code",
    state,
  });
  return {
    url: `${serverUrl}/auth/openid?${query}`,
    pending: { serverUrl, state, verifier, redirectUri, returnTo },
  };
}

export async function completeOpenId(
  pending: PendingOpenId,
  params: URLSearchParams,
  fetcher: Fetcher = fetch,
): Promise<
  LoginResult | { ok: false; reason: "state-mismatch" | "provider-error" | "rejected"; detail?: string }
> {
  if (params.get("state") !== pending.state) return { ok: false, reason: "state-mismatch" };
  const error = params.get("error");
  if (error) return { ok: false, reason: "provider-error", detail: error };
  const code = params.get("code");
  if (!code) return { ok: false, reason: "state-mismatch" };
  const query = new URLSearchParams({ state: pending.state, code, code_verifier: pending.verifier });
  let response: Response;
  try {
    response = await fetcher(`${pending.serverUrl}/auth/openid/callback?${query}`, {
      credentials: "same-origin",
    });
  } catch {
    return { ok: false, reason: "unreachable" };
  }
  // The server reports a failed exchange by sending the browser to its own login page with the error.
  const refused = response.redirected ? new URL(response.url).searchParams.get("error") : null;
  if (refused) return { ok: false, reason: "rejected", detail: refused };
  return readLogin(response, pending.serverUrl);
}

export function isSameOrigin(serverUrl: string) {
  return typeof location !== "undefined" && new URL(serverUrl).origin === location.origin;
}
