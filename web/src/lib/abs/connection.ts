import { z } from "zod";

/**
 * How this browser proves identity to one server.
 * - token: password or OpenID (PKCE) sign-in that returns tokens; the rotating refresh token is kept per connection
 *   in this browser's storage. The server's cookie-based web flow is not used: its `refresh_token` cookie would
 *   replace the session of the server's own web interface on the same origin.
 * - legacy: servers before 2.26 issue one non-expiring `user.token`.
 */
export const authStateSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("token"), accessToken: z.string(), refreshToken: z.string() }),
  z.object({ kind: z.literal("legacy"), token: z.string() }),
]);
export type AuthState = z.infer<typeof authStateSchema>;

export const connectionSchema = z.object({
  id: z.string(),
  serverUrl: z.string(),
  username: z.string(),
  userId: z.string(),
  serverVersion: z.string().optional(),
  serverLanguage: z.string().optional(),
  auth: authStateSchema,
});
export type Connection = z.infer<typeof connectionSchema>;

/** A saved server whose credentials the server rejected; kept so the user can sign in again without retyping. */
export const savedConnectionSchema = z.object({
  id: z.string(),
  serverUrl: z.string(),
  username: z.string(),
  userId: z.string(),
  serverVersion: z.string().optional(),
  serverLanguage: z.string().optional(),
  auth: authStateSchema.nullable(),
  lastLibraryId: z.string().optional(),
});
export type SavedConnection = z.infer<typeof savedConnectionSchema>;

export function bearerOf(auth: AuthState) {
  return auth.kind === "token" ? auth.accessToken : auth.token;
}

/** Connection identity mirrors the legacy app: one entry per server address and username. */
export function connectionId(serverUrl: string, username: string) {
  return `${serverUrl}@${username}`;
}

export type AddressResult =
  | { ok: true; url: string; assumedScheme: boolean }
  | { ok: false; reason: "empty" | "invalid" | "unsupported-scheme" };

/** Normalizes user input to a server base URL, preserving reverse-proxy subpaths. */
export function normalizeServerAddress(input: string): AddressResult {
  const trimmed = input.trim();
  if (!trimmed) return { ok: false, reason: "empty" };
  const assumedScheme = !/^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed);
  let url: URL;
  try {
    url = new URL(assumedScheme ? `https://${trimmed}` : trimmed);
  } catch {
    return { ok: false, reason: "invalid" };
  }
  if (url.protocol !== "http:" && url.protocol !== "https:")
    return { ok: false, reason: "unsupported-scheme" };
  if (url.username || url.password) return { ok: false, reason: "invalid" };
  const path = url.pathname.replace(/\/+$/, "");
  return { ok: true, url: `${url.origin}${path}`, assumedScheme };
}
