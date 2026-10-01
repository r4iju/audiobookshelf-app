# Server contract

What this browser client relies on from the Audiobookshelf server. The browser journeys verify every entry against
an unmodified **2.30.0** container
(`ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03`, pinned in
`qa/server.mjs`). No other server version has been tested.

Responses are parsed with zod schemas in `src/lib/abs/schemas.ts` and `src/lib/abs/feeds.ts`. Objects are loose, so
fields a later server adds are ignored. A missing required field fails as "Unexpected server response" rather than
as wrong data.

## Connecting and signing in

| Request | Use |
| --- | --- |
| `GET /status` | Recognise a server: `isInit`, `authMethods`, `authFormData.authOpenIDButtonText`, `serverVersion`. |
| `POST /login` with `x-return-tokens: true` | Password sign-in. Reads `user.accessToken` and `user.refreshToken`. A server without them returns `user.token`, which is kept as a legacy token. |
| `POST /auth/refresh` with `x-refresh-token` | Renews tokens after a 401. One renewal at a time per account, across tabs (`navigator.locks`). |
| `POST /api/authorize` | Confirms the sign-in before downloads, and gives the e-readers this account may use (`ereaderDevices`). |
| `GET /api/me` | The account, its permissions and its progress. |

Status codes the client distinguishes: 401 (renew once, then ask to sign in again), 403, 404, 429 (sign-in rate
limit). A `text/plain` error body is shown as the server's own explanation, such as "Slug already in use".

### OpenID (PKCE "mobile" flow)

1. The browser goes to `GET /auth/openid?code_challenge=<S256>&code_challenge_method=S256&redirect_uri=<client>/oauth&client_id=Audiobookshelf-Web&response_type=code&state=<random>`.
2. The server keeps the challenge in its session cookie and sends the browser to the provider. The provider's
   return address is the server's own `/auth/openid/mobile-redirect`.
3. The server redirects to `<client>/oauth?code=...&state=...`, but only if that exact address is in
   `authOpenIDMobileRedirectURIs`.
4. The client checks `state`, then calls `GET /auth/openid/callback?state&code&code_verifier` with the cookie
   (same origin only) and reads the same payload as `/login`.

2.30.0 quirks the client handles or documents:

- **Return addresses with a port are rejected.** `authOpenIDMobileRedirectURIs` entries must match
  `^\w+://[\w\.-]+(/[\w\./-]*)*$`. The only alternative is `*`, which must not be used.
- **The server's address comes from the request.** It builds the provider return address from `Host` and from
  `X-Forwarded-Proto` (or a TLS socket). Proxies must forward both.
- **A failed exchange is a redirect.** It goes to `/login?error=<message>&autoLaunch=0` instead of an error status,
  so the client reads `error` from the final URL of the followed redirect.
- **A provider refusal is lost.** `access_denied` reaches the client as `code=undefined`. The exchange then fails
  with "Error in callback".
- **Provider keys are cached.** openid-client caches the provider's keys and refetches them at most about once a
  minute. Only the QA provider is affected: it keeps its key across restarts.
- **New accounts are named from the provider.** Auto-registration names accounts from `preferred_username`.

### Cross-origin use

Without the same origin, the browser needs the server's `allowedOrigins` setting (`PATCH /api/settings`). The QA
server allows the development server's origins. OpenID cannot work cross-origin; see step 4 above.

## Library and items

- `GET /api/libraries`
- `GET /api/libraries/:id?include=filterdata`
- `GET /api/libraries/:id/personalized?include=rssfeed,numEpisodesIncomplete`
- `GET /api/libraries/:id/items?<sort, desc, filter, limit, page, collapseseries, minified, include>`
  - Filters are the server's `group.base64(value)` form.
- `GET /api/libraries/:id/search?q`
- `GET /api/libraries/:id/series?...`
- `GET /api/libraries/:id/series/:seriesId?include=progress`
- `GET /api/libraries/:id/authors`
- `GET /api/authors/:id?include=items,series&library=:id`
- `GET /api/authors/:id/image`
- `GET /api/items/:id?expanded=1&include=rssfeed,downloads`
  - Includes `rssFeed`, `episodeDownloadsQueued` and `episodesDownloading`.
- `GET /api/items/:id/cover`
- `GET /api/libraries/:id/recent-episodes?limit&page`

## Playback and progress

- `POST /api/items/:id/play` and `POST /api/items/:id/play/:episodeId`
  - Sent with `deviceInfo`, `mediaPlayer: "html5"`, `forceDirectPlay: false`, `forceTranscode: false` and
    `supportedMimeTypes`.
  - The client plays the returned `audioTracks[].contentUrl`. These are direct files under
    `/public/session/:id/track/:index`, or HLS under `/hls/` when the server transcodes; HLS segments carry the
    bearer token.
