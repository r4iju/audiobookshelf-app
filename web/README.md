# Audiobookshelf web client

A Next.js browser client for an existing Audiobookshelf server. It talks to the server's own HTTP API, socket.io
channel and media endpoints from the browser. Nothing sits between the browser and the server, and no hosted
service is involved. The legacy browser client that the server serves at `/` is unchanged and keeps working.

- How to deploy it next to a server: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- Which server endpoints and behaviours it relies on: [docs/SERVER-CONTRACT.md](docs/SERVER-CONTRACT.md)

## Requirements

- Node.js 22 or later, with npm.
- Docker for the QA server, the production image and the deployment journeys. On the Studio this is colima; the QA
  scripts use `unix://$HOME/.colima/default/docker.sock` when `DOCKER_HOST` is unset.

## Commands

Run these from `web/`.

| Command | What it does |
| --- | --- |
| `npm ci` | Install the exact pinned dependencies. |
| `npm run dev` | Development server on http://127.0.0.1:19881. |
| `npm run lint` | Biome lint and format check. |
| `npm run typecheck` | TypeScript, no emit. |
| `npm test` | Unit tests (vitest). |
| `npm run e2e` | Browser journeys (Playwright, Chromium) against the QA server. |
| `npm run build` | Production build (`.next/standalone`). Set `ABS_WEB_BASE_PATH=/web` to build for a subpath. |
| `npm run qa:server -- up` / `down` | Start or remove the isolated QA server. |
| `npm run qa:deploy -- up` / `down` | Build the production image and run the documented deployment against the QA server. |

`npx playwright install chromium` is needed once before the first journey run.

## QA fixtures and ports

The journeys never use the owner's server or data. They run against an unmodified Audiobookshelf 2.30.0 container
(pinned by digest in `qa/server.mjs`) with a synthetic library and synthetic accounts. All fixtures bind to loopback
on ports in 19880 to 19885, which are not shared with the Apple or Android QA fixtures.

| Port | Fixture | Source |
| --- | --- | --- |
| 19880 | QA Audiobookshelf server (container `abs-web-qa`) | `qa/server.mjs` |
| 19881 | Development server | `npm run dev` |
| 19882 | nginx serving the server at `/` and this client at `/web` from one origin | `deploy/compose.yaml` |
| 19883 | Production image of this client, built for `/web` | `deploy/compose.yaml` |
| 19884 | OpenID provider used by the server for OpenID sign-in | `qa/oidc.mjs` |
| 19885 | Podcast feed the server downloads episodes from | `qa/feed.mjs` |

Playwright starts the feed, the OpenID provider and the development server itself, and `e2e/global-setup.ts` starts
the QA server. `e2e/deployment.spec.ts` runs `qa/deploy.mjs up` first. That spec opens the deployment as
`http://abs-web.test`, a name that Chromium maps to 127.0.0.1:19882. The server only accepts OpenID return addresses
without a port.

Setting `ABS_WEB_URL` runs the journeys against an already running client. Setting `ABS_WEB_PROD=1` makes Playwright
build and start the production server instead of the development server.

Server-side state lives in `qa/.runtime` (git-ignored). This includes the QA state file and the OpenID provider's
signing key. `node qa/server.mjs up --fresh` recreates the QA server from scratch.
