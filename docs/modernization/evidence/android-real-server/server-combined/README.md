# Combined 2.30.0 server candidate: Apple user cache + Android first progress

A candidate only. It is not applied to any owner server, and nothing here is resolved on one.

## Inputs

| Input | SHA-256 |
| --- | --- |
| Pinned image `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03`, `server/models/User.js` | `2174eec7b50b43ed3e0da55c4e54edaa90f9f98c30cefb9b4819430b744f6a1d` |
| Apple `apple-real-server/server-usercache/usercache-candidate-3ef58609.patch` | `b59ea8c83dceaece79b33abc72159abf9d6d4537b24b519f243c8fae74f50a94` |
| Android `server-first-progress/first-progress-candidate.patch` | `6313948fcce74d83ad7b320da1db0b587bb81557892cabdaad1207237cdf7367` |
| **Combined `User.js`** (Apple's patch, then Android's) | **`15ee2c33d88fab0e6e8e43d9ffe3c7eddb272ea6ba3f11906cabeb455c0ffac4`** |
| Apple `instrumentation-candidate-3ef58609.patch` / `instrumentation-pristine.patch` (race DIAG lines only) | `e0963eb2…3629` / `6c94ced9…afb` |
| Instrumented combined / pristine `User.js` | `304b2502…405b` / `0948e73f…ecb8` |

Applying Apple's patch alone gives `3ef58609…`, the file Apple tested. Apple's patch applies exactly. The Android patch then applies without fuzz, 19 lines lower, because Apple's patch adds lines above it. Apple's candidate instrumentation applies after both. Its last hunk reports fuzz 1 only because the two Android lines sit inside its context, and its log line still lands right after the create branch.

## Runner

`run-combined.sh` builds the files and checks the pristine file, both candidate patches and the combined file against the hashes above, then stops on any mismatch. It records the instrumentation hashes but does not pin them. It reads Apple's files without changing them, from `APPLE_USERCACHE_DIR` (default: this checkout's `apple-real-server/server-usercache`). Servers are this lane's own `abs-android-qa` (127.0.0.1:28870), freshly seeded with synthetic data by the unmodified `web/qa/server.mjs`, behind `require-local-image.sh`.

Modes:
- `assemble` builds and verifies the files.
- `seams pristine|combined` runs Apple's three user-cache seam checks inside the image, with no network.
- `progress pristine|combined` runs `first-progress-check.mjs`.
- `race pristine|combined` runs the cold-cache race, following the steps of Apple's `diag-race.sh` with Apple's instrumentation:
  1. Set an unfinished position.
  2. Restart, so the cache is empty.
  3. Race a finishing `local-all` session against `GET /api/me`.
  4. Read the position immediately, 3 s later, and after another restart.

  A try is stale when the read 3 s later is still unfinished.
- `native pristine|combined` runs Android `RealServerJourney` a-d.
- `down` removes the container.

## Preliminary results (before Apple's evidence merged)

Apple's files were read from Apple's own checkout (`audiobookshelf-final-mobile-qa` at dc22a79e) with the hashes above. The runner was on `fork/android-combined-server-candidate` from `fork/native-tv` 767a3d62. These runs validate the controls. They are not the merged-source proof.

| Control | Pristine 2.30.0 | Combined |
| --- | --- | --- |
| Apple seam checks (concurrent load, invalidation during load, delayed write) | 3 of 3 fail | 3 of 3 pass |
| `first-progress-check.mjs` | 7 of 8 fail | 8 of 8 pass |
| Cold-cache race, 10 tries | 4 of 10 stale (the cached copy that a second load replaced took the finish; every read after a restart is finished) | 0 of 10 stale; every read finished |
| Android `RealServerJourney` a-d | not rerun (a-c pass, d fails at f583677a) | waits for the merged source |

Outputs are under `/Volumes/ai-ssd/developer-caches/abs-android-native-claude/artifacts/combined-candidate/`, outside the repository.

## Still to do

The merged-source proof runs once Apple's evidence is in `fork/native-tv`, from the in-repo Apple path. It covers the seams, the eight first-progress cases, the race and the Android a-d.

Not covered:
- owner servers and libraries;
- a physical device;
- the review's limits on the first-progress patch (see `server-first-progress/README.md`).
