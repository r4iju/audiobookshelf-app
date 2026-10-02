# Self-hosted deployment

This client is a static-plus-Node web app that runs on your own machine next to an existing Audiobookshelf server.
The browser talks to the server directly for everything: sign-in, the API, the live socket, covers, audio and
ebooks. The client's own Node process only serves the app's pages and scripts. It never sees credentials or media,
and nothing is hosted elsewhere.

The server stays as it is. Its own web interface keeps working at `/`, and the native apps keep talking to it
directly. Deploying this client does not upgrade, restart or reconfigure the server, apart from the optional OpenID
settings described below.

Tested against Audiobookshelf **2.30.0**
(`ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03`).
See [SERVER-CONTRACT.md](SERVER-CONTRACT.md) for what the client relies on.

## Choosing a topology

| | Same origin, under `/web` (recommended) | Separate origin |
| --- | --- | --- |
| Address | `https://abs.example/web` beside `https://abs.example/` | `https://books.example` and `https://abs.example` |
| Password sign-in | Yes | Yes, if the server allows the client's origin |
| OpenID sign-in | Yes | **No**: the server keeps the sign-in in a cookie on its own origin |
| Server change needed | None for passwords; OpenID needs the settings below | Add the client's origin to the server's allowed origins |

**Same origin** puts a reverse proxy in front of both. It sends `/web` to this client and everything else to the
server. `deploy/compose.yaml` and `deploy/nginx.conf` are exactly this, and they are what the deployment journeys
run (`e2e/deployment.spec.ts`).

**Separate origin** serves the client on its own host name. The browser then makes cross-origin requests, which the
server allows only for origins in its `allowedOrigins` setting (`PATCH /api/settings`, administrator only). The
client shows "OpenID sign-in needs this client to be served from the same origin as the server" in place of the
OpenID button.

## Same-origin deployment with Docker Compose

Requirements: Docker with Compose v2, and the server already running in a container on a user-defined Docker
network.

1. Find the server's network and give the server the name the proxy uses. The proxy finds the server as
   `audiobookshelf` on port 80, so the container needs that name or alias on the network:

   ```sh
   docker inspect --format '{{json .NetworkSettings.Networks}}' <server-container>
   # If the container is not already called "audiobookshelf" on that network:
   docker network connect --alias audiobookshelf <network> <server-container>
   ```

   If the server listens on a different port inside its container, change `audiobookshelf:80` in
   `deploy/nginx.conf`.

