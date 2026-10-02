# Combined 2.30.0 server candidate: promotion and rollback runbook

**Status: reviewable, not executed.** Nothing here has been run against the owner's server, container, compose file or data. Promotion needs the owner's explicit decision, and the owner runs every step below. Commands use placeholders for the owner's own names and paths; a filled-in private copy is kept outside the repository with the rest of the private evidence.

## What would be promoted

| Artifact | Value |
| --- | --- |
| Image tag (local only, never pushed) | `abs-server-candidate:2.30.0-usercache-firstprogress-session` |
| Image ID | `sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4`, linux/arm64 |
| Base | `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03` (2.30.0, revision `29752798`) |
| Layers | the base's 9 layers unchanged, plus one layer per replaced file |
| `server/models/User.js` | base `2174eec7b50b43ed3e0da55c4e54edaa90f9f98c30cefb9b4819430b744f6a1d`, candidate `d36db80057337ae071a436a7753cb3aa024e97373e8d4cc9e805d1c048486097` |
| `server/managers/PlaybackSessionManager.js` | base `e196eea6e727fbe634a985ee475f5f50782069e6debc4a81f7a2517114885428`, candidate `a140b5679a81e8b48b3485f6bd7e2bee0c20fb6bd79819a61279e465c8f685ae` |
| Patches, in order | Apple user cache `b59ea8c8…0f94` (`evidence/apple-real-server/server-usercache`), session-only first progress `ed88f5e0…8fcb` (`evidence/web-real-server/server-combined`) |
| Saved image | `abs-server-candidate-2.30.0-usercache-firstprogress-session.tar`, SHA-256 `4e8d60b873dae59ceed49ff991a16c8eb4fa32eccf4196db72b723f4483f02a6`, in the private package beside the earlier candidate, with the build context and both patches |
| Source of the proof | `fork/native-tv` at `a23db59b` (#94, #101, #102, #103) and this change |
| Held, not for promotion | `abs-server-candidate:2.30.0-usercache-firstprogress`, `sha256:c649a2bd…9abd` (`User.js` `15ee2c33…ac4`). It stores progress first created by PATCH within 10 s of the end as finished. Kept unchanged as historical evidence. |

The candidate changes no database schema and adds no migration: the database it writes is the database 2.30.0 reads. That is what makes rollback to the pinned base image safe without restoring data.

## Gates before promotion

All must hold. The compatibility matrix is in `SERVER-COMPATIBILITY.md`.

1. Every completed client is green against **this** image, `cd703e87`, on a synthetic server: Apple affected native cases, Android `RealServerJourney`, the controlled progress and cache checks, and the Next.js production journeys. Passes on the held `c649a2bd` do not count.
2. The owner has reviewed both patches and the known limits in `evidence/android-real-server/server-first-progress/README.md` and `evidence/web-real-server/server-combined/README.md`.
3. The owner accepts that physical-device acceptance (playback, background controls, downloads, readers) happens **after** promotion, on the owner's devices, and is part of this runbook's verification, not of the synthetic matrix.
4. The image ID and `User.js` hash verify on the machine that runs the server (step 1 below).

## Steps (owner only)

Placeholders: `$COMPOSE` the compose file, `$SERVICE` and `$CONTAINER` the server's service and container name, `$DATA` the directory holding its `config` and `metadata` bind mounts, `$BACKUP` a backup directory on another disk, `$PKG` the private candidate package.

```sh
CANDIDATE=abs-server-candidate:2.30.0-usercache-firstprogress-session
CANDIDATE_ID=sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4
BASE=ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03
STAMP=$(date +%Y%m%d-%H%M%S)

# 1. Verify the artifacts. Load from the saved tar only if the image is missing, after checking the tar.
docker image inspect "$CANDIDATE" --format '{{.Id}}' \
  || { shasum -a 256 "$PKG/abs-server-candidate-2.30.0-usercache-firstprogress-session.tar"; \
       docker load -i "$PKG/abs-server-candidate-2.30.0-usercache-firstprogress-session.tar"; }
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
tar -tzf "$BACKUP/abs-config-metadata-$STAMP.tgz" | grep -c absdatabase.sqlite   # must be 1

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

- browser: sign in, open an item, play, pause, reload and resume; a book with no progress yet starts and its progress appears; a position set from another device near the end of a short item stays unfinished;
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
docker compose -f "$COMPOSE" stop "$SERVICE"
mv "$DATA/config" "$DATA/config.failed-$STAMP"; mv "$DATA/metadata" "$DATA/metadata.failed-$STAMP"
tar -C "$DATA" -xzf "$BACKUP/abs-config-metadata-$STAMP.tgz"
docker compose -f "$COMPOSE" up -d --no-deps --pull never "$SERVICE"
```

## Risks

- **A floating tag.** If the service names `audiobookshelf:latest`, any `docker compose pull` or `up --pull always` replaces both the base and the candidate with whatever upstream publishes. Pin by tag or digest with `pull_policy: never`, for the candidate and for rollback alike.
- **Local-only image.** The tag exists only on this machine. Keep the saved tar and its checksum with the backup; a pruned image is restored from the tar, not rebuilt.
- **arm64 only.** The image runs on the Studio's arm64 Docker. Another host needs a fresh build and fresh verification.
- **The next upstream release.** A later upstream image does not contain these patches unless upstream fixed the same defects. Before moving off this candidate, run the same matrix against that release; the pinned 2.30.0 failures (cold-cache race, first progress) are the regression checks.
- **Restoring data costs progress.** A data restore discards progress since the backup, including progress synced from offline devices afterwards. Prefer the image-only rollback.
- **Synthetic matrix only.** The matrix used synthetic libraries and accounts. Owner libraries, real devices and physical media controls are verified only by the owner's acceptance after promotion.
