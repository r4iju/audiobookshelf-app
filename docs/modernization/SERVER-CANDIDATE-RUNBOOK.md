# Combined 2.30.0 server candidate: promotion and rollback runbook

**Status: promoted locally on October 3, 2026, with explicit owner authorization.** The owner selected “Deploy the verified server candidate,” authorizing the agent to back up config/metadata and deploy the exact candidate below. The execution record is at the end of this document. Physical client acceptance remains separate. Commands below remain a reusable procedure with placeholders; filled values, owner data and backups stay private.

## What would be promoted

| Artifact | Value |
| --- | --- |
| Image tag (local only, never pushed) | `abs-server-candidate:2.30.0-usercache-firstprogress-session` |
| Image ID | `sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4`, linux/arm64 |
| Base | `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03` (2.30.0, revision `29752798`) |
| Layers | the base's 9 layers unchanged, plus one layer per replaced file |
| `server/models/User.js` | base `2174eec7b50b43ed3e0da55c4e54edaa90f9f98c30cefb9b4819430b744f6a1d`, candidate `d36db80057337ae071a436a7753cb3aa024e97373e8d4cc9e805d1c048486097` |
| `server/managers/PlaybackSessionManager.js` | base `e196eea6e727fbe634a985ee475f5f50782069e6debc4a81f7a2517114885428`, candidate `a140b5679a81e8b48b3485f6bd7e2bee0c20fb6bd79819a61279e465c8f685ae` |
| Patches, in order | Apple user cache `b59ea8c8…0a94` (`evidence/apple-real-server/server-usercache`), session-only first progress `ed88f5e0…8fcb` (`evidence/web-real-server/server-combined`) |
| Saved image | `abs-server-candidate-2.30.0-usercache-firstprogress-session.tar`, SHA-256 `4e8d60b873dae59ceed49ff991a16c8eb4fa32eccf4196db72b723f4483f02a6`, in the private package beside the earlier candidate, with the build context and both patches |
| Source of the proof | Original #94/#101/#102/#103 evidence at `a23db59b`; session-scoped correction #119 at `481acf98`; exact packaged Apple five-case proof #122 using client `d3152a5d`. See `SERVER-COMPATIBILITY.md` for per-row provenance. |
| Held, not for promotion | `abs-server-candidate:2.30.0-usercache-firstprogress`, `sha256:c649a2bd…9abd` (`User.js` `15ee2c33…ac4`). It stores progress first created by PATCH within 10 s of the end as finished. Kept unchanged as historical evidence. |

The candidate changes no database schema and adds no migration: the database it writes is the database 2.30.0 reads. That is what makes rollback to the pinned base image safe without restoring data.

## Gates before promotion

All must hold. The compatibility matrix is in `SERVER-COMPATIBILITY.md`. Gate 1 now has scoped synthetic evidence for every listed client, including the exact packaged Apple run in #122. Owner review, physical acceptance and execution remain separate; this evidence does not authorize or perform promotion.

1. Every completed client is green against **this** image, `cd703e87`, on a synthetic server: Apple affected native cases, Android `RealServerJourney`, the controlled progress and cache checks, and the Next.js production journeys. Passes on the held `c649a2bd` do not count.
2. The owner has reviewed both patches and the known limits in `evidence/android-real-server/server-first-progress/README.md` and `evidence/web-real-server/server-combined/README.md`.
3. The owner accepts that physical-device acceptance (playback, background controls, downloads, readers) happens **after** promotion, on the owner's devices, and is part of this runbook's verification, not of the synthetic matrix.
4. The image ID and `User.js` hash verify on the machine that runs the server (step 1 below).

## Promotion steps (owner or explicitly authorized operator)

Placeholders: `$COMPOSE` the compose file, `$SERVICE` and `$CONTAINER` the server's service and container name, `$DATA` the directory holding its `config` and `metadata` bind mounts, `$BACKUP` a backup directory on another disk, `$PKG` the private candidate package.

```sh
CANDIDATE=abs-server-candidate:2.30.0-usercache-firstprogress-session
CANDIDATE_ID=sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4
BASE=ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03
STAMP=$(date +%Y%m%d-%H%M%S)

# 1. Verify the artifacts. Load from the saved tar only if the image is missing, after checking the tar.
docker image inspect "$CANDIDATE" --format '{{.Id}}' \
  || { test "$(shasum -a 256 "$PKG/abs-server-candidate-2.30.0-usercache-firstprogress-session.tar" | cut -d' ' -f1)" \
            = 4e8d60b873dae59ceed49ff991a16c8eb4fa32eccf4196db72b723f4483f02a6 \
       && docker load -i "$PKG/abs-server-candidate-2.30.0-usercache-firstprogress-session.tar"; }
test "$(docker image inspect "$CANDIDATE" --format '{{.Id}}')" = "$CANDIDATE_ID"
docker run --rm --pull=never --network none --entrypoint sha256sum "$CANDIDATE" \
  /app/server/models/User.js /app/server/managers/PlaybackSessionManager.js
#    must print d36db800…6097 and a140b567…85ae
docker image inspect "$BASE" --format '{{.Id}}'   # the rollback image must be present locally too

# 2. Record what runs now.
docker inspect "$CONTAINER" --format '{{.Image}} {{.Config.Image}}' | tee "$BACKUP/abs-before-$STAMP.txt"
cp "$COMPOSE" "$BACKUP/compose-before-$STAMP.yml"

# 3. Back up with the server stopped, so the SQLite database is consistent.
#    Optionally first take the server's own backup in Settings > Backups.
docker compose -f "$COMPOSE" stop "$SERVICE"
tar -C "$DATA" -czf "$BACKUP/abs-config-metadata-$STAMP.tgz" config metadata
shasum -a 256 "$BACKUP/abs-config-metadata-$STAMP.tgz" | tee -a "$BACKUP/abs-before-$STAMP.txt"
tar -tzf "$BACKUP/abs-config-metadata-$STAMP.tgz" | grep -cx 'config/absdatabase.sqlite'   # must be 1
#    Stop here if tar reported any error (for example root-owned files): the backup is incomplete.

# 4. Switch the service to the candidate, pinned and never pulled. In $COMPOSE, for $SERVICE only:
#      image: abs-server-candidate:2.30.0-usercache-firstprogress-session
#      pull_policy: never
docker compose -f "$COMPOSE" up -d --no-deps --pull never "$SERVICE"

# 5. Verify what actually runs.
test "$(docker inspect "$CONTAINER" --format '{{.Image}}')" = "$CANDIDATE_ID"
docker exec "$CONTAINER" sha256sum /app/server/models/User.js /app/server/managers/PlaybackSessionManager.js
curl -fsS http://127.0.0.1:<published port>/status     # serverVersion 2.30.0, isInit true
docker logs --since 5m "$CONTAINER" 2>&1 | grep -iE 'error|exception' || true
```