2. Build and start, from `web/`:

   ```sh
   ABS_SERVER_NETWORK=<network> docker compose -f deploy/compose.yaml up --detach --build --wait
   ```

   | Variable | Default | Meaning |
   | --- | --- | --- |
   | `ABS_SERVER_NETWORK` | required | The Docker network the server container is on. |
   | `ABS_PROXY_BIND` | `80` | Where the proxy listens: `80`, `0.0.0.0:80`, `192.168.1.10:80`, ... |
   | `ABS_WEB_BIND` | `127.0.0.1:3000` | The client's own port, for checking it directly. |
   | `ABS_WEB_IMAGE` | `audiobookshelf-web:local` | Tag for the built image. |
   | `ABS_WEB_SERVER` | `/` | The server the client signs in to first. See [The client's own server](#the-clients-own-server). |

3. Open `http://<host>/web`. A browser with no saved servers checks the server at `http://<host>` (the same origin,
   without `/web`) and goes straight to signing in to it.

Compose never creates, stops or changes the server container. `docker compose -f deploy/compose.yaml down` removes
only the client and the proxy.

### Using your own reverse proxy

If a reverse proxy already fronts the server (nginx, Caddy, Traefik, Nginx Proxy Manager), skip the bundled proxy.
Run the client container on its own and add one route. The proxy must:

- send `/web` and everything below it to the client, keeping the path (do not strip `/web`);
- send everything else to the server, unchanged;
- pass the original `Host` header to the server, port included. The server builds OpenID return addresses from it;
- pass `X-Forwarded-Proto: https` when people use HTTPS. The server picks `http` or `https` for OpenID addresses
  from it. The bundled nginx keeps a value set by a TLS proxy in front of it;
- allow WebSocket upgrades for `/socket.io` (the live updates channel) and leave streams unbuffered with long
  timeouts.

`deploy/nginx.conf` is a complete, commented example. For nginx in Docker that already proxies the server:

1. Start only the client, on the Docker network the proxy is on (the bundled proxy is not started):

   ```sh
   ABS_SERVER_NETWORK=<proxy's network> docker compose -f deploy/compose.yaml up --detach --build --wait abs-web
   ```

2. Include `deploy/existing-proxy.conf` in the proxy's `server` block for the server's host name, beside its
   `location /`. Leave that location as it is.
3. Check the configuration (`nginx -t`) and reload the proxy, then run the smoke check below.

A proxy that passes `Host` as `$host` drops the port. That is fine on the default ports, but OpenID return
addresses then lack any other port.

### The client's own server

`ABS_WEB_SERVER` is read by the running client, so one image serves any deployment. It names where the server
answers:

- a path on the client's own origin: `/` when the server is at the origin's root beside `/web`, or a subpath such as
  `/audiobookshelf` when the proxy serves it there;
- or a full address, `https://abs.example`.

On a first visit, with no servers saved in that browser, the connect page checks that server's `/status` and opens
its sign-in. If the check fails, the page says why and the address can be corrected. "Change server" always leads
to the address field, prefilled with the deployment's server. Browsers with saved servers see them listed as before.

Unset or empty, the client names no server and people enter the address themselves; that suits a client serving
several servers. Nothing is guessed from the host name, and the client's own base path is never taken for the
server's.

### The base path is fixed when the image is built

Next.js only supports a build-time base path. The image is built for `/web` (the `ABS_WEB_BASE_PATH` build argument
in `deploy/compose.yaml`). To serve it elsewhere, change that argument and rebuild. An empty value serves the client
at the root of its own origin, which only suits the separate-origin topology. The server already owns `/` on its own
origin.

### Without Docker

```sh
cd web
npm ci
ABS_WEB_BASE_PATH=/web npm run build
cp -r .next/static .next/standalone/.next/static
cp -r public .next/standalone/public
HOSTNAME=127.0.0.1 PORT=3000 node .next/standalone/server.js
```

Then route `/web` to `127.0.0.1:3000` as described above.

## OpenID sign-in

The client uses the server's own OpenID flow with PKCE, the one the mobile apps use. The browser goes to the
provider through the server and comes back to the server. The server then sends the browser to this client's
`/web/oauth` page, which finishes the sign-in. The identity provider only ever talks to the server. This client
needs no provider registration of its own.

Server settings (administrator, Settings → Authentication, or `PATCH /api/auth-settings`):

1. Configure OpenID for the server as usual, and confirm the server's own interface can sign in with it.
2. Add the client's return address to **Allowed Mobile Redirect URIs**, exactly as people reach it, for example
   `https://abs.example/web/oauth`.

Limitations of 2.30.0 to plan around:

- **No port in the return address.** The server rejects any URI with a port (its check is
  `^\w+://[\w\.-]+(/[\w\./-]*)*$`). The client must be reachable on port 443 or 80 under a host name for OpenID to
  work. A port-addressed deployment such as `http://192.168.1.10:13378/web` can still use password sign-in.
- **Never use `*`.** The server's "allow any redirect URI" setting lets any web page receive a sign-in code meant
  for your server.
- **The `Host` header must reach the server.** Otherwise the server sends the provider a return address for a host
  people cannot reach.
- **Refusals look alike.** When the provider refuses (for example, the person presses "Deny"), 2.30.0 reports its
  own failed exchange, so the client shows "the server refused it (Error in callback)".

Before it sends anything to the server, the client checks that the reply belongs to the sign-in started in the same
tab (the `state`). The PKCE verifier lives only in that tab's `sessionStorage`. Once the sign-in finishes, the code
is removed from the address bar and from history.

## HTTPS and plain-HTTP LAN addresses

Use HTTPS wherever the client is reachable beyond one trusted machine. It protects the password, the tokens and the
media. Most podcast apps also need it for RSS feeds.

A plain-HTTP LAN address such as `http://nas.local/web` still works. Browsers withhold some APIs from insecure
origins (`crypto.subtle`, `crypto.randomUUID`, the clipboard), so the client has fallbacks: its own SHA-256 for the
PKCE challenge, random ids from `crypto.getRandomValues`, and copy buttons that fail quietly and leave the text
selectable. The deployment journeys run on a plain-HTTP host name to keep these fallbacks covered.

## Credentials and data in the browser

- The access and refresh tokens are kept in this browser's `localStorage`, per server and account. Every request
  sends the access token as a bearer token. On a 401 the client renews it once with the refresh token, coordinated
  across tabs, and saves the new tokens before retrying. If renewal fails, the client asks the person to sign in
  again and keeps their place and any unsent progress.
- Signing out forgets the tokens. It keeps the server entry and any progress still waiting to be sent, until the
  next sign-in to that account.
- Listening progress waits in `localStorage` until the server confirms it, so an outage or a closed tab does not
  lose it.
- Downloads use the server's `?token=` query parameter, as the server's own interface does, so that large files
  stream to disk. That puts the access token into the download's address. Prefer HTTPS, and keep server access logs
  private.
- The client has no server-side storage, cookies or sessions of its own. Its container is read-only.

## Media and reachability

Audio, covers, ebooks and comic pages load from the server's address in the browser. When the browser can reach
the server, playback works; the client's own process is never on the media path. In the same-origin topology,
everything uses the one origin. The deployment journey "pages, deep links, readers and media are all served from
the one origin" records every request origin and finds only that one.

Nothing in this design depends on a cloud service reaching your LAN. A browser outside the LAN needs whatever
route you already use for the server, such as a VPN or your own HTTPS proxy.

## Upgrading and rolling back

The client is stateless on the host, so upgrading means rebuilding from a newer checkout:

```sh
git pull
ABS_SERVER_NETWORK=<network> docker compose -f deploy/compose.yaml up --detach --build --wait
```

To roll back, check out the previous commit and run the same command, or tag images (`ABS_WEB_IMAGE=...:<sha>`) and
start the old tag. Browser data carries over in both directions: its keys are versioned (`abs-web:v1:...`) and
unknown entries are ignored.

Edits to `deploy/nginx.conf` take effect after `docker compose -f deploy/compose.yaml restart proxy`.

Upgrading the server is a separate decision. Check [SERVER-CONTRACT.md](SERVER-CONTRACT.md) and run the journeys
against the new server version first (change the digest in `qa/server.mjs`).

## Verifying a deployment

From `web/`, against the isolated QA server (never your own server):

```sh
npm run qa:deploy -- up                  # build the image and run deploy/compose.yaml beside the QA server
npx playwright test e2e/deployment.spec.ts
npm run qa:deploy -- down
```

The journeys cover:

- OpenID sign-in through a real provider round trip;
- a refused sign-in;
- a forged return;
- a reload, and signing out;
- playback, a comic and a PDF over the one origin;
- the client's own port: no framework header, and nothing outside `/web`.

Against a real deployment, `node qa/smoke.mjs https://abs.example` checks, with GET requests only and without
signing in, that `/web/connect` answers without `x-powered-by` and loads its scripts from the same origin, that the
server's `/status` and live updates channel answer through the proxy, and that the server's own interface still
answers at `/`. Then check by hand:

- `curl -I https://abs.example/web/connect` answers 200 without `x-powered-by`;
- the server's own interface still signs in at `https://abs.example/`;
- signing in at `/web` and playing a book works;
- with OpenID, the provider round trip ends back at `/web` signed in.
