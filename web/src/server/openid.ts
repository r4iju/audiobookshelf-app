import "server-only";
import { createHash, randomBytes } from "node:crypto";
import * as oidc from "openid-client";
import { z } from "zod";
import { type Account, DomainError, openIdSession, requireAdministrator } from "./accounts";
import { database, transaction } from "./data";
import { remoteStream, remoteUrl } from "./remote";
import { seal, unseal } from "./secrets";

function insecureHosts() {
  return process.env.LEAFWAKE_OPENID_ALLOWED_HOSTS ?? "";
}
function providerUrl(value: string) {
  const url = remoteUrl(value);
  if (url.protocol !== "https:" && !insecureHosts().split(",").includes(url.hostname))
    throw new DomainError(400, "OpenID requires HTTPS or an explicitly configured development host");
  return url;
}
const exactRedirect = z
  .string()
  .max(2048)
  .refine((value) => {
    try {
      const url = new URL(value);
      return (
        !url.username &&
        !url.password &&
        !url.hash &&
        !url.search &&
        url.toString() === value &&
        (url.protocol === "https:" ||
          (url.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) ||
          (!["http:", "https:", "javascript:", "data:", "file:"].includes(url.protocol) &&
            url.host === "oauth" &&
            !url.pathname))
      );
    } catch {
      return false;
    }
  }, "Use an exact HTTPS, loopback development or native oauth callback");
