# Apple native apps against a real Audiobookshelf 2.30.0 server

## CURRENT (2026-10-02)

**The affected Apple native software gate passes: 5/5 on the exact session-scoped packaged server.**
Client source: `d3152a5d3bc0eb7c23bf77e835088d650df514a3` (merged PR #121).
Server source amendment: merged PR #119 (`481acf981c6438033cde1f9ef5205e1221638b34`), packaged image
`sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4`.
The cached image was used unchanged, without a network pull, `docker cp`, source overlays or bind overrides.
Inspection before and after the cases pins the image and allows only `/library`, `/podcasts`, `/config`
and `/metadata` mounts, all synthetic disposable data. The library is read-only.

| Existing affected case | Native exit | Observed result |
| --- | ---: | --- |
| `test1SignInBrowseAndStreamAcrossFiles` | 0 | Restored sign-in, multi-file streaming, first progress 37.473 s, unfinished |
| `test4aDownloadForOffline` | 0 | Multi-file book available offline |
| `test4dFinishOfflineWithServerStopped` | 0 | Starts unfinished in file 2, reaches file 3/end with zero remaining |
| `test4eReconnectPublishesTheFinish` | 0 | Server returns 90.2008167755102 s, finished; unchanged after another restart |
| `testPendingLegacyListeningReachesTheRealServerExactlyOnce` | 0 | Three sessions acknowledged; second sync has nothing pending or unconfirmed; listening totals 25/11/3 s, positions 25/11/3.5 s; newer legacy position 2 s uploaded, newer server position 3 s preserved |

The runner exits 0 and records every native command's own status. One pass does not demonstrate that a
cache race occurred. Existing controlled/race, browser and Android passes are retained from their original
sources and were not rerun. The old `c649a2bd` 5/5 is historical and cannot count for this image; that image
is held because of its browser first-PATCH regression.

Unchanged packaged source SHA-256:

- `/app/server/models/User.js`: `d36db80057337ae071a436a7753cb3aa024e97373e8d4cc9e805d1c048486097`.
- `/app/server/managers/PlaybackSessionManager.js`: `a140b5679a81e8b48b3485f6bd7e2bee0c20fb6bd79819a61279e465c8f685ae`.

Reproduce using the cached image, local Xcode/XcodeGen and `sim`, from an external-SSD checkout:

```sh
ABS_RS_OUT=/path/on/external-ssd/unique-evidence \
ABS_RS_DERIVED=/path/on/external-ssd/owned-derived \
  docs/modernization/evidence/apple-real-server/server-combined/run-packaged-native.sh
```

No new tests or app fixes were added. The runner reuses the existing probe sources and seeded fixtures,
leases a pooled iPhone, then releases it and removes only its owned container/volumes. Logs, result bundles,
exact source hashes and both Arabic failures remain private. Public proof hashes:

- Five-case `results.txt`: `a5e6324f90d010101f45dae597440151be7af26c08190ab6279dd1f089b8f1d8`.
- `runner-output.txt`: `8a504175f0446a982dd01f044f629314de6bfb38906fbf7612dc4ac3cede982a`.
- `source-hashes.txt`: `d56577d72f893a14b7106fc3e8a0b3beb43d3712ef09f48ed2d5d2823bedd9fe`.
- Executed runner: `cbc6f4187f366f38b08904eeeecc0a148c68cb2d53a6b7e0dafda14fd3e7f6f6`.

**Separate open gates:** owner server promotion/acceptance, physical audio routes/system controls,
owner-library and real legacy migration/rollback acceptance, assistive-technology and native-speaker review.
The [Arabic render failure](APPLE-LOCALIZATION-READINESS.md#current-2026-10-02) remains excluded from acceptance.
The owner server was not changed, and this bounded pass does not close Phase 1 or replace the original criteria.

## Historical real-server evidence

Before this run, every native journey had been tested only against the Python and Node fixtures. This run uses the production iPhone app, the production TV app and the production migration adoption code against the real server image recorded in `SERVER-COMPATIBILITY.md`.

The setup is local, isolated and synthetic. It establishes no owner-library, owner-device, physical-hardware, OpenID-provider, SMTP or real-legacy-data acceptance.

## Setup

- **Source:** `68842296` (origin/fork/native-tv) for the first attempts, then the runner revisions `386fed27` and `97bac3e3` of this branch for the fresh-checkout runs. The probes add test sources only; no app code changed.
- **Server:** the locally present pinned image `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53…` (2.30.0), with no network pull. It is started by the web real-server harness `web/qa/server.mjs` under its own name and ports:
  - container: `ABS_QA_CONTAINER=abs-apple-qa`
  - main port: `ABS_QA_PORT=19890`
  - helper ports: 19894 to 19896
  - volumes: the named volumes `abs-apple-qa-{config,metadata,podcasts}`, plus the synthetic library that `web/qa/make-library.sh` generates inside the checkout on the external SSD
- **Untouched:** the owner's `audiobookshelf` container and the web thread's `abs-web-qa` containers. Only `abs-apple-qa` was created, stopped, started, restarted and removed.
- **Data:**
  - the generated synthetic library: 69 books, 1 podcast with 4 episodes, MP3 audio and PDFs
  - the harness's synthetic accounts `qa` and `qa-other`
- **Devices:** pooled simulators leased with `sim acquire`: Pool iPhone 1 (iOS 27.0) and a pooled Apple TV that the TV runner leases and erases itself.
- **Probes:** XCTest classes run with `-only-testing`. They are not added to the suites. Their sources live in `evidence/apple-real-server/` and are copied into the test targets only for a run. Each probe reads results from the server's own API (`/api/me/progress`, `/api/me/item/listening-sessions`, `/api/me`). Seeded ids are looked up by title on each server, not hardcoded.
- **Evidence:**
  - logs and result bundles of the first attempts are in the ignored `apple/build-qa/real-server/` folder of the QA worktree; those of the fresh-checkout runs are in `apple/build-qa/real-server-repro/` of each fresh worktree
  - the committed folder holds the runners, their combined output (`runner-output.txt`, `fresh-run-*-output.txt`), the server-side setup output, the server log excerpts and the reproductions

## Reproducing

From any checkout, with the pinned image present locally and the `sim` pool available:

```sh
docs/modernization/evidence/apple-real-server/run-all.sh
```

`common.sh` finds the repository root through git. `run-all.sh` recreates the owned container and its volumes, regenerates the synthetic library, seeds the accounts, resolves the seeded ids by title, installs the probes, leases a phone and runs every case below in order. It removes the probes and releases the phone on exit, and leaves the container up for inspection; `server_down` in `common.sh` removes it.

Each case is recorded with its own xcodebuild exit status in `results.txt`. Every case runs even after a failure, and the runner exits non-zero if any case or server step failed. The runners at `386fed27` did not: `xcode_phone` and `tv` returned the status of the `grep` that printed the results, and `run-all.sh` did not combine them, so the `386fed27` run below printed exit 0 with two failed cases. `evidence/apple-real-server/exit-status/` demonstrates this with a stub xcodebuild that fails with 65: before the fix `phone()` returned 0; after it, `phone()` returns 65 and the runner exits 1. A passing stub still exits 0 (`exit-status/output.txt`).

The other runners in the folder (`run-phone.sh`, `run-rest.sh`, `run-reruns.sh`, `run-migration.sh`, `run-tv-rerun3.sh`) are the first attempts' sequences on the same `common.sh`.

## Results of the first attempts

Every attempt in the original QA worktree is listed, including the failures. Where the fault was in the probe, the correction is stated. Assertions were corrected, not loosened. Not every corrected probe was run again there: the corrected offline step (`test4b`) was first run in the fresh-checkout runs below.

| Case | Attempts | Result in the first attempts | Evidence |
| --- | --- | --- | --- |
| **Phone: sign in, browse, stream.** Sign in, then relaunch restores the account. The catalog reports 69 items, and an item from the server's second page is reachable. A multi-file book streams across a file boundary. The server position is within 3 s of the app's, and listening time is recorded. | 1 | Pass | `phone-online.{log,xcresult}` |
| **Phone: PDF.** A PDF opens in the native reader. Page 3 is saved to the server (`ebookLocation`, `ebookProgress`), and a relaunch reopens page 3. | 1 | Pass | `phone-online.*` |
| **Phone: podcast episode.** A podcast episode streams, and the server saves progress for that episode only. | 4 | Pass on the fourth attempt. The first two read time labels that the single-file episode player does not show (`total-elapsed` in `phone-online`, then `chapter-elapsed` in `podcast-rerun`; the right one is `playback-elapsed`). The third (`podcast-rerun2`) failed its podcast-level check, which misread the server: 2.30 answers `/api/me/progress/<podcast>` with an episode's row. The check now reads `/api/me`, where every row for the podcast has an `episodeId` (`podcast-progress-api.txt`). The fourth (`podcast-rerun3`) passed. | `phone-online.*`, `phone-podcast-rerun{,2,3}.*` |
| **Phone: download, then offline with the server stopped, then reconnect.** The download completes. With the container stopped, the downloaded book plays from the server position and crosses into its third file. After the container restarts, a relaunch publishes the offline listening: the server position is at least 60 s and the session is recorded. | 2 | Partial. The download passed both times. The offline step failed both times: in the first run the probe skipped from 37 s past the end of the 90 s book (see the observation below); in the second (`offline-rerun`, exit 65) its final assertion misparsed "1 min" as "1". Reconnect failed the first time (the server read stayed at 37.4 s) and passed the second (74.6 s). The corrected offline probe, which skips only until "File 3 of 3" and asserts the label "1 min", was not run in this worktree; it passes in both fresh-checkout runs. | `phone-{download,offline,reconnect}{,-rerun}.*` |
| **TV: search and podcast episode.** Server search finds "Salt and Signal", and its details open. A podcast episode plays with the remote, and the server records that episode's progress (0 to 6.8 s). | 1 | Pass | `tv.{log,xcresult}` |
| **TV: resume a server position.** Continue Listening shows the server's saved position. Playback resumes there, Previous chapter moves into the second file, and the server records the TV's position. | 4 | Pass on the fourth attempt. The TV resumed at 64 s against a server position of 63.7 s (chapter 3 of 3) and moved to chapter 2. The server then recorded 34.3 s, inside the second file. That server position was left by the third attempt's TV session. Each attempt starts on an erased leased TV with a reset sign-in, so it came from the server, not local state. The first attempt hit the known tvOS sign-in keyboard focus flake (`TVJourney.swift`, as recorded in `APPLE-LOCALIZATION-READINESS.md`). The second resumed from the phone's 75 s position, then asked for Next chapter while already in the last chapter, where the control is correctly disabled. The third reached playback, but Previous first restarted the current chapter (intended when more than 3 s in), and the probe then read a label after Stop closed Now Playing. | `tv.*`, `tv-resume-rerun{,2,3}.*` |
| **Migration upload as `qa-other`.** The production `LegacyMigrator`, `LegacyArchive` and `NativeMigrationAdoption` are signed in with a real `URLSession`. | 2 | Pass on the second run (details below). In the first run, the fixture dated the legacy app's last update about 50 s before its own last server sync for the restarted session. The adoption code then correctly refused to overwrite a server row written later, and kept it as unconfirmed. | `migration{,-rerun}.{log,xcresult}`, `migration-setup{,-rerun}.txt` |

### Observation in the first attempts: a finish the server stored, but did not return

In the first offline run, the probe skipped past the book's end, so the app's offline session on "The Long Tide" ended at 90.2 s of 90.2 s. The server log excerpt (`first-run-server-log-excerpt.txt`) shows what followed:

- 07:52:18, on reconnect: the server synced the app's session, updated the progress to 90.2 s ("previously 37.4"), and marked it finished.
- 07:52:20 to 07:56:04, in the same server process: every read of `/api/me/progress` still returned 37.4 s, unfinished, with the earlier `lastUpdate`. The probe failed on that. The second attempt's download then resumed offline from 39 s, the stale value.
- 07:57:11, in a fresh process after the stop and start: syncing the second attempt's 74.6 s session logged "previously 90.2". The database had held the finish, and the 74.6 s session then replaced it.

So the finish was stored, but that server process kept returning the earlier progress, and the app downloaded from it. The fresh-checkout run at `97bac3e3` reproduced this, and the cause was then found in the server (below). Those container logs were destroyed when a later `server_fresh` recreated the container; the excerpt was recovered from saved tool output, with its provenance stated in the file.

`repro-finish-after-restart.sh` does not test this transition: its corrected run started from a row that was already finished (`repro-finish-after-restart.txt`, Catalog Volume 02). Its earlier attempts used a session time older than their own PATCH and were correctly skipped by the server (`repro-finish-after-restart-stale-time.txt`).

## Fresh-checkout runs

Both runs use `run-all.sh` from a new worktree on the SSD, a recreated container and freshly generated data. They add two cases on the same item after the earlier ones: `test4d` plays the downloaded "The Long Tide" offline from its unfinished server position after the TV case (74.8 s at `386fed27`, 34.4 s at `97bac3e3`) to the end with the server stopped, and `test4e` relaunches after the server returns and requires the server's own progress row to be finished at the end, and a session reaching the end to be recorded. The server's view is then read again after a further restart.

### At `386fed27`

`fresh-run-386fed27-output.txt`, `fresh-run-386fed27-server-long-tide.txt`, `fresh-run-386fed27-ids.txt`. The wrapper printed exit 0; the individual results were:

| Case | Exit | Result |
| --- | --- | --- |
| online (tests 1 to 3) | 0 | Pass |
| download | 0 | Pass |
| offline (corrected `test4b`) | 0 | Pass: started at 39 s, reached 1 min in the third file |
| reconnect | 0 | Pass: server 74.8 s, unfinished |
| TV | 65 | `test1` failed on the tvOS sign-in keyboard focus flake; `test2` passed (episode saved 7.8 s) |
| finish offline (`test4d`) | 65 | Probe fault: at the end the player shows no `total-elapsed`. It had reached "File 3 of 3". The probe now checks `playback-remaining` is "−0 sec". The failed read came after playback had ended, so the finished session existed for `test4e`. |
| finish reconnect (`test4e`) | 0 | Pass: server 90.2 s of 90.2 s, `isFinished` true |
| after a further restart | | 90.2 s, `isFinished` true |
| migration | 0 | Pass, same figures as below |

Not a clean run: two cases failed.

### At `97bac3e3`

`fresh-run-97bac3e3-output.txt`, `fresh-run-97bac3e3-results.txt`, `fresh-run-97bac3e3-server-long-tide.txt`, `fresh-run-97bac3e3-finish-window.txt`, `fresh-run-97bac3e3-ids.txt`. The runner exited 1, from its own aggregation:

| Case | Exit | Result |
| --- | --- | --- |
| online (tests 1 to 3) | 0 | Pass |
| download | 0 | Pass |
| offline (corrected `test4b`) | 0 | Pass: started at 39 s, reached 1 min in the third file |
| reconnect | 0 | Pass: server 74.7 s, unfinished |
| TV, both cases | 0 | Pass: resumed at 75 s in chapter 3 against the phone's 74.7 s, moved to chapter 2, server 30.1 s; episode saved 7.2 s. The server then held 34.4 s, unfinished, from the TV. |
| finish offline (`test4d`) | 0 | Pass: from "File 3 of 3" to "−0 sec" remaining, with the server stopped |
| finish reconnect (`test4e`) | 65 | **Fail.** For 60 s the server returned 34.4 s, unfinished, with the TV's `lastUpdate` |
| after a further restart | | 90.2 s, `isFinished` true, `lastUpdate` of the app's finished session |
| migration | 0 | Pass, same figures as below |

Not a clean run: `test4e` failed. Its server log (`fresh-run-97bac3e3-finish-window.txt`) shows the same pattern as the first attempts. The server had just started (08:39:38). The app's socket connected at 08:40:00.204, and its finished session was synced at 08:40:00.220: progress updated to 90.2 s ("previously 34.4") and marked finished. No later write to that row appears, yet every read in that process returned 34.4 s. The process started by the restart returned 90.2 s, finished.

### The cause: a user-cache race in the 2.30.0 server

The stale value differs between runs and is always the row as it stood before the finish: 34.4 s at `97bac3e3`, left by the TV case, and 37.4 s in the first attempts, left by the phone's earlier streaming.

**From the source** (`server/models/User.js` in the pinned image):

- `GET /api/me/progress` answers from the in-memory user object (`req.user.getOldMediaProgress`), which comes from the server's user cache.
- On a miss, `getUserById`, `getUserByIdOrOldId`, `getUserByUsername`, `getUserByEmail` and `getUserByOpenIDSub` each await their own database load and then store that object, marking it `fromCache`. Two requests that miss at once each get their own object, and the one stored last replaces the other in the cache.
- A progress update changes the object its own request holds. `userCache.maybeInvalidate` evicts only objects without `fromCache`, so an object displaced from the cache is never evicted, and reads keep answering from the other one until the server restarts.

Right after a server start, the app's socket authentication and its pending-session sync are two such requests (`fresh-run-97bac3e3-finish-window.txt`: socket at 08:40:00.204, sync at .220).

**Confirmed with instrumentation.** These checks ran in a separate owned container, `abs-apple-diag` on 127.0.0.1:19900, from the same pinned image and harness with its own volumes. Its `User.js` logs which user object each request stores, updates and reads (`server-usercache/instrumentation-*.patch`). `server-usercache/diag-race.sh` runs the cold-cache race: each try leaves "The Long Tide" unfinished, restarts the server, then sends a finishing `local-all` session and a plain `GET /api/me` at the same moment.

On the pinned server, 8 of 10 tries returned the unfinished row (`server-usercache/race-10-pristine.txt`). Each stale try shows two `cache.set` lines for two objects, the finish applied to the first (`progress update on inst=ow9t1 … cached=zk6s1 progress=[[90.2,true]]`), and the reads answered by the second (`progress read on inst=zk6s1 progress=[[0,false]]`). In those tries the un-finishing PATCH had left the row at 0 s rather than the 34 s it sent; that handling was not examined further. After a restart the finished row was returned in every try.

`server-usercache/concurrent-load-check.js` checks the same thing without a database. It runs in the pinned image with a stubbed loader, and two concurrent `getUserById` calls must get the object the cache keeps. On the pinned file it fails: the first request holds load 1, still marked `fromCache`, while the cache holds load 2 (`concurrent-load-check.txt`).

The app sent the right session each time, and the server stored it. The first attempts' 07:52 finish also came 22 s after a server start. Those logs are gone, so whether the race happened there is not known.

The earlier checks on the QA server itself, with no app and no instrumentation:

- `repro-finish-transition.sh` (`repro-finish-transition.txt`): on a warm server, a second device leaves the book unfinished at 34 s, then a newer `local-all` session finishes it. Every read is right at once. A warm cache does not exclude the race; it only has no concurrent miss.
- `repro-cold-cache-race.sh` (`repro-cold-cache-race.txt`): the same race without instrumentation, stale on the second try.

### Candidate server fix, not promoted

The current candidate is `server-usercache/usercache-candidate-3ef58609.patch`. It changes only `server/models/User.js` of the pinned 2.30.0 image. Applied to the pinned file (SHA-256 `2174eec7…`), it gives `3ef58609…`. It keeps one user object per cached user, and never caches or returns a load that a change to that user overlapped:

- **One object per user.** All five lookups load through `UserCache.load`. A load that finishes after another load for the same user was cached returns the cached object.
- **Changes during a load.** `UserCache.delete` stamps the user's invalidation. A load overlapped by a stamp is repeated and checked against the cache again. Only a change to the same user causes a reload. After three overlapped loads in a row, the last is returned uncached, like any read that overlaps a write. The stamps are kept per user id.
- **Writes still in flight.** `update`, `save` and `destroy` invalidate before their database write, as before, and again once it settles (`finally`), so a load that read the row during the write is not kept. For the cached object itself both calls do nothing, since it already holds its own changes.
- **Displaced objects.** `maybeInvalidate` also evicts when the cached object is not the one that was updated.

Two earlier candidates were each corrected after review, by first writing a check that fails on them:

- `usercache-candidate-b1480234.patch` only fenced caching. A request waiting on an overlapped load still went on with the object read before the change (`invalidation-during-load-check.js`).
- `usercache-candidate-569a673a.patch` reloaded after an invalidation. But the model invalidates before awaiting its write, so a reload during the write still read and cached the old row (`delayed-write-check.js`).

No candidate is in the app, the owner's server or any image beyond the owned diagnostic container. Root's reviews cleared `3ef58609` (patch file SHA-256 `b59ea8c8…`) as a candidate only. This patch is independent of any other server change.

| Check | Pinned `2174eec7` | `b1480234` | `569a673a` | `3ef58609` |
| --- | --- | --- | --- | --- |
| `concurrent-load-check.js`: concurrent misses share one object | exit 1 | exit 0 | exit 0 | exit 0 |
| `invalidation-during-load-check.js`: a change while a load awaits is not returned or cached stale; an unrelated change costs no reload; constant change still answers within three loads | exit 1 | exit 1 | exit 0 | exit 0 |
| `delayed-write-check.js`: a write in flight during a load is not returned or cached stale | exit 1 | exit 1 | exit 1 | exit 0 |
| `diag-race.sh`, 10 tries, judged from each try's rows (the script's exit status is not a result) | 8 stale | 0 stale | 0 stale | 0 stale, all 30 reads finished |
| native run, same cases and order as `97bac3e3` (`run-candidate.sh`) | `test4e` 65 at `97bac3e3` (1 of 2 fresh runs) | 8 of 8 exit 0 | 8 of 8 exit 0 | 7 of 8 exit 0, finish cases included; `phone-online` 65 on a probe fault (below), then `test1` alone exit 0 with the corrected poll |

**The `3ef58609` native run's failure.** `phone-online` failed in `test1`: "server 32 vs app 37" (`native-candidate-3ef58609-output.txt`). The server log shows the app's reports in order and none refused: 32 s at 09:25:24.558 from the skips, then the paused 37.419 s at 09:25:31.239 (the session's `updatedAt` is the pause, 09:25:30.013). The probe polled right after Close, about 0.5 s after the pause, and accepted the first row with at least 30 s, which was the 32 s. Its next assertion, the app's position within 3 s, then failed. This was the probe accepting too early, not the app or the server. The poll now accepts only a row that meets both conditions, with the same 30 s timeout, threshold and assertion. `test1` alone against a freshly seeded `3ef58609` server then passed, with the paused 36.45 s position reaching the server (`native-candidate-3ef58609-test1-*`). The finish cases of the failing run (`test4d`, `test4e`) had passed, and the corrected poll does not touch them. Earlier runs used the old poll condition and passed it.

`seam-checks.txt` holds all three seam checks for all four files. `concurrent-load-check.txt`, `invalidation-during-load-check-red.txt` and `delayed-write-check-red.txt` are the first runs. Each native run's outputs carry its patch hash (`native-candidate-<hash>-*`). Each was against its own patch only: the `b1480234` and `569a673a` passes say nothing about `3ef58609`.

The native runs used the app at `386fed27`, whose `apple/` and `tvos/` are identical to `97bac3e3`, and the probes from `97bac3e3`. The image was the pinned `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53…` with only `models/User.js` replaced, its hash recorded in each run's `*-tested.txt`. Each run met the failing run's precondition: the server had just started, the row was unfinished at 34.4 s from the TV, and the app's sync and socket reached the server within 20 ms. A single native pass does not show the race was hit in that run; the controlled checks are the proof.

What the native finish case covers: the finish updates a progress row that already exists ("previously 34.4"). It does not cover a book's first progress being created by an offline session that already finished, which takes the server's separate create branch.

**Combined with Android's first-progress patch.** `server-combined/` runs only the affected Apple cases against both reviewed candidates together: this patch, then Android's `first-progress-candidate.patch` (SHA-256 `6313948f…`), which gives `models/User.js` `15ee2c33…`, the hash the Android track pins. The source was the merge of #94 (`6de5e359`) and the server a freshly seeded owned diagnostic container. `test1`, `test4a`, `test4d` (server stopped), `test4e` and the migration probe each exited 0. The Long Tide's first row, created by `test1`, now takes the session's `lastUpdate`. The finish updated it to the end, and it stayed finished after the reconnect and after a restart. The migration's Volume 01 session created its row already finished, which the pinned server would not do; the adoption probe passed unchanged. As above, this is not deployed, and one pass does not show the race was hit.

An earlier, narrower attempt covered only the two id lookups (`first-candidate.diff`, `race-5-first-candidate.txt`: 0 stale of 5). `race-5-pristine-first.txt` is the first instrumented pristine run (3 stale of 5); its DIAG lines accumulate across tries.

### Finish sync gate: still open

The matched production probe, unfinished to finished on the same item, failed at `97bac3e3` against the real 2.30.0 server and passed at `386fed27`. The failure is the server returning stale progress after storing the finish, not a lost finish. The real server does not pass this case. The cause is confirmed in the server. The candidate fix passes the controlled checks and the native finish sequence in the owned diagnostic container only. It is not deployed anywhere else, and the owner's server is unchanged, so the gate stays open. No app code changed.

An app-side change, sending pending sessions before opening the socket, would remove only the app's own concurrent pair, not other requests or other clients that miss the cache at the same moment. It has not been made.

Until a fixed server is in use, a client reading progress from an affected server process can resume from the earlier position. In the first attempts that happened: the next download resumed from 39 s, and its later offline session replaced the finish.

## Migration upload against the server

The runner first does, as the legacy app would on the server:

- opens a streamed session on "A Very Long Story Title" and syncs 5 s
- restarts the container, which closes that session
- opens a streamed session on "Salt and Signal" and syncs 10 s
- saves a newer 3.0 s position on Catalog Volume 03

The legacy snapshot then holds:

- each streamed session's unsent listening (6 s and 15 s)
- a downloaded session on Catalog Volume 01 that the server never saw (3 s), with its WAV file
- a newer legacy position on Catalog Volume 02 (2.0 s)
- an older legacy position on Catalog Volume 03 (1.0 s)

| Expectation | Server after the first sync | After a second sync |
| --- | --- | --- |
| Open session: `/sync` adds 15 s to the 10 s already reported | 25 | 25 (nothing added twice) |
| Session closed by the restart: `local-all` sends the stored 5 s plus the unsent 6 s | 11 | 11 |
| Downloaded session: `local-all` with its whole total | 3 | 3 |
| Newer legacy position is uploaded | 2.0 | 2.0 |
| Older legacy position does not replace the server's newer one | 3.0 | 3.0 |
| Sync report | 3 acknowledged, 0 pending, 0 unconfirmed | nothing to send |

This is migration gate 1 ("pending sessions accepted by the server") at software level against 2.30.0. The already-posted `play_local_` path is not covered. Exporting from the legacy app on a device, importing through Files, and rolling back remain physical gates.

## Other observation

During offline playback with the server stopped, the player shows "Playback progress could not be saved: Could not connect to the server". The listening is kept and published on reconnect, as the reconnect cases show, so the wording overstates the loss. No change was made.

## Summary

- **Real-server software checks that pass:** in the fresh-checkout run at `97bac3e3`, with every case's own exit status:
  - phone sign-in and restore, catalog paging, streaming across files, PDF page save and restore
  - podcast episode progress
  - download, offline playback across files with the server down, and publishing on reconnect
  - finishing a downloaded book offline with the server down
  - TV resume from a server position left by another install, with chapter movement across files
  - TV search and podcast episode progress
  - migration session and position upload, including idempotence
- **Open software gate: finish sync.** The finish reaches the server and is stored, but in that run the server went on returning the earlier unfinished progress until it restarted. The cause is a user-cache race in the 2.30.0 server, confirmed with instrumentation. A candidate server patch (`usercache-candidate-3ef58609.patch`) passes the isolated checks and has been reviewed. It is not deployed anywhere, so the gate stays open.
- **No product defect was found in the apps, so no app code changed.**
- **Still open, physical or owner gates:**
  - devices, lock screen and routes
  - VoiceOver and reduced motion
  - an OpenID provider, SMTP and RSS on the owner server
  - large real libraries
  - real legacy migration and rollback
  - native-speaker translation (#22: 507 native texts are English only)
