// Sequentially replace only the private QA installation with a prefixed product image.
// One listener serves pages, APIs and media. The original backend is never launched.
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { client, issuer } from "./oidc.mjs";
import { accounts, env, image, stop } from "./server.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const origin = "http://127.0.0.1:19882/web";
const prefixedImage = `${image}-subpath`;
function server(environment) {
  execFileSync("node", [join(here, "server.mjs"), "up"], {
    env: { ...env, LEAFWAKE_QA_REUSE_VOLUME: "1", ...environment },
    stdio: "inherit",
  });
}
async function up() {
  execFileSync("node", [join(here, "server.mjs"), "up"], { env, stdio: "inherit" });
  execFileSync(
    "docker",
    ["build", "--build-arg", "ABS_WEB_BASE_PATH=/web", "-t", prefixedImage, join(here, "..")],
    { env, stdio: "inherit" },
  );
  stop();
  server({ ABS_QA_PORT: "19882", ABS_WEB_BASE_PATH: "/web", LEAFWAKE_QA_IMAGE: prefixedImage });
  const login = await fetch(`${origin}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-return-tokens": "true" },
    body: JSON.stringify(accounts.admin),
  });
  if (!login.ok) throw new Error(`QA login failed: ${login.status}`);
  const token = (await login.json()).user.accessToken;
  // Helpers have independent startup readiness. Discovery must not race their listeners.
  for (let n = 0; n < 100; n++) {
    try {
      if ((await fetch(`${issuer}/.well-known/openid-configuration`)).ok) break;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const response = await fetch(`${origin}/api/admin/openid/settings`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      enabled: true,
      issuer,
      publicUrl: origin,
      clientId: client.id,
      clientSecret: client.secret,
      redirectUris: ["audiobookshelf://oauth", `${origin}/oauth`],
      allowRegistration: true,
      buttonText: "Sign in with QA SSO",
      autoLaunch: false,
    }),
  });
  if (!response.ok) throw new Error(`OpenID settings: ${response.status} ${await response.text()}`);
  console.log(JSON.stringify({ web: origin, image: prefixedImage }));
}
function down() {
  stop();
  server({ ABS_QA_PORT: "19880", ABS_WEB_BASE_PATH: "", LEAFWAKE_QA_IMAGE: image });
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === "down") down();
  else if ((process.argv[2] ?? "up") === "up") await up();
  else throw new Error("Use up or down");
}
