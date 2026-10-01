// Runs the self-hosted deployment from docs/DEPLOYMENT.md against the QA server: the production image of this client
// under /web (127.0.0.1:19883) and nginx serving it and the server from one origin (127.0.0.1:19882), with OpenID
// sign-in through the loopback provider (qa/oidc.mjs, 19884). Never touches the production container or its data.
//   node qa/deploy.mjs up     build the image, (re)start the containers and enable OpenID on the QA server
//   node qa/deploy.mjs down   remove the containers and network (the QA server keeps running)
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { backchannel, client, issuer } from "./oidc.mjs";
import { accounts, docker, env, QA_PORT } from "./server.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const dockerIfPossible = (...args) => {
  try {
    return docker(...args);
  } catch {
    return null;
  }
};

const WEB_PORT = 19883;
const PROXY_PORT = 19882;
const basePath = "/web";
const proxyLoopback = `http://127.0.0.1:${PROXY_PORT}`;
// The 2.30.0 server only accepts OpenID return addresses without a port (or "*", which lets any site receive
// sign-ins). Browsers in the journeys map this name to the proxy, so the deployment is seen as it is in use: on the
// default port of its own host name.
const proxyHost = "abs-web.test";
const proxyOrigin = `http://${proxyHost}`;
const network = "abs-web-deploy";
const project = "abs-web-qa-deploy";
const qaServer = "abs-web-qa";
const qaOrigin = `http://127.0.0.1:${QA_PORT}`;
const compose = (...args) =>
  execFileSync("docker", ["compose", "-p", project, "-f", join(root, "deploy", "compose.yaml"), ...args], {
    env: {
      ...env,
      ABS_SERVER_NETWORK: network,
      ABS_WEB_IMAGE: "abs-web:qa",
      ABS_WEB_BIND: `127.0.0.1:${WEB_PORT}`,
      ABS_PROXY_BIND: `127.0.0.1:${PROXY_PORT}`,
    },
    stdio: "inherit",
  });

async function waitFor(url) {
  for (let tries = 0; tries < 120; tries++) {
    try {
      if ((await fetch(url)).ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`${url} did not come up`);
}

async function enableOpenId() {
  const login = await fetch(`${qaOrigin}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-return-tokens": "true" },
    body: JSON.stringify(accounts.admin),
  });
  const token = (await login.json()).user.accessToken;
  const response = await fetch(`${qaOrigin}/api/auth-settings`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      authActiveAuthMethods: ["local", "openid"],
      authOpenIDIssuerURL: issuer,
      authOpenIDAuthorizationURL: `${issuer}/authorize`,
      authOpenIDTokenURL: `${backchannel}/token`,
      authOpenIDUserInfoURL: `${backchannel}/userinfo`,
      authOpenIDJwksURL: `${backchannel}/jwks`,
      authOpenIDClientID: client.id,
      authOpenIDClientSecret: client.secret,
      authOpenIDTokenSigningAlgorithm: "RS256",
      authOpenIDButtonText: "Sign in with QA SSO",
      authOpenIDAutoRegister: true,
      authOpenIDMobileRedirectURIs: ["audiobookshelf://oauth", `${proxyOrigin}${basePath}/oauth`],
      authOpenIDSubfolderForRedirectURLs: "",
    }),
  });
  if (!response.ok) throw new Error(`auth settings -> ${response.status} ${await response.text()}`);
}

async function up() {
  execFileSync("node", [join(here, "server.mjs"), "up"], { stdio: "inherit" });
  if (!dockerIfPossible("network", "inspect", network)) docker("network", "create", network);
  // The QA server joins under the name the documented nginx configuration uses for the server.
  if (!docker("inspect", "--format", "{{json .NetworkSettings.Networks}}", qaServer).includes(`"${network}"`))
    docker("network", "connect", "--alias", "audiobookshelf", network, qaServer);
  // Exactly the documented deployment: deploy/compose.yaml, rebuilt from this checkout.
  compose("up", "--detach", "--build", "--force-recreate", "--wait");
  await waitFor(`http://127.0.0.1:${WEB_PORT}${basePath}/connect`);
  await waitFor(`${proxyLoopback}${basePath}/connect`);
  await waitFor(`${proxyLoopback}/status`);
  await enableOpenId();
  console.log(JSON.stringify({ web: `${proxyOrigin}${basePath}`, proxy: proxyLoopback }));
}

function down() {
  compose("down");
  dockerIfPossible("network", "disconnect", network, qaServer);
  dockerIfPossible("network", "rm", network);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command = "up"] = process.argv.slice(2);
  if (command === "down") down();
  else if (command === "up") await up();
  else throw new Error(`Unknown command ${command}`);
}
