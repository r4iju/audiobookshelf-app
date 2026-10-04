# Leafwake deployment

One image serves the browser, REST API, Socket.IO, persistent jobs and bounded FFmpeg work on port 3000. The original backend and browser are replaced. The image runs as an unprivileged user. Keep `/data` on a persistent private volume, and mount original media and import snapshots read-only.

## Docker Compose

From `web/`, set these privately in your environment or an untracked environment file:

- `LEAFWAKE_SETUP_KEY`: a private first-owner setup key.
- `LEAFWAKE_MEDIA_DIR`: the original media directory.
- `LEAFWAKE_IMPORT_DIR`: a private directory of read-only snapshots, empty for a fresh installation.
- `LEAFWAKE_BIND`: listener binding, default `127.0.0.1:3000`.
- `LEAFWAKE_IMAGE`: image tag, default `leafwake:local`.

Run `docker compose -f deploy/compose.yaml up --detach --build --wait`. Open `/setup` for a fresh owner or follow [MIGRATION.md](../../docs/fullstack/MIGRATION.md) to import existing data. Initialization closes atomically. Restarting retains accounts and requires normal sign-in. Never expose the setup key in a listing, log or source archive.

The Compose file has one service. An existing HTTPS ingress can forward all requests to that listener, preserving paths and allowing WebSocket upgrades and long media streams. No legacy backend service or path split is needed. Set the exact public URL in OpenID settings, with HTTPS for public use and exact client callbacks. Registration is disabled unless deliberately enabled.

## Subpath

`ABS_WEB_BASE_PATH` is a build argument, empty by default. Build with `docker build --build-arg ABS_WEB_BASE_PATH=/web -t leafwake:subpath .` to serve the entire product below `/web`, including status, APIs, media and Socket.IO. Native clients then use the URL ending in `/web`. Next.js embeds the prefix at build time; changing a runtime variable cannot relocate an existing image. The image sets its initial browser server address to its own prefix.

## Without Docker

Use Node 24, install FFmpeg, run `npm ci`, then `npm run build`. Start `NODE_ENV=production LEAFWAKE_DATA_DIR=<private-dir> LEAFWAKE_MEDIA_ROOTS=<read-only-media-dir> LEAFWAKE_SETUP_KEY=<private-key> node server.mjs`. Use the custom entry, not `.next/standalone/server.js`.

## Backup, update and rollback

Take a verified private backup before an upgrade. Preserve the image digest and corresponding source. Follow [MIGRATION.md](../../docs/fullstack/MIGRATION.md) for validation and [RECOVERY.md](../../docs/fullstack/RECOVERY.md) for recovery. A backup includes the SQLite state and private signing authority; restore revokes sessions. Do not run an older image against a newer schema. Restore a compatible backup into an empty volume for rollback and retain the original data untouched until verification completes.

## Verification

`node qa/smoke.mjs https://books.example` performs read-only checks of the UI, status and realtime handshake. For a subpath, pass `/web` as the second argument. Then sign in, play audio and reopen the account to confirm saved progress. The existing browser deployment journeys use `qa/deploy.mjs` to build a prefixed product image and reuse only a synthetic volume. These fixture helpers are not part of a live deployment.
