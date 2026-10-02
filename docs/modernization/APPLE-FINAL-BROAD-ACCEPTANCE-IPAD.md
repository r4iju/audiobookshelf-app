# Final broad iPad acceptance

The final broad journey run on iPad for the corrected mobile source, against the synthetic local fixtures (synthetic accounts, libraries and server). It is simulator acceptance only. Physical acceptance is not verified here.

## Source

- Integrated source 6b59eda0 (root), whose app code (`apple/App`, `tvos/Core/Sources`, `apple/project.yml`) is identical to 9e46bc19. Since then only journeys, fixtures and documents changed.
- Run source 9c88031d: 6b59eda0 plus a QA-only commit, not for integration. That commit moves the fixture ports to 59765, 59766, 59767 and 59769, and the remaining-QA pair to 58765 and 58769, so this run never shares another lane's fixtures. It changes no other code.
- Correction for integration: a3f8c375 (on 6b59eda0, test only). It is the same change as ba8ad8ec on the run branch.
- Simulator: pooled "Pool iPad 1 (iOS 27.0)" (`CDFFEB30-07F5-4A50-AB64-57A46709335B`), iPad Pro 11-inch (M5), leased with `sim acquire ipad`.
- Evidence: `/tmp/ipadqa/evidence/final/` (logs) and `/tmp/ipadqa/results/` (result bundles).

## Results

| Stage | Runner | Source | Result | Evidence |
| --- | --- | --- | --- | --- |
| Broad journeys | `verify-ui.sh`, same selection as the first broad run | 9c88031d | 93 tests: 89 passed, 1 failed, 3 skipped | `fin-ui-broad.log`, `fin-ui-broad.xcresult` |
| Gated contrast audits (the 3 skipped above) | `verify-remaining-qa.sh` (sets the accessibility gate), `RemainingQAAccessibilityJourney` only | 9c88031d | 3 passed | `fin-accessibility.log`, `fin-accessibility.xcresult` |
| Playlist deletion, before the fix | `verify-ui.sh`, up to 10 iterations until failure | 9c88031d | 1 passed, then 1 failed (same failure) | `playlist-red.log` |
| Playlist deletion, after the fix | same | 9c88031d plus the fix | 10 of 10 passed | `playlist-green.log` |
| `CollectionJourney` class | `verify-ui.sh` | ba8ad8ec | 6 of 6 passed | `collection-ba8ad8ec.log` |

On iPad all 93 broad journeys and the 3 gated audits pass with the correction. 89 of them passed in the single broad run. The playlist journey passed after the fix. The 3 audits passed in their own gated runner; in the broad run they count as skipped, not passed.

The dedicated stages were not rerun, because the app code has not changed since they passed on iPad at 9e46bc19: presentation 12 of 12, realtime 11 of 11, related authors and series 4 of 4, item server actions 4 of 4, progress reset 4 of 4 and publication recovery 1 of 1. `PlaybackAuthorizationJourney`, `RemainingQAJourney` and `RemainingQAGroupJourney` are outside this selection, as they were in the first broad run.

### The playlist deletion failure

`CollectionJourney.testCreateReorderRemoveAndDeletePlaylistThroughRelaunch` failed in both broad runs, at 9e46bc19 and at 9c88031d. The failure state is recorded in `FAILURE-playlist-delete-state.md`. The app presented the "Delete playlist?" confirmation. 0.05 s later the journey tapped its Delete button while the button had no frame yet. XCTest then treated the app's own alert as an interruption and its default handler dismissed it with Cancel, so the deletion was never confirmed.

The fix waits until Delete can be tapped (`hittable`). The deletion and playlist-contents assertions are unchanged. No screenshot exists, because the runner disables diagnostic collection. The UI hierarchy saved after the handler's Cancel shows no alert.

### First broad run, for comparison

9e46bc19 without the ledger corrections: 93 tests, 84 passed, 6 failed and 3 skipped (`/tmp/ipadqa/evidence/acceptance/acc-ui-90.log`). Five of those failures came from fixture and journey expectations written before the publication ledger, and pass with the corrections. The sixth is the playlist deletion above.

## Coverage by ticket

"Simulator" means the journeys pass on the iPad simulator against synthetic fixtures. Physical behaviour is unverified for every ticket.

| Ticket | Simulator coverage on iPad | Not covered |
| --- | --- | --- |
| #4 Connect and sign in | Connection 5, catalog recovery 4 | Real server |
| #5 OpenID and multiple servers | OpenID 4, saved connections 3 | Real identity provider |
| #6 Browse libraries and inspect books | Connection, catalog recovery, artwork 1, presentation 12, related 4 | |
| #7 Stream multi-file audiobooks | Playback 8 | Real audio routes |
| #8 Durable listening progress | Durable progress 4, realtime 11, progress reset 4, publication recovery 1, saved connections | Real server |
| #9 Background playback and system controls | None | Lock screen, system controls, audio routes |
| #10 Chapters, speed and bookmarks | Listening controls: chapters and speed, skips, 2 bookmark journeys | |
| #11 Sleep timers and advanced preferences | Listening controls: 4 sleep timer journeys, resume rewind | Background timers on device |
| #12 Search and discovery | Search 3, related 4 | |
| #13 Collections and playlists | Collection 6 | |
| #14 Podcast listening and permitted actions | Podcast 9, item server actions 4 | |
| #15 Download and manage content | Downloads in offline, collection and reader journeys; offline download retry | Storage limits on device (`verify-download-storage.sh` not run) |
| #16 Offline listening and reconnection | Offline 3, collection offline 2, durable progress | Real network loss |
| #17 Local files and opening modes | None in this selection | All |
| #18, #20, #21 EPUB, MOBI and comics | Deferred until after Phase 2 | |
| #19 PDF reading | Reader 20 | |
| #22 Preferences, statistics and diagnostics | Preferences 11, contrast audits 3 | |
| #23 Migrate account and listening state | Legacy import 2, legacy account refresh 1 | Real legacy migration data |
| #24 Migrate downloaded media and reading locations | None | Real legacy migration data |
| #25 Internal replacement readiness | This document and the iPhone results | Physical acceptance on owner devices |
