# Native Android handoff

Branch `fork/native-android`, based on `origin/fork/native-tv` at `39ad6af65715957c585e7b0f0d20238ebe60ee8f`.
Not merged into `fork/native-tv`. The app installs as the preview identity
`com.audiobookshelf.app.nativepreview` beside the legacy `com.audiobookshelf.app`, which it never touches.

## Review blockers at 25f5116e, fixed in 2b3227dc

| Blocker | Fix | RED observed before the fix |
| --- | --- | --- |
| Listening write: a stop, account switch or queue advance while the journal write failed lost the delta | `ListeningWriter` owns each record's unsaved listening until the write succeeds. Finishing the record, publishing progress and closing the server session run only after that write succeeds. Retries back off from 1 s to 60 s. Playback pauses with an explanation while the current title cannot be saved. | `ListeningDurabilityJourney` failed on the 25f5116e engine (no listening reached the server after storage recovered) |
| Download manifest replacement ignored rename results | `DownloadStore.save` uses the checked `writeAtomically`. A refused replacement keeps the previous manifest and in-memory records, and the UI says nothing changed. | `DownloadStoreTest.aManifestThatCannotBeReplacedIsNotReportedAsSaved` |
| Reading sync rejected newer remote pages and PATCHed blindly | Each page keeps the server `lastUpdate` it last agreed with, plus pages sent but not yet confirmed. Before sending, sync reads `GET /api/me/progress/<id>`. A newer page from another device becomes a conflict that the reader resolves; it is never overwritten. | `ReadingSyncTest`, 3 tests |

## Review blockers at f8015e83, fixed in a3d98009

| Blocker | Fix | RED observed before the fix |
| --- | --- | --- |
| A newer server position that is not a page number made preflight report a conflict without storing one, so publication re-fetched forever | The position is stored as a conflict (`conflictLocation`, `conflictUpdatedAt`) and the page is not publishable until the reader keeps it or leaves the other position. A guard stops publication if an entry is still unchanged and publishable after a round. | `ReadingSyncTest.aNewerPositionThatIsNotAPageWaitsForTheReaderWithoutAskingTheServerAgain`: the server was asked 21 times |
| A reading PATCH advanced the shared `lastUpdate` while listening was unsent, so the server then dropped that listening | `PlaybackEngine.publishReading` gates every reading write (mirrors Apple `publishReading`): <ul><li>Refused while a title is open, loading or holding unwritten listening.</li><li>Otherwise publishes the account's journaled listening first and fails, keeping the page, if that fails.</li><li>Opening a title waits for an in-flight reading write.</li><li>`listeningEnded` resumes held reading.</li></ul> | `ReadingListeningJourney`: listening sync refused, page turned, sync restored. The server kept 6 s while 10.47 s had been sent, in 2 of 2 runs. The first runs without a 3 s gap passed or failed on sub-second emulator/host clock differences, so the gap was added. |

Evidence for a3d98009:
- Unit tests pass: the 4 reading tests, plus the full app and core suites.
- `ReadingListeningJourney`, `PdfJourney` and `ListeningDurabilityJourney` pass 12 of 12 on the emulator.
- The commit compiles on its own, including instrumentation tests; checked in a clean temporary worktree.
- **Behavior note:** reading is not sent to the server while a title is loaded in the player, even when paused. It is published once the player is closed, matching Apple.

## Settings, statistics, diagnostics and progress reset in 50e1c2a1

- Settings cover the existing app's player, sleep, orientation, haptic and cellular options. Statistics come from `/api/me/listening-stats`, and diagnostics keep redacted recent failures.
- `SettingsJourney`: 4 of 4. Its RED was observed before the screens existed.
- Discarding book and episode progress was added for root parity. **Its reset lifecycle was not durable; see 5068c1d3.**

## Item RSS feeds and send-ebook in be65ac11

These follow server 2.30 permissions, as required by the root parity audit.