- `POST /api/session/local-all`
  - Listening is reported as "local sessions" with client-chosen ids and cumulative totals.
  - Sending a session again is safe.
  - The server applies progress only when `updatedAt` is not older than what it has, so reports are dated in
    server time (the offset is taken from the play response).
- `POST /api/session/:id/close`
  - Ends a playback session. When progress is discarded, the session is closed without a final report.
- `PATCH /api/me/progress/:itemId[/:episodeId]`
  - `isFinished`, and reader places (`ebookLocation`, `ebookProgress`).
- `DELETE /api/me/progress/:progressId`
  - Discard progress. Sent only after the session is closed and any `local-all` already sent is answered. The
    server creates progress afresh from a report that lands after the delete, bringing the old position back.
    Listening for the same book recorded during the discard is held and sent after the delete, so it is not deleted
    with the old position. Opening a playback session (`/play`) does not change progress, so playing again during a
    discard is safe.
- `POST` and `PATCH` on `/api/me/item/:id/bookmark`, `DELETE /api/me/item/:id/bookmark/:time` (bookmarks come with `/api/me`)
- `GET /api/me/listening-stats`, `GET /api/me/stats/year/:year`, `GET /api/stats/year/:year` (administrators)

After a server restart, sessions are forgotten. The client recovers once with a fresh session at the same position.

## Lists, podcasts and item actions

- **Collections:** `GET /api/libraries/:id/collections`; `POST /api/collections`; `POST` and `DELETE` on
  `/api/collections/:id/book[/:itemId]`; `DELETE /api/collections/:id`.
- **Playlists:** `GET /api/libraries/:id/playlists`; `POST /api/playlists`; `POST /api/playlists/:id/batch/add`;
  `DELETE /api/playlists/:id/item/:itemId[/:episodeId]`; `DELETE /api/playlists/:id`.
- **Podcasts:**
  - `GET /api/search/podcast?term`
  - `POST /api/podcasts/feed`
  - `POST /api/podcasts`
  - `POST /api/podcasts/:id/download-episodes`
  - `GET /api/podcasts/:id/clear-queue`
  - `DELETE /api/podcasts/:id/episode/:episodeId?hard=1`
- **RSS feeds (administrators):**
  - `POST /api/feeds/item/:id/open` with `{ serverAddress, slug, metadataDetails: { preventIndexing, ownerName, ownerEmail } }`
    returns `{ feed }`;
  - `POST /api/feeds/:id/close`.
  - In 2.30.0 a feed's `id` is a UUID; the slug appears only in `feedUrl` (`/feed/<slug>`). Anyone sees an open feed
    through the item's `rssFeed`.
- **Send to e-reader:** `POST /api/emails/send-ebook-to-device` with `{ libraryItemId, deviceName }`.
  - The server checks the device's availability for the account and needs working SMTP settings. An SMTP failure
    comes back as 400 with the mail error as text.
- **Download:** `GET /api/items/:id/download?token=<access token>`. The token travels as a query parameter so that
  the browser can stream the file to disk.

## Readers

- `GET /api/items/:id/ebook` serves the primary ebook. `GET /api/items/:id/ebook/:ino` serves a supplementary ebook;
  only the primary ebook keeps a reading place, as in the other clients.
- PDF and comic places are the 1-based page as text, as the other clients save them.
- EPUB places are CFIs.
- MOBI and AZW3 places use the browser's own `mobi:<version>:<section>:<block>`, because the legacy clients never
  saved one.

## Live updates (socket.io)

The client connects to `<server>/socket.io` and sends `auth` with the access token. `auth_failed` means sign in
again. It listens for:

- `user_item_progress_updated`, `user_updated`;
- `item_added`, `item_updated`, `item_removed`, `items_added`, `items_updated`;
- `episode_added` and the `episode_download_*` events;
- `collection_*` and `playlist_*` events.

## Alignment needed after a server release

Before a new server version reaches the owner's server, for this client and for the native apps, which call the
same endpoints:

1. Change the image digest in `qa/server.mjs`. Run `node qa/server.mjs up --fresh` and the full suite
   (`npm run lint && npm run typecheck && npm test && npm run e2e`).
2. Check the release notes against each section above. These areas have changed between releases before: token
   fields in `/login`, the OpenID redirect-URI check and error reporting, feed ids, and the progress `updatedAt`
   rule.
3. If the redirect-URI check starts accepting ports, port-addressed deployments can use OpenID. Update
   [DEPLOYMENT.md](DEPLOYMENT.md).
4. Report any change in a shared endpoint to the native app owners. `docs/modernization/SERVER-COMPATIBILITY.md` is
   the shared record.
