# Apple TV completion handoff

Scope: stories #26–#30 (TV browsing, playback controls, durable progress, podcasts, readiness). The TV slice changed only `tvos/App`, `tvos/UITests`, `tvos/scripts/verify-ui.sh`, `tvos/project.yml`, the generated TV project and TV docs. `apple/Playback`, `tvos/Core/Sources/TVCore`, `verification/` and `apple/App` were read, not edited. The recommendations below are for their owners.

## Recommendations for shared code owners

1. **Listening journal storage.** Shared commit `44011bc2` stores the TV journal in bounded `UserDefaults` under `NativeListeningJournal`, with the old file as a migration source. The TV Debug `--reset-tv-state` argument clears both; Release and device state are untouched. Simulator termination recovery passes. Storage-pressure recovery on hardware remains open (physical check 7 in [QA.md](QA.md)).
2. **Failure recovery.** Shared `ApplePlayback.isProgressFailure` distinguishes progress retry from media restart. Now Playing offers the applicable action and the remote can reach it. `RecoveryJourney.testMediaFailureOffersRestartRatherThanSavingProgress` verifies recovery in the simulator. `MediaRestart` also pins account, session, media and failure state while fetching the item; app unit tests exercise replacement sessions and pause/recovery. The same guard also pins the shared playback-intent revision, so a seek, pause or resume wins even when session and error text are unchanged.
3. **Deprecated interruption reason.** `ApplePlayback.swift:624` uses `AVAudioSession.InterruptionReason.appWasSuspended`, deprecated since tvOS/iOS 16; it builds with a warning on the TV target.
4. **Filter value encoding.** Shared `ServerAddress.url` percent-encodes literal `+` in query values so Express keeps base64 filters and search text intact. The regression failed with two assertions before the fix and all 22 shared core tests pass afterward. The existing TV pre-escaped filter remains compatible with the server's additional decode step. Source: the local copy of server 2.30.0, `server/utils/queries/libraryFilters.js`.
5. **Fixture observations and modes (`verification/fixture.py`).** Recorded requests keep only `method`, `path` and `page`. Recording the `filter`, `sort` and `desc` query values would let journeys assert the server request directly, rather than only the server's filtered result. Two more modes would let the TV cover behaviour that is currently verified only by review: one that fails a single library's personalized and search endpoints, and one that revokes the token mid-session.
6. **Parity matrix (`verification/parity.json`).** Recorded `replacementEvidence.tv` entries. These are simulator and fixture evidence only, and each story still needs the physical gates listed below:
   - `story-05`, `story-55`: `TVJourneyTests/CatalogJourney/testContinueListeningOpensDetailsAndBackRestoresFocus`, `testLibraryLoadsNextPageAsFocusMovesDown`.
   - `story-56`: `CatalogJourney/testTrustedHTTPSServerAndLongMetadata` (long title, missing cover).
   - `story-57`: `PlaybackJourney/*`, `PodcastJourney/*`, `RecoveryJourney/testUnsentListeningSurvivesTerminationAndSyncsOnRelaunch`, `CatalogJourney/testServerSearchFindsTitlesOutsideLoadedPage`, `testFilterAndSortAreAppliedByTheServer`.
   - `local-builds`, `internal-distribution`: `./tvos/scripts/verify-ui.sh` and `./tvos/scripts/deploy.sh`.

## Integration notes

- TV journeys use ports 20765 (HTTP) and 20767 (HTTPS) and simulator `00DD108F-2435-4FEC-9C37-3E62861A0EF6`. They do not touch 19765–19769 or the iPhone/iPad QA simulators.
- The HTTPS fixture uses a throwaway CA generated for each run and trusted only in the TV QA simulator (`simctl keychain add-root-cert`). This mirrors a homelab CA profile installed on the TV. The app adds no pinning or trust exceptions.
- `tvos/App/LibraryStore.swift` and `Views.swift` were replaced by `CatalogStore`, `LibraryBrowser` and per-screen views. Nothing outside `tvos/App` referenced them.
- The TV still compiles `apple/Playback` and `tvos/Core/Sources/TVCore` directly. It relies on these public members of `ApplePlayback`: `start`, `toggle`, `pause`, `skip`, `seek`, `changeSpeed`, `stop`, `sync`, `restoreListening`, `setFinished`, the sleep-timer API, `authenticationRestored`, and the published state used in `NowPlayingView`. Changing their behaviour requires rerunning `./tvos/scripts/verify-ui.sh`.
