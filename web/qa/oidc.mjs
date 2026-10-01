// A minimal OpenID Connect provider on loopback, so the server's real OpenID flow can be exercised with no hosted
// identity service. The browser reaches it as 127.0.0.1; the QA server's token, user info and key requests reach it
// as host.docker.internal. Both names serve the same issuer.
//   node qa/oidc.mjs
import {
  createHash,
  createPrivateKey,
  createPublicKey,
  createSign,
  generateKeyPairSync,
  randomBytes,
} from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const OIDC_PORT = Number(process.env.ABS_QA_OIDC_PORT ?? 19884);
export const issuer = `http://127.0.0.1:${OIDC_PORT}`;
export const backchannel = `http://host.docker.internal:${OIDC_PORT}`;
export const client = { id: "abs-web-qa", secret: "abs-web-qa-secret" };
export const person = {
  sub: "qa-openid-subject",
  preferred_username: "qa-openid",
  name: "QA OpenID",
  email: "qa-openid@example.invalid",
  email_verified: true,
};

// The server caches the provider's keys and refetches them at most once a minute, so the key outlives restarts.
const keyFile = join(dirname(fileURLToPath(import.meta.url)), ".runtime", "oidc-key.pem");
if (!existsSync(keyFile)) {
  mkdirSync(dirname(keyFile), { recursive: true });
  const generated = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;
  writeFileSync(keyFile, generated.export({ format: "pem", type: "pkcs8" }), { mode: 0o600 });
}
const privateKey = createPrivateKey(readFileSync(keyFile));
const publicKey = createPublicKey(privateKey);
// Named by its own hash, so a replaced key file is fetched again rather than mistaken for the cached one.
const kid = createHash("sha256")
  .update(publicKey.export({ format: "der", type: "spki" }))
  .digest("base64url");
const codes = new Map();
const tokens = new Map();

const base64Url = (value) => Buffer.from(value).toString("base64url");
const s256 = (verifier) => createHash("sha256").update(verifier).digest("base64url");

function sign(claims) {
  const input = `${base64Url(JSON.stringify({ alg: "RS256", typ: "JWT", kid }))}.${base64Url(JSON.stringify(claims))}`;
  return `${input}.${createSign("RSA-SHA256").update(input).sign(privateKey, "base64url")}`;
}

const json = (response, status, body) => {
  response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  response.end(JSON.stringify(body));
};

const htmlEscape = (value) => String(value).replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

function redirectWith(redirectUri, params) {
  const url = new URL(redirectUri);
  for (const [key, value] of Object.entries(params)) if (value) url.searchParams.set(key, value);
  return url.toString();
}

async function readForm(request) {
  let body = "";
  for await (const chunk of request) body += chunk;
  return new URLSearchParams(body);
}

function clientFrom(request, params) {
  const basic = request.headers.authorization?.match(/^Basic (.+)$/)?.[1];
  if (basic) {
    const [id, secret] = Buffer.from(basic, "base64").toString().split(":").map(decodeURIComponent);
    return { id, secret };
  }
  return { id: params.get("client_id"), secret: params.get("client_secret") };
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? "/", issuer);
  const route = `${request.method} ${url.pathname}`;

  if (route === "GET /.well-known/openid-configuration") {
    return json(response, 200, {
      issuer,
      authorization_endpoint: `${issuer}/authorize`,
      token_endpoint: `${backchannel}/token`,
      userinfo_endpoint: `${backchannel}/userinfo`,
      jwks_uri: `${backchannel}/jwks`,
      response_types_supported: ["code"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"],
      code_challenge_methods_supported: ["S256"],
    });
  }

  if (route === "GET /jwks") {
    return json(response, 200, {
      keys: [{ ...publicKey.export({ format: "jwk" }), kid, use: "sig", alg: "RS256" }],
    });
  }

  // The sign-in page a person sees at the provider: one account, and a way to refuse.
  if (route === "GET /authorize") {
    const params = url.searchParams;
    if (params.get("client_id") !== client.id || params.get("response_type") !== "code")
      return json(response, 400, { error: "invalid_request" });
    const hidden = [...params].map(
      ([key, value]) => `<input type="hidden" name="${htmlEscape(key)}" value="${htmlEscape(value)}">`,
    );
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    return response.end(`<!doctype html><html lang="en"><title>QA identity provider</title>
<main><h1>QA identity provider</h1><form method="post" action="/authorize">${hidden.join("")}
<button name="decision" value="allow">Continue as ${htmlEscape(person.name)}</button>
<button name="decision" value="deny">Deny</button></form></main></html>`);
  }

  if (route === "POST /authorize") {
    const params = await readForm(request);
    const redirectUri = params.get("redirect_uri") ?? "";
    if (!URL.canParse(redirectUri)) return json(response, 400, { error: "invalid_request" });
    const state = params.get("state") ?? "";
    if (params.get("decision") !== "allow") {
      response.writeHead(302, { Location: redirectWith(redirectUri, { error: "access_denied", state }) });
      return response.end();
    }
    const code = randomBytes(24).toString("base64url");
    codes.set(code, {
      redirectUri,
      challenge: params.get("code_challenge"),
      nonce: params.get("nonce"),
      scope: params.get("scope"),
    });
    response.writeHead(302, { Location: redirectWith(redirectUri, { code, state }) });
    return response.end();
  }

  if (route === "POST /token") {
    const params = await readForm(request);
    const caller = clientFrom(request, params);
    if (caller.id !== client.id || caller.secret !== client.secret)
      return json(response, 401, { error: "invalid_client" });
    const grant = codes.get(params.get("code") ?? "");
    codes.delete(params.get("code") ?? "");
    if (
      !grant ||
      params.get("grant_type") !== "authorization_code" ||
      params.get("redirect_uri") !== grant.redirectUri ||
      (grant.challenge && s256(params.get("code_verifier") ?? "") !== grant.challenge)
    )
      return json(response, 400, { error: "invalid_grant" });
    const now = Math.floor(Date.now() / 1000);
    const accessToken = randomBytes(24).toString("base64url");
    tokens.set(accessToken, person);
    return json(response, 200, {
      access_token: accessToken,
      token_type: "Bearer",
      expires_in: 600,
      scope: grant.scope,
      id_token: sign({
        iss: issuer,
        sub: person.sub,
        aud: client.id,
        iat: now,
        exp: now + 600,
        ...(grant.nonce ? { nonce: grant.nonce } : {}),
      }),
    });
  }

  if (route === "GET /userinfo") {
    const found = tokens.get(request.headers.authorization?.replace(/^Bearer /, "") ?? "");
    return found ? json(response, 200, found) : json(response, 401, { error: "invalid_token" });
  }

  json(response, 404, { error: "not_found" });
});

if (process.argv[1] === fileURLToPath(import.meta.url))
  server.listen(OIDC_PORT, process.env.ABS_QA_FIXTURE_HOST ?? "127.0.0.1", () =>
    console.log(`QA OpenID provider on ${issuer}`),
  );
