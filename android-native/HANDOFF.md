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

## Evidence for 2b3227dc (emulator and fixture only)

- Unit tests: `./gradlew :core:test :app:testDebugUnitTest`, 24 tests, 0 failures.
- Journeys on `emulator-5584` (API 36) against the local fixture on ports 28765/28766/28767/28769:
  - Browse, Connection, Download, Groups, ListeningDurability, Pdf, Playback, PlayerTools and Podcast: 39 of 39 pass.
  - AccountsJourney 3 of 3 pass after the emulator's Chrome was force-stopped.
- **Emulator caveat:** the first AccountsJourney attempt failed because Chrome on the emulator was stuck on an old fixture tab and never requested `/auth/openid`. Force-stop Chrome before the OIDC journey if this recurs.

## Known limits

- Listening that is held in memory because storage refuses writes is lost if the process dies before storage recovers. The player pauses and warns as soon as a write fails, which bounds the loss to the listening already played.
- `PlayerToolsJourney.a` (`delete-bookmark-0`) has flaked once in a full run.
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