Then the owner's acceptance, on the owner's devices and accounts:

- browser: sign in, open an item, play, pause, reload and resume; a book with no progress yet starts and its progress appears; a position set from another device near the end of a short item with no progress yet stays unfinished;
- iPhone/iPad and Android: resume a book, finish one, and confirm it stays finished after reconnecting; an offline session synced later creates the row with the right position;
- Apple TV: resume and progress persistence;
- another device sees progress without reloading.

## Rollback

Rollback is image-only unless data is damaged. The candidate writes the same schema, so progress recorded while it ran stays valid on 2.30.0.

```sh
# Image-only rollback: keeps everything written since promotion.
#   In $COMPOSE, for $SERVICE: image: <the BASE digest above>, pull_policy: never
docker compose -f "$COMPOSE" up -d --no-deps --pull never "$SERVICE"
test "$(docker inspect "$CONTAINER" --format '{{.Image}}')" = "sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03"
docker exec "$CONTAINER" sha256sum /app/server/models/User.js /app/server/managers/PlaybackSessionManager.js
#    2174eec7…a1d and e196eea6…5428

# Data restore, only if the data itself is damaged. Loses everything written since the backup.
# The compose image must already name the base digest (image-only rollback above) before the final up.
docker compose -f "$COMPOSE" stop "$SERVICE"
mv "$DATA/config" "$DATA/config.failed-$STAMP"; mv "$DATA/metadata" "$DATA/metadata.failed-$STAMP"
tar -C "$DATA" -xzf "$BACKUP/abs-config-metadata-$STAMP.tgz"
docker compose -f "$COMPOSE" up -d --no-deps --pull never "$SERVICE"
```

## Risks

- **Downtime between steps 3 and 5.** The server is stopped from the backup until the candidate starts. If the compose edit is wrong, `up` fails and the server stays down: restore `$BACKUP/compose-before-$STAMP.yml` and `up` again.
- **A floating tag.** If the service names `audiobookshelf:latest`, any `docker compose pull` or `up --pull always` replaces both the base and the candidate with whatever upstream publishes. Pin by tag or digest with `pull_policy: never`, for the candidate and for rollback alike.
- **Local-only image.** The tag exists only on this machine. Keep the saved tar and its checksum with the backup; a pruned image is restored from the tar, not rebuilt.
- **arm64 only.** The image runs on the Studio's arm64 Docker. Another host needs a fresh build and fresh verification.
- **The next upstream release.** A later upstream image does not contain these patches unless upstream fixed the same defects. Before moving off this candidate, run the same matrix against that release; the pinned 2.30.0 failures (cold-cache race, first progress) are the regression checks.
- **Restoring data costs progress.** A data restore discards progress since the backup, including progress synced from offline devices afterwards. Prefer the image-only rollback.
- **Synthetic matrix only.** The matrix used synthetic libraries and accounts. Owner libraries, real devices and physical media controls are verified only by the owner's acceptance after promotion.

## Local promotion record (October 3, 2026)

- Exact `cd703e87` image and both patched file hashes verified before and after deployment. The retained pinned base was tagged and saved as a local rollback image archive; the candidate image archive checksum matches the recorded package.
- Only the server was stopped for a consistent config/metadata archive. All 517 application files matched the stopped source byte-for-byte, with the SQLite database present. macOS metadata entries were retained. An initial comparison rejected those extra metadata entries and automatically restarted the exact base; the corrected comparison then passed before promotion.
- The local compose service persists the candidate tag with `pull_policy: never`. No port, mount, network, account or API contract changed. The existing frontend and nginx image/start times are unchanged.
- Read-only HTTP and trusted HTTPS deployment checks each passed 4/4: frontend/static asset, server status (2.30.0 initialized), live-updates endpoint and server interface. Startup recorded one invalid socket-token rejection; no database/schema failure was observed. Physical authentication/playback acceptance is still required.
- No owner-account playback, progress mutation, device launch, data restore or legacy retirement was performed. The synthetic compatibility matrix was reused, not repeated against owner data. This promotion does not close platform readiness tickets.
