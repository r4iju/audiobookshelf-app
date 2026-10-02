# Main-use-case iPhone acceptance

A selected iPhone run of the main use cases on the final mobile source, against the synthetic local fixtures. This is not the full journey suite and not a full replacement acceptance. Physical acceptance and the cases listed under Follow-up remain open.

## Source

- App source 9e46bc19, from b1a82fea (PR 85).
- Branch `fork/apple-final-mobile-acceptance-phone`, adding QA-only commits that change no product code or numeric limit:
  - 966328b5 (cherry-pick of 56a9ac50): the account test pauses as soon as qa's listening reaches 10 s.
  - ec7add47 (cherry-pick of d91f9302): custom sleep timer input ends with Return before Start.
  - this runner and document.
- Simulator "Audiobookshelf FinalMobile iPhone QA" (`06CB7A2D-0379-41D2-9DD5-7BE833DB8CA5`), fixtures on 19765, 19766, 19767 and 19769.
- The source builds for testing (`apple/build-qa/acceptance-build.log`).

## Selection

`apple/scripts/verify-main-use-cases.sh A|B <bundle>` runs one group through `verify-ui.sh`.

| Use case | Group A (17) | Group B (4) |
| --- | --- | --- |
| Connection and restore | Connection: connect, select library and restore; invalid server recovery | |
| Browsing, aligned grid, details | Connection: paginated books and expanded metadata; Artwork: covers inside phone grid columns; Preferences: catalog layout survives relaunch; Search: book beyond first page and back from details | |
| Multi-file play, pause, resume | Playback: crosses files and continues after leaving details; natural book end; ListeningControls: resume rewind; DurableProgress: unsent listening survives termination | DurableProgress: retry after lost acknowledgment |
| Chapters, skips, bookmarks | ListeningControls: chapter seek and speed; skip intervals across files; bookmark create, edit, jump, delete | |
| Account isolation | SavedConnections: accounts on one server keep their own position | |
| Downloads and offline | Collection: downloaded collection book plays without the server | Offline: downloaded book across files offline, relaunch and reconnect |
| PDF | Reader: invalid PDF recovery and long document; PDF reading keeps audio playing | Reader: PDF rotation and page after offline relaunch; newer remote page after offline reconnect |

Group B depends on worker 681's corrections to the `offline-library` fixture and the lost-ack and PDF restart journeys, now carried here.

## Results

Final selected run: Group A 17 of 17 and Group B 4 of 4 passed, in one run each, on the simulator above with derived data on the external SSD.

| Group | Test source | Result | Evidence (`apple/build-qa/`) |
| --- | --- | --- | --- |
| A | 393a71cd | 17 passed, 0 failed (564 s) | `final-A.log`, `final-A.xcresult` |
| B | 8f0585a7 | 4 passed, 0 failed (157 s) | `final-B.log`, `final-B.xcresult` |

Both sources are b1a82fea with QA-only commits on top; `git diff b1a82fea` touches only `apple/UITests`, `apple/scripts`, `verification` and this document.

QA commits added since the selection was prepared:

- 5a8bcba2, 4aa3bb1b: cherry-picks of worker 681's a9079463 (fixture records each write's body) and 36cca957 (offline-library writes refused with 500 before anything is stored; a lost acknowledgment still stores and answers 503). `python3 -m unittest verification.test_fixture`: 15 passed.
- 62c849a1, 2504b882: cherry-picks of 83dc3f68 and 0f535b39 (confirm a server restart before the retry or newer PDF page). `FixtureControl.restart` uses this lane's `127.0.0.1:19765`, the same base as `configure` and the app; the iPad 5976x remap (deb291fa) is not taken.
- 393a71cd: `ConnectionJourney.setUp` configures `baseline`. RED: the first Group A run on ffb6e9c3 (`acceptance-A.log`, `acceptance-A.xcresult`) failed both Connection connect cases with HTTP 503 because the collection offline case had left the fixture in `offline-library`; they passed alone (`acceptance-A-connection-isolated.*`) and in order after this commit.
- 8f0585a7: the lost-ack journey waits for 10 s and reads its paused value with `bookElapsed(app)` (book position, as the server session's `currentTime` is), not chapter-relative `playback-elapsed`. Bounds and the dedup, single-session and listening assertions are unchanged.

## Follow-up

- Fixture isolation: any local process can reconfigure a running fixture, and sibling checkouts still use 127.0.0.1:19765 (`APPLE-FINAL-MOBILE-QA-IPHONE.md`).
- Loopback port exhaustion on a busy host makes an account switch report "The server could not be reached"; whether to retry once is a product decision.
- Not in this selection: podcasts, EPUB and other formats (#18, #20, #21 deferred), realtime, OpenID, groups, statistics and year review, presentation and localization, and the 27765, 25765 and 26765 runners.
- Physical acceptance: lock screen and system controls, audio routes, background timers, a real server and library, real legacy migration data, owner devices.

## Root integration and internal installations

Root integrates the equivalent fixture and recovery-journey corrections at `6b59eda0`. The restart helper uses the canonical fixture port and recovery comparisons use whole-book elapsed time. Connection setup and offline collection teardown restore baseline fixture state. Both bounded source reviews are clear; `python3 -m unittest verification.test_fixture verification.test_upgrade_gate` passes 16 tests. Production Apple app source is unchanged from PR #85 (`9e46bc19`).

The iPad lane records 21/21 of the same main-use-case selection in one run on `10e34133`, using a leased pooled iPad. Its evidence is `/tmp/ipadqa/evidence/smoke/smoke-21-10e34133.log` and the matching result bundle. Its fixture port remap is local to that lane. Earlier broad failures are retained; final broad and accessibility acceptance remain separate work.

The signed Release native preview was built from `9e46bc19`, passed strict codesign validation and was installed on both paired physical devices without launching it. Installation logs are `/tmp/abs-final-native-iphone-install.log` and `/tmp/abs-final-native-ipad-install.log`; signature evidence is `/tmp/abs-root-final-mobile-ios-codesign.log`. The installed bundle is `com.forkzed.audiobookshelf.native.preview` (Audiobookshelf Native). Installation does not establish physical playback, audio-route, migration or accessibility acceptance. The signed TV build from PR #84 is also installed; its simulator suite passed 40/40.
