# Backup and recovery

Run the complete product image with one writable private data volume. The owner can create a backup in Migration and backups or enable an interval schedule (off by default). Scheduling persists its due time, lease and pending backup UUID. Restart reuses an already-published pending snapshot rather than creating another copy. Retention deletes scheduled snapshots only; manual backups remain until explicitly removed by the operator.

Each version2 backup is three private files in `/data/backups`: `UUID.sqlite`, `UUID.key`, `UUID.json`. Preserve all three together. The manifest records hashes, schema version and required media mounts. The key decrypts SMTP/OpenID configuration and validates authentication sessions, so protect backups as credentials. SQLite backup produces a consistent database with configuration, metadata, cover blobs, accounts, policies, sessions, migration receipts and durable job state. Snapshot finalization uses a self-contained journal format that opens from a read-only mount. Files and atomic manifest publication are synced. The database limit is256MiB and the copy deadline is60seconds.

**Media files are excluded.** Preserve every manifest-listed media folder and the managed `/data/media` directory separately. Managed uploads and downloaded podcast episodes live there. Preserve original read-only source snapshots separately as well. Stop media producers before making a filesystem copy of managed media, or use an appropriate consistent filesystem snapshot. Do not rescan missing files as a replacement for restoring them. The image's environment and deployment mount declarations are host configuration and must be retained with the deployment.

For an offline/operator backup, run `node maintenance.mjs backup` in the image with the installation data volume mounted at `/data`. The command prints the manifest, never the key. `node maintenance.mjs diagnose` checks storage, tools and database integrity without configuration secrets. Startup refuses an incomplete restore marker or a future schema. Schema initialization and upgrades use one SQLite transaction; a failed upgrade rolls back its dataset changes and does not publish the connection.

Restore into a **new empty volume**, preserving the active installation and its volume for rollback:

```sh
docker volume create leafwake-restored
docker run --rm --network none \
  -v /private/backup-folder:/restore:ro \
  -v leafwake-restored:/data \
  leafwake:VERSION node maintenance.mjs restore \
  --backup-dir /restore --id BACKUP_UUID
```

Use the accepted image version or a newer compatible version. The CLI verifies regular files, hashes, key, schema, SQLite integrity, foreign keys and one active owner before touching the destination. It rejects a populated destination. A durable marker prevents startup during an interrupted restore; files are synced before committing the database and removing the marker. Keep the original volume and retry a failed restore into another empty volume. Restore media mounts at their recorded paths before starting the image. Authentication sessions remain available in a fresh-volume restore; durable media jobs recover through normal worker startup. Mounts, job limits and private-host exceptions must be configured intentionally for the restored deployment.

The owner UI also supports in-place database restoration using the same installation key and exact schema. Pause playback and wait for active requests, subscription checks, scans and media jobs. Request accounting waits for both response lifetime and handler settlement, including disconnected clients. Restoration runs in one transaction, revokes authentication sessions and OpenID flows, stops old playback, requeues interrupted media jobs, clears subscription leases and marks scans interrupted. Sign in again afterward. Backups with another key require a new-volume CLI restore. Earlier database-only backups require preservation of their original installation key.

Diagnostics exposes readiness, database integrity/version, storage space, media-tool availability, current mount checks and at most20 generic job failures. It excludes settings, tokens, passwords, remote query strings and raw failure payloads. Mount checks cap at100 libraries and ten folders each, explicitly flag truncation and avoid claiming full readiness when omitted. Public health reports readiness only. Fix storage/tool/mount problems before retrying failed jobs; preserve a suspect volume and restore a validated backup into a new volume when integrity fails.
