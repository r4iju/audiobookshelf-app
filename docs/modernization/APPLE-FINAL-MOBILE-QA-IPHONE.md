# Final mobile QA on iPhone at 56990f46

Independent QA run of the production native app on a fresh iPhone simulator, against the synthetic local fixtures. No owner server, owner data, owner device or hosted service was used. The iPad suite at the same source runs separately (worker 681b5b5b, ports 59765 to 59769).

## Setup

- Source: 56990f46, worktree `audiobookshelf-final-mobile-qa`, branch `fork/apple-final-mobile-qa`.
- Simulator: "Audiobookshelf FinalMobile iPhone QA" (`06CB7A2D-0379-41D2-9DD5-7BE833DB8CA5`), iPhone 17, iOS 27.0, created for this run.
- Fixtures: `apple/scripts/verify-ui.sh` on ports 19765, 19766, 19767 and 19769, which were free when checked. The realtime proxy dependencies were installed in this checkout with `npm ci --prefix verification/realtime`.
- Excluded with `-skip-testing`, because their runners use other ports: PresentationJourney (12, port 25765), RealtimeJourney (5) and PausedRealtimeJourney (2, port 26765), and RelatedAuthorSeriesJourney, ItemServerActionsJourney and ProgressResetJourney (4 each, port 27765). They are not counted below; they belong to their own runners.

## Initial results at 56990f46

| Suite | Result |
| --- | --- |
| Core (`swift test --package-path tvos/Core`) | 63 of 63 passed |
| NativeTests (on a fresh iPad simulator, before the iPad suite moved to worker 681b5b5b) | 64 of 64 passed |
| NativeJourneyTests on iPhone, 90 journeys | 81 passed, 9 failed, 0 skipped (xcresult summary) |

The 9 failures:

- DurableProgressJourney: `testRecoveredListeningPreservesNewerProgressAndANewClientResumesIt`, `testUnsentListeningSurvivesTerminationAndRestoresServerProgress`
- ListeningControlsJourney: `testChapterSeekAndSpeedSurviveSessionRestoration`, `testConfiguredSkipIntervalsSeekAcrossFilesAndPersist`, `testResumeRewindsAfterAPauseAndCanBeDisabledPersistently`
- OfflineJourney: `testDownloadedBookPlaysAcrossFilesOfflineAfterRelaunchAndSynchronizesOnReconnect`
- PodcastJourney: `testPodcastEpisodeSelectionKeepsIndependentProgressThroughRelaunch`
- SavedConnectionsJourney: `testAccountsOnTheSameServerKeepTheirOwnListeningPosition`, `testSavedServersKeepLibraryChoicesAndRecoverUnsentListeningWhenSwitchedBack`

## Cause

768ff969 made the chapter track the iOS default (`ApplePlayback.defaultChapterTrack`, as in `apple/Localization/HANDOFF.md`). The app is behaving as designed. With the chapter track on, `PlayerDisplay` uses the chapter window, so `playback-elapsed` is the time within the chapter (`PlaybackViews.swift:169`). The whole book is in `total-elapsed`, which the total track (on by default) shows beside it. Both are divided by the speed unless "Scale elapsed time by speed" is off. The 9 journeys predate 768ff969 and read `playback-elapsed` as book time. The fixture books and episodes have chapters at 0 and 8 seconds, so:

- after selecting chapter 2 the label reads 0, not 8;
- a 5-second skip from 7 reads 4, not 12;
- waiting for 14 or more never succeeds (the second chapter shows at most 12), and the 20-second book ends before the pause button can be tapped.

Isolation was checked as well. `--reset-preview-account` removed `previewChapterTrack` but kept `previewTotalTrack`, `previewScaleElapsedBySpeed` and `previewLockPlayerControls`. PresentationJourney changes all three, so on a shared simulator its choices reached later journeys. `configure(baseline)` already restores book-0 for both synthetic users (qa 6 s, qa-other 2 s) and clears reports, local sessions and bookmarks. A probe run after DurableProgressJourney recorded qa's book-0 at 6 s with no reports, so server state did not leak into the failures.

## Correction

- `NativeJourney.bookElapsed(_:)` returns `total-elapsed`. The 9 journeys assert book time through it, with the same numbers and timings as before, and add no settings steps while audio plays.
- The 2× speed test turns "Scale elapsed time by speed" off after pausing and before reading the position, so the check that playback reached at least 12 seconds is unchanged. Doing this before playing kept the player paused long enough to trigger the 3-second resume rewind.
- `openPlayerSettings` and `playerSettings` moved unchanged from PresentationJourney into NativeJourney so both can use them. PresentationJourney compiles against them; this branch did not run it (port 25765).
- `--reset-preview-account` (debug simulator builds only) also removes the three player display keys. The saved chapter and total track choice still carries across an ordinary relaunch.

## Correction evidence

- **RED in isolation at 56990f46** (`iphone-nine-red`): 7 of the 9 failed with the same chapter-relative values. The skip and saved-servers tests passed on that run because their start positions kept the asserted range inside one chapter.
- **Reset isolation RED** (`probe-red`): a throwaway journey turned the total track off, turned scaling off and locked the player, then relaunched with `--reset-preview-account`. The player stayed locked and the total track stayed off. With the correction, the same probe passed. It is not committed.
- **GREEN** (`iphone-nine-green`, second run): 8 of the 9 and the probe passed. The first correction attempt changed player settings during the journeys. It failed 3 tests, because it shifted timing (the speed test's resume rewind, and a podcast episode playing to its end) and so was replaced.
- **SavedConnectionsJourney, repeated:** `testSavedServersKeepLibraryChoicesAndRecoverUnsentListeningWhenSwitchedBack` passed 3 of 3. `testAccountsOnTheSameServerKeepTheirOwnListeningPosition` passed 8 of its 10 runs after the correction. One failure was the restored-position wait for qa (expected 10 to 13 s). The other was `book-book-0` not appearing within 10 s after switching back to qa. A passing probe recorded the restored position as 11 s. Neither failure's value was captured, so this residual is open and not attributed to the product, the fixture or the simulator.

## Artifacts

All are in `apple/build-qa/` in this checkout, which is ignored by `apple/.gitignore`.

| Run | Log | Result bundle |
| --- | --- | --- |
| Full iPhone suite, 90 journeys | `iphone-full.log` | `iphone-full.xcresult` |
| Core | `core.log` | |
| NativeTests | `nativetests-ipad.log` | `nativetests-ipad.xcresult` |
| The 9, isolated, RED | `iphone-nine-red.log` | `iphone-nine-red.xcresult` |
| Reset isolation probe, RED | `probe-red.log` | `probe-red.xcresult` |
| The 9 plus probe, GREEN | `iphone-nine-green.log` | `iphone-nine-green.xcresult` |
| SavedConnections repeats and probes | `sc-repeat.log`, `sc-probe.log`, `sc-probe2.log`, `state-probe.log` | matching `.xcresult` |

## Not covered here

- The full 90-journey suite was not rerun after the correction, as root asked; it is due at final integration.
- The 31 journeys on ports 25765, 26765 and 27765, which root and other workers run.
- Physical acceptance: lock screen and system controls, calls and audio routes, background timers, live server and library, real legacy migration data, and owner devices. Simulator and fixture results do not stand in for any of these.