- **Feeds:**
  - Administrators open (feed name, directory visibility, owner) and close an item's feed.
  - Anyone sees and copies the address of an open feed.
  - Only titles with audio or episodes qualify.
- **Send-ebook:**
  - Offered only when the title has an ebook and `/api/authorize` returns e-readers.
  - A refused delivery is reported and not shown as sent.
- The fixture wrapper models `/api/feeds/item/:id/open`, `/api/feeds/:id/close`, `include=rssfeed` and `/api/emails/send-ebook-to-device`. **No mail is sent and no owner feed is touched.**
- **RED:** `ItemActionsJourney` failed 4 of 4 on the missing actions. The checks that listeners and devices without e-readers see no action passed before the failing step.
- **GREEN:** 4 of 4.
- `BrowseJourney` now scrolls to the description, which the progress actions moved below the fold.

## Review blockers at 50e1c2a1, fixed in 5068c1d3

| Blocker | Fix | RED observed before the fix |
| --- | --- | --- |
| No durable reset intent; DELETE before local cleanup; lost response or relaunch lost the reset | `ProgressResets` (core):<ul><li>Saves the reset before anything changes, keyed by the origin account.</li><li>Records the server progress it first saw before deleting.</li><li>Cleans up locally before the DELETE.</li><li>Removes the reset only after the DELETE (404 counts as done).</li><li>Retries on network return, account return and with backoff, and on launch.</li><li>A retry deletes only progress no newer than first seen, so progress made after the reset survives.</li></ul> | `ProgressResetsTest`, 4 tests: reset lost on restart; DELETE ran before failed cleanup; a lost response led to deleting later progress `p2`; reset dated by the device clock |
| Reset removed the cached position, so an older server snapshot restored the old offline position | `ListeningJournal.resetPosition` stores position 0 dated at the later of the request time and the server's last update seen. `adoptRemotePosition` only takes newer positions. | `ListeningJournalTest.aResetOutranksServerSnapshotsTakenBeforeIt`: 9.5 s came back |
| No exclusion with reading writes or audio starts | <ul><li>The DELETE runs in `PlaybackEngine.excludingTitle`, under the same gate as reading writes, after the title's listening is on the server.</li><li>A title under reset refuses to start.</li><li>Gated writes finish even when their caller is cancelled: the reader published from its own scope, so closing it released the gate mid-PATCH.</li><li>`ReadingSync` chooses its page inside the gate.</li></ul> | `ProgressResetJourney.aPageSentJustBeforeTheDiscardDoesNotBringProgressBack`: page 2 recreated the progress. `playingWhileProgressIsBeingDiscardedDoesNotResumeTheOldPosition`: progress came back at 8.2 s. |

Evidence for 5068c1d3:
- Unit tests: `./gradlew :core:test :app:testDebugUnitTest`, all pass.
- The full journey suite passes in one run on `emulator-5584`: 55 of 55 across 14 classes.
- The affected classes (ProgressReset, Pdf, Settings, PlayerTools) pass 20 of 20 in each of two further runs.
- Superseded by the corrections below.

## Review blockers at 5068c1d3, fixed in 13ca2ed5121f9c3b50d5fbb4b901882bc2ef66b2

| Blocker | Fix | RED observed before the fix |
| --- | --- | --- |
| An unreadable reset file was set aside and treated as no resets, so playback and reading could resurrect what it was to delete | `ProgressResets` keeps an unreadable file in place and reports `unreadable`. Every title then counts as under reset: nothing plays, no page is published, no new reset is saved and the file is never overwritten. This holds across restarts because the state is derived from the file on each launch. Only an explicit confirmation in Diagnostics sets the file aside (kept as `progress-resets.json.unreadable-<time>`) and releases titles. | `ProgressResetsTest.unreadableResetsHoldEveryTitleAndAreNeitherDiscardedNorOverwritten`: "An unreadable reset may be for any title". `ProgressResetJourney.unreadableDiscardRequestsKeepTitlesFromPlayingAfterStartUntilResolved`: the title played. |
| `ReadingSync` sent a stale primary page for a title whose reset cleanup had failed, and the retry then took its own PATCH for later progress and skipped the DELETE | `ReadingSync` takes a `held` predicate and skips titles with a pending (or unreadable) reset, both when looping and when choosing inside the gate. Other titles and supplementary PDFs still publish. A completed reset, or an explicit Diagnostics resolution, runs `publishAll` again. | `ProgressResetJourney.aPageLeftUnsentByAFailedResetIsNeverSentForIt` (production path: reading refused, page 2 turned, journal replacement blocked so only cleanup fails): the server kept `ebookLocation` 2 with `currentTime` 6 after the discard. |

