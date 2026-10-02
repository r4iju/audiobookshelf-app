# Apple native apps against a real Audiobookshelf 2.30.0 server

Before this run, every native journey had been tested only against the Python and Node fixtures. This run uses the production iPhone app, the production TV app and the production migration adoption code against the real server image recorded in `SERVER-COMPATIBILITY.md`.

The setup is local, isolated and synthetic. It establishes no owner-library, owner-device, physical-hardware, OpenID-provider, SMTP or real-legacy-data acceptance.

## Setup

- **Source:** `68842296` (origin/fork/native-tv). The probes add test sources only; no app code changed.
- **Server:** the locally present pinned image `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53…` (2.30.0), with no network pull. It is started by the web real-server harness `web/qa/server.mjs` under its own name and ports:
  - container: `ABS_QA_CONTAINER=abs-apple-qa`
  - main port: `ABS_QA_PORT=19890`
  - helper ports: 19894 to 19896
  - volumes: the named volumes `abs-apple-qa-{config,metadata,podcasts}`, plus the generated library under the worktree on the external SSD
- **Untouched:** the owner's `audiobookshelf` container and the web thread's `abs-web-qa` containers. Only `abs-apple-qa` was stopped, started and restarted.
- **Data:**
  - the generated synthetic library: 69 books, 1 podcast with 4 episodes, MP3 audio and PDFs
  - the synthetic accounts `qa` and `qa-other`
- **Devices:** pooled simulators leased with `sim acquire`: Pool iPhone 1 (iOS 27.0) and a pooled Apple TV.
- **Probes:** XCTest classes run with `-only-testing`. They are not added to the suites. Their sources and runner scripts are kept in `evidence/apple-real-server/`. Each probe reads results from the server's own API (`/api/me/progress`, `/api/me/item/listening-sessions`, `/api/me`).
- **Evidence:**
  - logs and result bundles are in the ignored `apple/build-qa/real-server/` folder of the QA worktree
  - the committed folder holds the runners' combined output (`runner-output.txt`), the server-side setup output and the reproductions
- **Rerunning:** copy the probes back into the test folders first: `RealServerProbe-iPhone.swift` to `apple/UITests/RealServerProbe.swift`, `RealServerProbe-TV.swift` to `tvos/UITests/RealServerProbe.swift`, and `RealServerAdoptionProbe.swift` to `apple/NativeTests/`.

## Results

Every attempt is listed, including the first failures. Where the fault was in the probe, the correction is stated and the case was run again; the assertions were corrected, not loosened.