export const openIdSchema = z.object({
  enabled: z.boolean(),
  issuer: z.string().max(4096),
  publicUrl: z.string().max(2048),
  clientId: z.string().min(1).max(256),
  redirectUris: z.array(exactRedirect).max(32),
  allowRegistration: z.boolean(),
  buttonText: z.string().max(256),
  autoLaunch: z.boolean(),
});
export const openIdInput = openIdSchema.extend({ clientSecret: z.string().max(4096).nullable().optional() });
const storedSchema = openIdSchema.extend({ clientSecret: z.string().max(4096), revision: z.string() });
const defaults = {
  enabled: false,
  issuer: "",
  publicUrl: "",
  clientId: "",
  redirectUris: [],
  allowRegistration: false,
  buttonText: "OpenID sign-in",
  autoLaunch: false,
  clientSecret: "",
  revision: "",
};
function stored() {
  const row = database().prepare("SELECT content FROM product_settings WHERE key='openid'").get();
  return row ? storedSchema.parse(unseal(z.string().parse(row.content))) : defaults;
}
export function openIdSettings() {
  const { clientSecret, revision, ...value } = stored();
  return { ...value, hasClientSecret: Boolean(clientSecret) };
}
async function providerFetch(url: Parameters<oidc.CustomFetch>[0], options: Parameters<oidc.CustomFetch>[1]) {
  const value = providerUrl(String(url));
  const signal = AbortSignal.any([AbortSignal.timeout(20000), ...(options?.signal ? [options.signal] : [])]);
  const headers = Object.fromEntries(new Headers(options?.headers));
  const body = options?.body === undefined ? undefined : String(options.body);
  if (body && Buffer.byteLength(body) > 16384) throw new DomainError(400, "OpenID request exceeds limit");
  const response = await remoteStream(value.toString(), 1048576, signal, 0, {
    method: options?.method,
    headers,
    body,
    allowedHosts: insecureHosts(),
    rawStatus: true,
  });
  const chunks: Buffer[] = [];
  let bytes = 0;
  for await (const chunk of response) {
    const b = Buffer.from(chunk);
    bytes += b.length;
    if (bytes > 1048576) {
      response.destroy();
      throw new DomainError(400, "OpenID response exceeds limit");
    }
    chunks.push(b);
  }
  const out = new Headers();
  for (const [name, value] of Object.entries(response.headers))
    if (value) out.set(name, Array.isArray(value) ? value.join(",") : value);
  return new Response(Buffer.concat(chunks), { status: response.statusCode ?? 502, headers: out });
}
async function configuration(settings: ReturnType<typeof stored>) {
  const config = await oidc.discovery(
    providerUrl(settings.issuer),
    settings.clientId,
    settings.clientSecret || undefined,
    undefined,
    {
      [oidc.customFetch]: providerFetch,
      execute: [oidc.allowInsecureRequests, oidc.enableNonRepudiationChecks],
      timeout: 20,
    },
  );
  const metadata = config.serverMetadata();
  for (const endpoint of [
    metadata.authorization_endpoint,
    metadata.token_endpoint,
    metadata.jwks_uri,
    metadata.userinfo_endpoint,
  ])
    if (endpoint) providerUrl(endpoint);
  return config;
}
export async function saveOpenIdSettings(
  actor: Account,
  input: z.infer<typeof openIdInput>,
  authorize: () => Account,
) {
  requireAdministrator(actor);
  const previous = stored();
  const next = {
    ...openIdSchema.parse(input),
    clientSecret: input.clientSecret === null ? "" : (input.clientSecret ?? previous.clientSecret),
    revision: randomBytes(16).toString("hex"),
  };
  if (next.enabled) {
    const publicUrl = new URL(next.publicUrl);
    if (
      publicUrl.username ||
      publicUrl.password ||
      publicUrl.search ||
      publicUrl.hash ||
      !["http:", "https:"].includes(publicUrl.protocol) ||
      next.publicUrl.endsWith("/")
    )
      throw new DomainError(400, "Set the exact public server URL without a trailing slash");
    if (publicUrl.protocol === "http:" && !["127.0.0.1", "localhost", "[::1]"].includes(publicUrl.hostname))
      throw new DomainError(400, "Public OpenID URLs require HTTPS");
    if ((publicUrl.pathname === "/" ? "" : publicUrl.pathname) !== (globalThis.leafwakeBasePath || ""))
      throw new DomainError(400, "Public URL must use this image’s configured base path");
    if (!next.redirectUris.length) throw new DomainError(400, "Configure an exact client callback");
    try {
      await configuration(next);
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError(400, "Provider discovery could not be validated");
    }
  }
  transaction((db) => {
    requireAdministrator(authorize());
    if (stored().revision !== previous.revision)
      throw new DomainError(409, "OpenID settings changed; reload before saving");
    db.prepare(
      "INSERT INTO product_settings VALUES('openid',?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
    ).run(seal(next));
    db.prepare("DELETE FROM openid_flows").run();
  });
  return openIdSettings();
}
const flowSchema = z.object({
  settings: storedSchema,
  providerIssuer: z.string(),
  state: z.string(),
  challenge: z.string(),
  redirect: z.string(),
  nonce: z.string(),
  providerCode: z.string().optional(),
  responseIssuer: z.string().optional(),
  handoff: z.string().optional(),
});
function hash(value: string) {
  return createHash("sha256").update(value).digest("hex");
}
function single(params: URLSearchParams, key: string) {
  const all = params.getAll(key);
  if (all.length !== 1 || !all[0]) throw new DomainError(400, "Invalid OpenID request");
  return all[0];
}
function cookiePath() {
  return (globalThis.leafwakeBasePath || "") + "/auth/openid";
}
function cookie(value: string, settings: ReturnType<typeof stored>, clear = false) {
  return `leafwake_oidc=${value}; Path=${cookiePath()}; HttpOnly; SameSite=Lax; Max-Age=${clear ? 0 : 600}${new URL(settings.publicUrl).protocol === "https:" ? "; Secure" : ""}`;
}
function redirect(url: string, headers: Record<string, string> = {}) {
  return new Response(null, {
    status: 302,
    headers: { location: url, "cache-control": "no-store", ...headers },
  });
}
export async function beginOpenId(request: Request) {
  const settings = stored();
  if (!settings.enabled) throw new DomainError(404, "OpenID is disabled");
  const params = new URL(request.url).searchParams,
    state = single(params, "state"),
    challenge = single(params, "code_challenge"),
    uri = single(params, "redirect_uri");
  if (
    !/^[A-Za-z0-9_-]{16,256}$/.test(state) ||
    !/^[A-Za-z0-9_-]{43}$/.test(challenge) ||
    single(params, "code_challenge_method") !== "S256" ||
    single(params, "response_type") !== "code" ||
    !settings.redirectUris.includes(uri)
  )
    throw new DomainError(400, "Invalid OpenID callback or PKCE challenge");
  const config = await configuration(settings);
  if (stored().revision !== settings.revision) throw new DomainError(409, "OpenID settings changed");
  const secret = randomBytes(32).toString("base64url"),
    nonce = oidc.randomNonce();
  const flow = {
    settings,
    providerIssuer: config.serverMetadata().issuer,
    state,
    challenge,
    redirect: uri,
    nonce,
  };
  transaction((db) => {
    db.prepare("DELETE FROM openid_flows WHERE expires_at<=?").run(Date.now());
    if (Number(db.prepare("SELECT COUNT(*) AS n FROM openid_flows").get()?.n) >= 256)
      throw new DomainError(429, "Too many pending sign-ins");
    if (db.prepare("SELECT id FROM openid_flows WHERE state=?").get(state))
      throw new DomainError(400, "Sign-in state already used");
    db.prepare("INSERT INTO openid_flows VALUES(?,?,?,?)").run(
      hash(secret),
      state,
      Date.now() + 600000,
      seal(flow),
    );
  });
  const url = oidc.buildAuthorizationUrl(config, {
    redirect_uri: settings.publicUrl + "/auth/openid/callback",
    scope: "openid profile email",
    state,
    nonce,
    code_challenge: challenge,
    code_challenge_method: "S256",
    response_type: "code",
  });
  return redirect(url.toString(), { "set-cookie": cookie(secret, settings) });
}
export async function callbackOpenId(request: Request) {
  const params = new URL(request.url).searchParams,
    state = single(params, "state");
  const row = database()
    .prepare("SELECT * FROM openid_flows WHERE state=? AND expires_at>?")
    .get(state, Date.now());
  if (!row) throw new DomainError(400, "Sign-in expired or already used");
  const flow = flowSchema.parse(unseal(z.string().parse(row.content)));
  if (!stored().enabled || stored().revision !== flow.settings.revision)
    throw new DomainError(400, "OpenID settings changed");
  if (params.has("code_verifier")) {
    const secret = request.headers
      .get("cookie")
      ?.split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith("leafwake_oidc="))
      ?.slice("leafwake_oidc=".length);
    const verifier = single(params, "code_verifier");
    if (
      !secret ||
      hash(secret) !== row.id ||
      single(params, "code") !== flow.handoff ||
      !flow.providerCode ||
      !/^[A-Za-z0-9._~-]{43,128}$/.test(verifier) ||
      createHash("sha256").update(verifier).digest("base64url") !== flow.challenge
    )
      throw new DomainError(400, "Invalid OpenID exchange");
    const claimed = transaction(
      (db) =>
        db
          .prepare("DELETE FROM openid_flows WHERE id=? AND content=?")
          .run(z.string().parse(row.id), z.string().parse(row.content)).changes,
    );
    if (!claimed) throw new DomainError(400, "Sign-in already used");
    try {
      const config = await configuration(flow.settings);
      const url = new URL(flow.settings.publicUrl + "/auth/openid/callback");
      url.searchParams.set("state", state);
      url.searchParams.set("code", flow.providerCode);
      if (flow.responseIssuer) url.searchParams.set("iss", flow.responseIssuer);
      const tokens = await oidc.authorizationCodeGrant(config, url, {
        expectedState: state,
        expectedNonce: flow.nonce,
        pkceCodeVerifier: verifier,
        idTokenExpected: true,
      });
      const claims = tokens.claims();
      if (!claims?.sub || claims.sub.length > 1024)
        throw new DomainError(400, "Provider identity is missing");
      if (stored().revision !== flow.settings.revision) throw new DomainError(400, "OpenID settings changed");
      const reply = openIdSession(
        flow.providerIssuer,
        claims.sub,
        flow.settings.allowRegistration,
        typeof claims.preferred_username === "string" ? claims.preferred_username : "openid",
      );
      return Response.json(reply, {
        headers: { "cache-control": "no-store", "set-cookie": cookie("", flow.settings, true) },
      });
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError(400, "Provider sign-in could not be verified");
    }
  }
  const target = new URL(flow.redirect);
  target.searchParams.set("state", state);
  if (params.has("error")) {
    database().prepare("DELETE FROM openid_flows WHERE id=?").run(z.string().parse(row.id));
    target.searchParams.set("error", "access_denied");
    return redirect(target.toString());
  }
  const providerCode = single(params, "code");
  if (providerCode.length > 4096 || flow.providerCode)
    throw new DomainError(400, "Invalid provider callback");
  if (params.has("iss")) {
    const issuer = single(params, "iss");
    if (issuer !== flow.providerIssuer) throw new DomainError(400, "Provider response issuer did not match");
    flow.responseIssuer = issuer;
  }
  flow.providerCode = providerCode;
  flow.handoff = randomBytes(32).toString("base64url");
  const saved = transaction(
    (db) =>
      db
        .prepare("UPDATE openid_flows SET content=? WHERE id=? AND content=?")
        .run(seal(flow), z.string().parse(row.id), z.string().parse(row.content)).changes,
  );
  if (!saved) throw new DomainError(400, "Provider callback already used");
  target.searchParams.set("code", flow.handoff);
  return redirect(target.toString());
}