Evidence for 13ca2ed5121f9c3b50d5fbb4b901882bc2ef66b2:
- Unit tests: `./gradlew :core:test :app:testDebugUnitTest`, all pass.
- `ProgressResetJourney` passes 6 of 6 on `emulator-5584`.
- The commit alone, in a clean temporary worktree, passes the unit tests and compiles the instrumentation tests.
- Regression on the same build: `PdfJourney` and `ReadingListeningJourney` 11 of 11, `SettingsJourney` 4 of 4, `ListeningDurabilityJourney` 1 of 1, `PlaybackJourney` 5 of 5.
- Two interruptions in those runs, neither a failure of the change:
  - `SettingsJourney.a` hung once mid-run with the app idle on Settings. Run alone, it passed 4 of 4.
  - One `PlaybackJourney` failure was caused by a folder picker I opened on the emulator during the run ("No compose hierarchies found"). Run alone, it passed 5 of 5.
- **Pending independent re-review** of 13ca2ed5.
- No timeouts were lengthened and no fixture or app data is cleared to make a test pass. The page journey restores the journal path in `finally` so cleanup can succeed afterwards.

**Fixture wrapper changes:**
- `/__android__/refuse-reading` answers page PATCHes with 503 and records them as not applied.
- Reconfiguring drops progress added since startup, restores startup titles and clears bookmarks. This fixes the PlayerTools and Settings cross-class failures seen in full runs.
- Entries that exist are left for the mode, so layered modes such as `pdf-remote` then `pdf-supplementary` still work.
- `/__android__/slow-discard` holds DELETE.

## Evidence for 2b3227dc (emulator and fixture only)

- Unit tests: `./gradlew :core:test :app:testDebugUnitTest`, 24 tests, 0 failures.
- Journeys on `emulator-5584` (API 36) against the local fixture on ports 28765/28766/28767/28769:
  - Browse, Connection, Download, Groups, ListeningDurability, Pdf, Playback, PlayerTools and Podcast: 39 of 39 pass.
  - AccountsJourney 3 of 3 pass after the emulator's Chrome was force-stopped.
- **Emulator caveat:** the first AccountsJourney attempt failed because Chrome on the emulator was stuck on an old fixture tab and never requested `/auth/openid`. Force-stop Chrome before the OIDC journey if this recurs.

## Known limits

- Listening that is held in memory because storage refuses writes is lost if the process dies before storage recovers. The player pauses and warns as soon as a write fails, which bounds the loss to the listening already played.
- `PlayerToolsJourney.a` (`delete-bookmark-0`) has flaked once in a full run. The fixture reset in 5068c1d3 removes the cross-class bookmark state behind the `bookmarks-empty` failure.
- While a discard is pending (offline, or listening not yet sent), the title does not play and shows "Discarding progress" until the server confirms.
- Physical-only gates are not yet exercised:
  - Bluetooth, lock screen and Android Auto controls.
  - Real metered networks.
  - Migration from the legacy app on the owner's device.

## Running the checks

```sh
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ANDROID_HOME=~/Library/Android/sdk
cd android-native
./gradlew :core:test :app:testDebugUnitTest
scripts/verify-journeys.sh [JourneyClass ...]   # refuses to start if any fixture port is already in use
```