| Case | Attempts | Final result | Evidence |
| --- | --- | --- | --- |
| **Phone: sign in, browse, stream.** Sign in, then relaunch restores the account. The catalog reports 69 items, and an item from the server's second page is reachable. A multi-file book streams across a file boundary. The server position is within 3 s of the app's, and listening time is recorded. | 1 | Pass | `phone-online.{log,xcresult}` |
| **Phone: PDF.** A PDF opens in the native reader. Page 3 is saved to the server (`ebookLocation`, `ebookProgress`), and a relaunch reopens page 3. | 1 | Pass | `phone-online.*` |
| **Phone: podcast episode.** A podcast episode streams, and the server saves progress for that episode only. | 3 | Pass on the third attempt. The first two read time labels that the single-file episode player does not show (`total-elapsed`, then `chapter-elapsed`; the right one is `playback-elapsed`). The second attempt's podcast-level check also misread the server: 2.30 answers `/api/me/progress/<podcast>` with an episode's row. The check now reads `/api/me`, where every row for the podcast has an `episodeId` (`podcast-progress-api.txt`). | `phone-online.*`, `phone-podcast-rerun{,2,3}.*` |
| **Phone: download, then offline with the server stopped, then reconnect.** The download completes. With the container stopped, the downloaded book plays from the server position and crosses into its third file. After the container restarts, a relaunch publishes the offline listening: the server position is at least 60 s and the session is recorded. | 2 | Download, offline crossing and publish pass on the second run (`download-rerun`, `offline-rerun`, `reconnect-rerun`). Step 2's final assertion failed there on a probe parse: past a minute the label reads "1 min", and the probe took "1". The publish is proven by step 3's server check. In the first run, the probe skipped from 37 s past the end of the 90 s book; see the observation below. | `phone-{download,offline,reconnect}{,-rerun}.*` |
| **TV: search and podcast episode.** Server search finds "Salt and Signal", and its details open. A podcast episode plays with the remote, and the server records that episode's progress (0 to 6.8 s). | 1 | Pass | `tv.{log,xcresult}` |
| **TV: resume a server position.** Continue Listening shows the server's saved position. Playback resumes there, Previous chapter moves into the second file, and the server records the TV's position. | 4 | Pass on the fourth attempt. The TV resumed at 64 s against a server position of 63.7 s (chapter 3 of 3) and moved to chapter 2. The server then recorded 34.3 s, inside the second file. That server position was left by the third attempt's TV session. Each attempt starts on an erased leased TV with a reset sign-in, so it came from the server, not local state. The second attempt resumed from the phone's 75 s position, but stopped before its assertions. The first attempt hit the known tvOS sign-in keyboard focus flake (`TVJourney.swift`, as recorded in `APPLE-LOCALIZATION-READINESS.md`). The second asked for Next chapter while already in the last chapter, where the control is correctly disabled. The third reached playback, but Previous first restarted the current chapter (intended when more than 3 s in), and the probe then read a label after Stop closed Now Playing. The server held 63.7 s, which is the chapter-3 restart plus 4 s of playback. | `tv.*`, `tv-resume-rerun{,2,3}.*` |
| **Migration upload as `qa-other`.** The production `LegacyMigrator`, `LegacyArchive` and `NativeMigrationAdoption` are signed in with a real `URLSession`. | 2 | Pass on the second run (details below). In the first run, the fixture dated the legacy app's last update about 50 s before its own last server sync for the restarted session. The adoption code then correctly refused to overwrite a server row written later, and kept it as unconfirmed. | `migration{,-rerun}.{log,xcresult}`, `migration-setup{,-rerun}.log` |

### Migration upload against the server

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

This is migration gate 1 ("pending sessions accepted by the server") at software level against 2.30.0. Exporting from the legacy app on a device, importing through Files, and rolling back remain physical gates.

### Observation: a finish reached the server, but the stored progress did not change

In the first offline run, the probe skipped past the book's end. The app's offline session therefore ended at 90.2 s of 90.2 s.

On reconnect, the app published it:

- the server stored that session as 90.2 s
- the server log reads "Updating progress for "The Long Tide" with current time 90.2…" and "Marking media progress as finished"

Even so, `/api/me/progress` still returned the earlier 37.4 s, unfinished, with its earlier `lastUpdate`. No later write to that row appears in the server log.

Two direct reproductions as `qa`, on Catalog Volumes 03 and 02, did persist a finishing `local-all`. One was in a running server and one right after a container restart (`repro-finish-after-restart.txt`). The earlier repro attempts that used a session time older than their own PATCH were correctly skipped by the server (`repro-finish-after-restart-stale-time.txt`).

The cause is not established. The app sent the right session, and the case is not reproduced. It stays open as a single unexplained observation, not a confirmed defect in the app or the server. Finishing a book offline should be checked again on a device against a real server.

## Summary

- **Real-server software checks that pass:**
  - phone sign-in and restore, catalog paging, streaming across files, PDF page save and restore
  - podcast episode progress
  - download, offline playback across files with the server down, and publishing on reconnect
  - TV search and podcast episode progress
  - migration session and position upload, including idempotence
- **TV:** resume from the server position with chapter movement across files.
- **No product defect was found, so no app code changed.**
- **Still open, physical or owner gates:**
  - devices, lock screen and routes
  - VoiceOver and reduced motion
  - an OpenID provider, SMTP and RSS on the owner server
  - large real libraries
  - real legacy migration and rollback
  - native-speaker translation (#22: 507 native texts are English only)
