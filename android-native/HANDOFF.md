# Native Android handoff

`fork/native-android` was merged into `fork/native-tv` through #87 (79b31196). This work is on
`fork/android-l10n-bookmarks`, branched from there. The app installs as the preview identity
`com.audiobookshelf.app.nativepreview` beside the legacy `com.audiobookshelf.app`, which it never touches.

Evidence paths written as `artifacts/...` are outside the repository, under
`/Volumes/ai-ssd/developer-caches/abs-android-native-claude/artifacts/`. The worktree's `artifacts` link to it has been removed.

## Issue mapping (for ticket maintenance)

Source `f256272b` (f256272b76251decaafd5099e6568f3a6b77d890, branch `fork/android-l10n-bookmarks` from `fork/native-tv` at 79b31196): one full run passed 88 of 88, that is 83 of 83 journeys in 23 classes plus `CastHandoverTest` 5 of 5. Unit tests pass (core 63, app 6). The two full runs before it on this branch each had one failure, both kept with their own XML: 2efb7f3d (87 of 88, the Chrome sign-in page; harness fixed in e3627918) and e3627918 (87 of 88, a lost listening write; fixed in f256272b); see Journey failures below. The bookmarks journey signal from 83826111 has not recurred but its cause is unknown, so it stays open. The APK is packaged from the merged source after root's merge and recorded on the pull request. All evidence is emulator plus synthetic fixture; nothing physical is claimed. Not a full replacement: casting (#49) has not been tried with a real receiver, localization is partial, and the physical gates below remain.

Previous source `83826111` (838261115c03b2bb67340191249f9f493d3132a9): one full run passed 80 of 81 journeys plus `CastHandoverTest` 5 of 5, not a clean full run; packaged APK SHA-256 `e406678e3ba84167a5c1608867242ace7a4e27000794a6d1a412b1c8cc7975a9` (22214564 bytes), kept at `/Volumes/ai-ssd/developer-caches/abs-android-native-claude/artifacts/audiobookshelf-native-preview-83826111.apk`.

| Issue | Status | Evidence | Open follow-ups |
| --- | --- | --- | --- |
| #31 connect and sign in | Done (emulator) | ConnectionJourney | |
| #32 OpenID, multiple servers | Done (emulator) | AccountsJourney | |
| #33 browse and inspect | Done (emulator) | BrowseJourney, FilteredScreen paths | |
| #34 stream multi-file audio | Done (emulator) | PlaybackJourney | |
| #35 durable listening progress | Done (emulator) | ListeningDurability, ListeningRecovery, LatePublication, ProgressReset | Listening held in memory while storage refuses writes is lost if the process dies first |
| #36 background playback, system controls | Partial | PlaybackJourney (media session) | Lock screen, Bluetooth and headset controls on a device |
| #37 chapters, speed, bookmarks | Done (emulator) | PlayerToolsJourney | Bookmark journey failed in two runs at 83826111, not since; cause unknown |
| #38 sleep timers, advanced playback | Done (emulator) | PlayerToolsJourney, SettingsJourney | Shake and chime on a device |
| #39 search and discovery | Done (emulator) | BrowseJourney | |
| #40 collections and playlists | Done (emulator) | GroupsJourney | |
| #41 podcasts | Done (emulator) | PodcastJourney | |
| #42 download and manage | Done (emulator) | DownloadJourney | Real metered networks |
| #43 offline and reconnection | Done (emulator) | DownloadJourney, MigrationJourney d, LatePublication | Real network loss |
| #44 local files and opening | Done (emulator) | LocalFilesJourney | |
| #46 PDF | Done (emulator) | PdfJourney (10) | |
| #49 casting | Implemented; receiver acceptance pending | `CastMediaTest` (3), `CastHandoverTest` (5), CastJourney (no receiver on the emulator network) | **Physical receiver journey not run**: connecting, remote controls, transfer back on receiver loss and progress while casting are untested on a real Chromecast/Google TV |
| #50 Android Auto | Partial | CarJourney | Car or Desktop Head Unit |
| #51 preferences, statistics, diagnostics | Done (emulator) | SettingsJourney | |
| #52 migrate accounts and listening | Done (emulator, synthetic archives) | MigrationJourney, MigrationSelectionJourney, LegacyImportTest, legacy `LegacyMigrationExportTest` | Owner device export and import; legacy export screen driven by hand; `ereaderSettings`, `playerSettings` and `lastLibraryId` preserved but not applied (the legacy app language is applied since 28cde313); listening history and logs not exported |
| #53 migrate downloads and reading locations | Done for audio and PDF (emulator) | MigrationJourney c, d, f | EPUB and other locations preserved, applied when #45/#47/#48 exist; a file damaged after commit is fetched from the server, not the archive; legacy downloads in user-chosen (SAF) folders not exercised on a device |
| #54 internal readiness | Partial | `verification/android-evidence.json`, AccessibilityJourney (ATF), `scripts/package.sh` | **Localization partial**: all UI text is in resources (579 strings) with legacy translations for 146 in 33 languages besides English, right-to-left checked in Arabic (LocalizationJourney); copy the legacy app only had in English and the 11 `core` error messages stay English (see Localization); TalkBack by a person; owner signing key; install on the owner's phone |
| #45, #47, #48 | Deferred (after #65) | | Files and locations are preserved by migration |


## Casting (#49) in 097bd373, corrected in 10a78ee5, e89c584b and 83826111

- The player's cast button opens a sheet listing receivers for the existing app's Audiobookshelf receiver (`FD1F76C5`, the same id as legacy `CastOptionsProvider`). While connected it shows "Playing on <receiver>" and offers Stop casting. The receiver app stops when the session ends, as in legacy.
- Media3 `CastPlayer` wraps the phone's ExoPlayer and a `RemoteCastPlayer`. On connect it moves the queue, position and play state to the receiver, and back to the phone when the session ends or the receiver is lost. The engine keeps journaling and publishing listening from whichever player is active, under the same server session.
- Track URLs follow legacy `PlaybackSession.getContentUri`: direct play on servers from 2.22.0 uses `/public/session/<id>/track/<index>`, transcoded streams use their server path, and older servers get `?token=`. The server version comes from `/status`, fetched once per server per process when casting is possible.
- Downloaded titles stay on the phone. Opening one while casting is refused with an explanation. Media3 cannot be stopped from switching to the receiver, so connecting while one is loaded keeps it on the phone, ends the receiver session and explains why. Media3 then switches back and the phone resumes at the same part and position if it was playing (`CastHandover`).
- Review blocker at 097bd373, found by the lane review and root's review: the transfer callback returned early, but Media3 1.9 `CastPlayerImpl.updateActivePlayer` still prepares the receiver, stops the phone and switches. The phone was left stopped, and ending the cast copied the receiver's empty queue onto it, dropping the downloaded title. `CastHandoverTest` replays that switch order with real ExoPlayers. It failed at 097bd373 (the phone kept 0 of 2 downloaded parts) and passes at 10a78ee5.
- Second review blocker at 097bd373, from root's spec review: if the app process dies while casting, the cast framework resumes the receiver session on relaunch, but no title, account or listening record is open on the phone. The receiver could keep playing with nothing saving progress, and ending the cast would copy its queue onto the phone under whichever account was active. Now the real session listener (`CastRoutes.resumed`, called from `onSessionResumed`) asks the engine whether a title is open. If none is, it ends the receiver session and shows "Casting stopped because the app restarted while casting. Open the title again to keep listening from the last place this phone saved." A receiver queue no open title accounts for is not copied to the phone. `CastHandoverTest` b and c failed before the fix (1 leftover item reached the phone; no notice) and pass at e89c584b. Rebuilding a remote session after a restart is not attempted. A real receiver resume after a restart is not verified.
- Third review blocker at e89c584b, from root's review: Media3 1.9 prepares the destination player only when the source player is not idle, and the earlier test helper checked the destination instead. A receiver given no queue is idle when its session ends, so the kept download came back stopped and could not resume. A second root reviewer also found that the kept queue was restored without checking that its title was still open. Since 83826111 the return prepares the phone explicitly. The kept queue is tied to the exact open title: if that title was closed or replaced (for example by an account switch) while the session was ending, its parts are cleared and not resumed. A pause made in that window is kept. `CastHandoverTest` now replays the SDK's real condition. Its five tests failed in three places at e89c584b (phone left stopped, closed title kept, pause lost) and pass at 83826111.
- A full run on e89c584b was also stopped by this lane after that review. Its partial log is under `artifacts/interrupted-e89c584b/` and counts as interrupted, not passed.
- A full run on 10a78ee5 was stopped by this lane once the second blocker was confirmed. Its partial log is kept under `artifacts/interrupted-10a78ee5/` and counts as interrupted, not passed.
- Test runs at 83826111. The affected classes (Cast, Playback, PlayerTools, Download, LocalFiles, ProgressReset, Accounts) passed 26 of 27, and the full run passed 80 of 81 journeys. Both failures were the bookmarks journey timing out at a different stage. In the affected run it timed out after reopening the sheet (line 55, `delete-bookmark-0`). In the full run it timed out on first opening the sheet (line 35, `bookmarks-empty`), so one cause is not proven. The class passed 2 of 2 alone. Nine further runs in suite-like orders used a temporary, uncommitted dump of the screen and fixture requests on failure, and none reproduced it. No failure screen or response was captured, and the app logged nothing between pausing and the timeout. No product or harness cause is confirmed. Timeouts and assertions are unchanged. In 2 of those 9 runs, `PlaybackJourney` a timed out waiting for the stream close request (line 59); it passed in the full and affected runs. Results are under `artifacts/full-83826111/` and `artifacts/targeted-83826111/`.
- Auto-rewind and the sleep-timer fade change only the phone's volume, never the receiver's.
- Actionable states: no receivers found (checked on the emulator), Play services missing or unable to start, connection failed, connection lost. The last three are not exercised by a test.
- Differences from legacy: the server session keeps `mediaPlayer: "exo-player"`; legacy reopened the session as `cast-player`. Legacy's separate cast volume mapping on the media session is not carried over. The cast sheet text is English only.
- Before the commit, one full run of the same code passed 78 of 81. PlaybackJourney a, ProgressResetJourney a and LocalFilesJourney failed. Rerun, those classes passed 15 of 15. PlaybackJourney a failed once more with a second listening session, which comes from a listening write that went unanswered, and then passed 3 of 3 alone. The full run of the committed 097bd373 passed 81 of 81.
- RED: `CastMediaTest` failed 2 of 3 against a stub that returned the phone URL. `CastJourney` failed because the player had no cast button.
- **Pending, physical only:** a real receiver journey, covering discovery, connecting, play/pause/seek/speed on the receiver, receiver loss, and progress reaching the server while casting.

## Localization (#54, partial) in 9756f68e

- `app/src/main/strings/strings.tsv` lists every UI string. Each row names the legacy key in `/strings` whose meaning matches, or `-`. `scripts/import-legacy-strings.py` writes `res/values*/strings.xml` and `res/xml/locales_config.xml` from it. Only the legacy app's own translations are used; no service is involved.
- 579 strings are extracted: navigation, library, filters and sort, item, player and its tools, cast sheet, search, sign-in and accounts, settings, downloads, PDF reader, podcasts, collections and playlists, migration, Android Auto browsing and accessibility descriptions. 146 of them have a legacy translation. 33 languages translate at least 80% of those and are offered in the system's per-app language setting (Android 13 and later). `et`, `fa`, `gu`, `hi`, `is` and `lt` have partial files and fall back to English; `lv` and `uz` have no translations.
- Placeholders: a legacy `{0}` becomes the English placeholder of the same position and type (`%1$d` or `%1$s`), so numbers are formatted for the language. A translation is used only when its placeholders match English exactly. Counts use `<plurals>`; a language gets a translated plural only when every quantity is translated, otherwise it falls back to English.
- Rows stay English where the legacy wording means something else, for example the notification's jump buttons, screen orientation (legacy "Lock orientation"), "Read PDF" and "Mark finished". The fourth column excludes single languages whose legacy wording is wrong in this context, for example Japanese "More" (多い), German "Low" (Wenig) and the haptic "Light", which 18 languages translate as the colour.
- Copy that the legacy app only had in English stays English in every language (about 430 strings, for example "Sort", "Ascending", "Playing", "Resume" and most explanations). No translation is promised for them.
- Right-to-left: layouts mirror (checked in Arabic), and icons that point use the auto-mirrored variants.
- **Still English:** messages built in `core` (`ApiError`: server unreachable, untrusted certificate, session no longer accepted, HTTP failures, 11 texts) are shown as is in about 20 failure paths, and diagnostics log entries are English by design. A few texts are resolved once and kept (a failed download's error, the playback save error, import issue details), so they stay in the previous language after the app language changes until they are produced again.
- RED: with Arabic, `LocalizationJourney.libraryControlsReadRightToLeftInArabic` found the mirrored top bar but timed out waiting for the Arabic sort option (`artifacts/red-l10n-392b95e2/`). GREEN: Localization and Migration journeys 9 of 9 at 28cde313.

## Legacy app language (#52) in 28cde313

- The `lang` preference the legacy exporter copies is applied once with the other legacy settings: on Android 13 and later, when the app offers that language and the person has not already chosen an app language. Legacy codes map as in the importer (`no` to `nb`, `pt-br` to `pt-BR`, `vi-vn` to `vi`, `zh-cn` to `zh-CN`); `en-us` is the legacy default and changes nothing.
- RED: `MigrationJourney.g_theLanguageChosenInTheLegacyAppCarriesOver`, importing the synthetic export with `lang: "de"`, stayed English ("Verbinden" never appeared). GREEN after the change.

## Journey failures, session close, writes and the bookmark signal (f256272b)

- Failure-only capture (942ece9c, a51b0dc5, e3627918): a failed wait, playback-position wait or browser step saves a screenshot to `/data/local/tmp/abs-journey-failures` and logs the Compose semantics tree, the window hierarchy (browser steps), the app's media session state and the last 40 fixture requests with their status (tag `JourneyFailure`). `verify-journeys.sh` pulls them with the fixture logs to `app/build/outputs/journey-failures` only when a failure happened.
- Session close (392b95e2, corrected in 2efb7f3d): a stream close sent over a pooled keep-alive connection that the server was closing as idle failed as Offline, so the session stayed open (`PlaybackJourney` a, line 59) or the next listening went to a second session (line 62). In six exact-order runs (Cast, Playback, PlayerTools) before the change, PlaybackJourney a failed 4 times; after it, 0 of 6. Closing is idempotent (404 means closed), so only the close request itself is sent once more, with the same token. Root's review found that the first version repeated the whole operation, including a token refresh whose answer was lost, which would send the already replaced refresh token. `ApiClientTest.aCloseWhoseTokenRefreshLosesItsAnswerDoesNotRefreshAgain` failed on that version (2 refreshes) and passes at 2efb7f3d. A close that times out on a slow server is also sent again, so it can take up to about 60 s before it is deferred.
- Chrome sign-in page (e3627918): the full run at 2efb7f3d passed 87 of 88 (journeys 82 of 83, `CastHandoverTest` 5 of 5). `AccountsJourney` c timed out waiting for the local OpenID page (line 77; lines 64 and 94 are frames of the same stack). That run's `summary.txt` is wrong: its totals came out empty and it lists those three frames. `summary-from-xml.txt` is rebuilt from the run's own XML; `run.log` is unchanged. Its browser screenshot went to the app's cache and was lost to the next test's reset.
  - RED, harness unchanged except that browser failures now go through the capture: two runs in the full run's class order (Accessibility, Accounts) both failed. In the first, method a timed out at "Approve sign-in" and b and c failed after it because they build on a's accounts. The second failed exactly as the full run did (c, line 77). Both captures show the page drawn ("Local OpenID", "Approve sign-in" on screen) at the correct authorize address with fresh state and PKCE, while the window hierarchy holds only Chrome's toolbar and none of the page. Chrome logged that no accessibility service was enabled. The steps look the page up by its text, so they could not find it. Results: `artifacts/accounts-loop-2efb7f3d/` and `artifacts/accounts-loop-2efb7f3d-unchanged/`.
  - Fix: `verify-journeys.sh` gives Chrome `--force-renderer-accessibility` (read from `/data/local/tmp/chrome-command-line` while Chrome is the debug app) and clears both afterwards. 3 of 3 runs passed (`artifacts/accounts-loop-chrome-a11y/`). No product cause.
- Writes on idle connections (f256272b): the full run at e3627918 passed 87 of 88 (journeys 82 of 83, `CastHandoverTest` 5 of 5; `summary-from-xml.txt`, since that run's summary total is wrong). `PlaybackJourney` a reported two listening sessions instead of one (the assertion at the end of the method). The app logged "Listening kept for retry: Offline": a listening sync failed, so the next listening went to a new session, as designed for an unanswered write. Cause: writes reused pooled keep-alive connections. OkHttp checks an idle pooled connection for a close only after 10 s, while Node servers close idle connections after 5 s (checked against the fixture through `adb reverse`: Node closed the socket after about 6 s and a request sent on it after that got no answer). A write sent in that window went out on a closed connection and, as writes are never resent, failed. Writes now open a new connection each time. Their bodies are one-shot, so OkHttp still never resends a write once sending began, but a connection that cannot be made now tries the server's next address, which `retryOnConnectionFailure(false)` had also prevented. Both failed at e3627918 and pass since: `ApiClientTest.aWriteIsNotSentOnAConnectionTheServerClosedWhileIdle` (Offline, nothing reached the server) and `aWriteReachesTheServerWhenItsFirstAddressRefusesTheConnection` (an IPv6 address that refuses, then IPv4). Only the write client changed: the token refresh still goes through the ordinary client with OkHttp's automatic retry, as before, so OkHttp itself may resend a refresh whose connection failed (unchanged limit). Each write now costs a new connection, and with TLS a new handshake. Listening is published every 15 s while playing, longer than a Node server keeps an idle connection, so against such a server this adds little; the window was hit when another request had used the connection 5 to 10 s before the write.
- **Bookmark signal still open.** `PlayerToolsJourney` a failed in the full and affected runs at 83826111. It has not failed since: 6 exact-order runs (Cast, Playback, PlayerTools) before the close change, 6 after it and 6 at f256272b, the interrupted run at 28cde313 (19 of 88 done) and the full runs at 2efb7f3d and e3627918 (PlayerTools 2 of 2 each). Its cause is unknown, and the close change is not claimed to fix it. With the capture in place, a further failure records the screen, sheet semantics and the bookmark requests.
- One `CastJourney` timeout (line 38, phone position not advancing after closing the cast sheet) happened once in those 12 targeted runs, before the playback-position wait was captured. The emulator's audio output went to standby right after the sheet closed. Not reproduced since; cause unknown.

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

## Opening downloads and a chosen download folder (#44) in af39cff48222cba49455dfa249825fa18b6d8f2f

- A downloaded ebook opens in another app through the `${applicationId}.files` FileProvider. The provider is not exported and shares only `files/downloads/`. Opening grants read access to that single file (`FLAG_GRANT_READ_URI_PERMISSION`, no write).
- Downloads can go to a folder picked with the system picker (Settings, Storage). The app keeps a persisted read and write grant. Finished files are copied to `<folder>/<Author>/<Title>/` and removed from app storage.
- When the folder's grant is gone, Downloads says so, nothing plays from it, and the folder can be chosen again. A file removed by another app is reported as missing and can be downloaded again.
- Without an app for the format, the format is named (for example MOBI) instead of failing silently.
- No folder scanning: legacy upstream removed local folder scanning, so it is not carried over.
- **RED:** `LocalFilesJourney` failed 4 of 4 (no `open-elsewhere`, no `choose-download-folder`).
- **GREEN:** 4 of 4. The test APK's `OtherAppActivity` (its own uid) read the exact bytes (size and SHA-256), was refused writing, and could not read neighbouring files.
- **Regression:** Download, Pdf, Settings and Podcast journeys pass 24 of 24; unit tests pass.

## Android Auto browsing (#50)

- `PlaybackService` (Media3 `MediaLibraryService`) serves the existing app's car layout:
  - Root: Continue (only with titles in progress), Recent (per library shelves), Libraries, Downloads.
  - Book libraries: Authors, Series, Collections, and Discovery when the server has a discover shelf. Podcast libraries list podcasts, then episodes newest first.
  - Authors and series lists over the grouping limit split into letter groups, extended one letter at a time when a group is still too large (`CarBrowsing` in `:core`). The legacy crash on names shorter than the prefix and the empty group dead end do not occur.
  - Series books sort by sequence (`1`, `2`, `10`; `1.5` before `1.10`), prefixed with their number. An author's series appear as one entry (`collapseseries=1`).
  - Titles carry completion status and percentage. Downloaded titles are marked downloaded and play from the phone's copy, also when picked from server lists.
  - Without the server, the root still offers Downloads.
  - Voice requests (`playFromSearch`) play the title whose name matches, else the best match.
- Settings: "Group authors and series in letters above" (25/50/100/200/500, plus any migrated value) and "Series books order".
- Browsing is refused (`ERROR_PERMISSION_DENIED`) to apps other than this one, the existing app, Android Auto, the Auto simulator, Wear OS, Google app, car assistant and trusted system controllers. Playback controls are unchanged.
- Manifest: `com.google.android.gms.car.application` (`automotive_app_desc`, media) and the car notification small icon.
- **RED:** `CarJourney` failed 5 of 5 (root was Continue and Libraries only; no settings; foreign app allowed; voice request did nothing). `CarBrowsingTest` failed 5 of 6 on the stub, including decoding the single series object that filtered lists return.
- **GREEN:** `CarJourney` 5 of 5, using the platform `MediaBrowser`/`MediaController` protocol a head unit uses, and a browser in the test APK's own uid for refusal. Two fixes came out of the GREEN runs: `recent/<library>` was routed to the top Recent node (bug), and the test compared Int 2 with the Long download status (test error).
- **Regression:** Playback, Settings, Browse and Podcast journeys pass 17 of 17; unit tests pass.
- **Not verified:** a physical car or the Desktop Head Unit. The MediaBrowser contract is checked on the emulator only.

## Writes whose answer was lost (publication uncertainty)

Server 2.30 neither orders requests for one session or title nor says whether an earlier request has finished. Only the answer to a request shows that its handler is done. A retry being answered, a fresh GET, a timeout or the client coroutine ending does not.

| Defect | Fix | RED observed before the fix |
| --- | --- | --- |
| OkHttp silently sent a POST or PATCH again when a reused connection dropped after the request was written, so the app saw success and never learned the original might still land | Non-GET requests use a client derived with `retryOnConnectionFailure(false)` | `ApiClientTest.aWriteWhoseConnectionDropsIsNotSentAgainBehindTheCallersBack`: the write was sent twice and reported as a success |
| A late original listening write recreated progress after a discard | `PublicationLedger` (core) records every listening, page and mark-finished write before sending. It settles the record only on that request's own answer. 502, 503 and 504 count as unanswered (proxies send them after forwarding), and so do transport failures after connecting. A write that was out when the process died is unanswered after restart. A discard runs only while none of the title's writes is unanswered; otherwise the item screen explains the risk and offers **Discard anyway** or **Keep progress** (only while nothing was done for the discard). Nothing expires on its own. | `LatePublicationJourney.listeningThatReachesTheServerAfterADiscardDoesNotBringProgressBack`: progress came back at 10.47 s |
| A late original page write recreated reading progress after a discard | Same ledger around the ebook PATCH. Supplementary documents, other titles and history are unaffected. | `LatePublicationJourney.aPageThatReachesTheServerAfterADiscardDoesNotBringProgressBack`: `ebookLocation` 1 came back |
| A late older cumulative total replaced a newer one for the same session | A session with an unanswered write is frozen (`ListeningJournal.freeze`) and only ever sent again exactly as sent. Later listening continues in a new session holding only the new time. Each publish re-applies freezes recorded in the ledger, so a failed freeze or a restart cannot send another total for that session. | `LatePublicationJourney.listeningThatArrivesLateDoesNotShrinkTheListeningHistory`: sessions kept 5.5 s of about 10 s |

- The ledger fails closed. If its file cannot be read, every title counts as uncertain: no listening or page is sent, no discard runs and the file is never overwritten. Diagnostics offers an explicit **Set them aside**, which keeps the file.
- Core unit REDs:
  - `PublicationLedgerTest`, 5 tests: classification, restart, per title and account, kept listening snapshot, unreadable.
  - `ListeningJournalTest.listeningAfterAWriteWithoutAnAnswerGoesToANewSessionAndTheSentOneIsResentUnchanged`.
  - `ProgressResetsTest.aDiscardNothingWasDoneForCanBeWithdrawnButOneUnderWayCannot`.
  - The 503 case was first expected to be conclusive. It was made uncertain, RED first, once the GREEN run showed the shared proxy answering 503 for a dropped upstream.
- **Fixture wrapper:**
  - `/__android__/hold-late {kind, seconds}` drops the connection without an answer and replays the same request to the server later. `/__android__/late-applied` reports when it landed.
  - The wrapper's deliberate refusals (`refuse-reading`, `refuse-listening`) now answer 500. An answer from the server itself means not applied, which keeps those journeys' meaning.
- **GREEN:**
  - `LatePublicationJourney` 3 of 3; unit tests pass.
  - Full suite: 71 of 79 in one run. The 8 failures came from a transient fixture outage: the proxy answered 503 to fixture control calls such as `/__fixture__/configure`, and sign-ins timed out.
  - Rerun on the final build: ItemActions, Pdf, ReadingListening and Settings 19 of 19; LatePublication, ProgressReset, ListeningDurability and Playback 15 of 15.
- **Cause of the 8 failures in the 79-test run:** the Android fixture listened with the default backlog of 5 (the shared factory fix `23abaa51` is not in this branch's base). Bursts of the app's one-request HTTP/1.0 connections were reset, and the realtime proxy reported them as 503. The wrapper now listens with 128. A local burst of 300 concurrent connections gave 43 resets at backlog 5 and 0 at 128. The reruns above are not a substitute for a clean full run, which is still required before ready.
- **Limits:**
  - An uncertain title stays uncertain until the user chooses. Server 2.30 offers no way to prove an earlier request has finished, and no backend change is assumed.
  - A late older page can still overwrite a newer page on the server. The next sync sees a server change it did not make and asks the reader, rather than overwriting silently.
  - The listening snapshots in the ledger are kept until the user accepts the risk for their titles.

## Review blockers at c301f067

| Blocker | Fix | RED observed before the fix |
| --- | --- | --- |
| **Discard anyway** removed the ledger's listening snapshots before the journal had kept those sessions as sent. If an earlier freeze had failed and more listening was journaled, the session was later sent with a larger total under the original ID, and the delayed original could shrink it | `PublicationLedger.accept` takes the journal's freeze and applies it to every affected snapshot before changing the records. If a freeze fails, nothing is accepted, the title stays uncertain and the discard does not run | `PublicationLedgerTest.acceptingTheRiskKeepsTheUnansweredSessionAsSent`: the original session was sent with the larger total. `theRiskIsNotAcceptedWhileTheSessionCannotBeKeptAsSent`: accept went ahead with the journal unwritable |
| Startup froze the ledger's snapshots inside the journal's initializer. A relaunch with an unanswered snapshot and unwritable storage threw while constructing playback and progress sync | `ListeningRecovery` (core) freezes the snapshots and closes records left open, and reports a failure instead of throwing. Until it is saved, playback is refused with a storage message and progress sync sends nothing and retries. Each play attempt, sync retry and the Diagnostics **Try again** button (`listening-storage`, `retry-listening-storage`) runs it again. The ledger and journal are left untouched while it fails | `ListeningRecoveryJourney`: constructing playback after relaunch threw `FileNotFoundException ... EACCES` |

`ListeningRecoveryJourney` builds a fresh `AppGraph` over its own files directory (made read-only), so the relaunch is real for the graph without touching the app's own data. After storage recovers, the original session is pending only with its sent payload, and the 3 s listened later is in a new session.

Evidence: unit tests pass. In one run on `emulator-5584`: ListeningRecovery 1, LatePublication 3, ProgressReset 6, ListeningDurability 1, Playback 5 and ReadingListening 1, 17 of 17. A clean full run is still required before ready.

## Evidence for 2b3227dc (emulator and fixture only)

- Unit tests: `./gradlew :core:test :app:testDebugUnitTest`, 24 tests, 0 failures.
- Journeys on `emulator-5584` (API 36) against the local fixture on ports 28765/28766/28767/28769:
  - Browse, Connection, Download, Groups, ListeningDurability, Pdf, Playback, PlayerTools and Podcast: 39 of 39 pass.
  - AccountsJourney 3 of 3 pass after the emulator's Chrome was force-stopped.
- **Emulator caveat:** the first AccountsJourney attempt failed because Chrome on the emulator was stuck on an old fixture tab and never requested `/auth/openid`. Force-stop Chrome before the OIDC journey if this recurs.

## Review blockers at 274aa769

| Blocker | Fix | RED observed before the fix |
| --- | --- | --- |
| Manifest digests named staging and temporary files before any check, so a digest such as `../../planted` wrote outside staging | `LegacyArchive.open` refuses the archive unless every digest is 64 lowercase hex characters, and every stored path is `files/<24 hex>/<name>` with no `..`, belongs to a digest and is an entry in the zip. Nothing is written for a refused archive | `LegacyImportTest.anArchiveWhoseDigestsOrPathsCouldLeaveStagingIsRefusedBeforeAnythingIsWritten`: both crafted archives were imported |
| A file whose digest matched but whose move into staging failed was marked corrupt, and its title was left out of the committed import for good | Only a digest mismatch marks a file corrupt. A failed move removes the temporary copy and stops the import as an interruption. Nothing is committed, and choosing the same export again resumes it | `aFileThatCannotBeMovedIntoPlaceInterruptsTheImportInsteadOfCountingAsCorrupt`: the import committed without the files |
| A PDF downloaded without its title's audio was refused (`ITEM_CHANGED`) because zero legacy tracks did not equal the server's track count | A title with no legacy audio matches on its ebook alone (format and ino still checked) and is adopted as an ebook-only download. Audio identity checks are unchanged when audio is present | `aPdfDownloadedWithoutItsTitlesAudioIsMatchedOnItsOwn`: "Its audio files changed on the server" |
| Closing the import while an export was still being read did not stop the read, which then reopened the screen. A second choice shared and overwrote the first's temporary file | Each choice gets its own temporary file. A newer choice or closing cancels the read in progress. The read's copy loop stops, removes its own file once nothing writes it any more, and its result is dropped. Choices are ignored while an import runs, and closing does not stop an import | `MigrationSelectionJourney` (instrumented, using a test provider whose export arrives after 2 s): the screen reopened as `Refused` after close; the slower first choice replaced the second as `Ready(slow-legacy-export…)` |

Evidence: core and app unit tests pass. On `emulator-5584`, MigrationSelectionJourney 2 of 2 and MigrationJourney 5 of 5 in one run.

## Code review of b152be26..77cc455b

Findings fixed in the next commit:
- **Malformed sessions.** A legacy session with impossible values (negative or non-finite listening, no duration) made attachment throw, so that account's titles retried for ever without being saved as attached. The import now leaves such sessions out and reports them as `INVALID_RECORD`. RED first: `LegacyImportTest.listeningWithImpossibleValuesIsReportedAndLeftOutSoTheRestAttaches` (the session was imported).
- **Location filter.** Only a positive page number becomes a PDF position. Other locations, such as an EPUB CFI, stay in the import instead of reaching the PDF reader's primary entry.
- **Cancellation.** A cancelled import or attachment is no longer reported as a failure.
- **Duplicated track selection.** `Attachment.Match` now carries the server tracks it matched, and `Downloads.adopt` uses those instead of choosing them again.
- **Covers.** An adopted title's cover is fetched while it attaches, so finished titles show their cover offline.
- **Error wording.** Refusal messages come from `MigrationError` alone.

Not changed (judgement calls): long parameter lists on `ListeningJournal.adopt` and `LegacyImport.propose`, and a shared copy-loop helper.

## Review blocker at 598ba9c4

| Blocker | Fix | RED observed before the fix |
| --- | --- | --- |
| Resuming an interrupted import reused a staged file because it was recorded as verified and still existed, without reading it again. A copy truncated or damaged while the import was stopped was committed and adopted as complete | `LegacyImport.verified(file)` returns the staged copy only when its SHA-256 still matches the export's digest. Resume copies any staged file that fails this again from the archive, which is only ever read, so a stopped import can be resumed any number of times | `LegacyImportTest.aStagedFileDamagedWhileTheImportWasInterruptedIsCopiedAgainFromTheArchive` (4 copies instead of 5; the damaged file was kept) and `aStagedFileDamagedAfterTheImportIsNotOfferedForAdoption` (the appended-to file was returned) |
| Adoption at sign-in must not bypass the same check (found by the code review of this fix: a first version dropped a title with any damaged file, and deleted its intact files with it) | Attachment adopts only files that pass `verified`. A damaged file becomes a missing part of the adopted download and is fetched again from the server, ebook included. The intact files are kept, and the import reports `FILE_CORRUPT` for the title. After an import is committed, the same export is not read again (`Already`), so the server is the source for a damaged file | `MigrationJourney.f_importedFilesDamagedBeforeSignInAreDownloadedAgainInsteadOfDroppingTheTitle`: every staged file is damaged between import and sign-in; `offline-book-0` never appeared |

The diagnostic full run on 598ba9c4 failed one case, MigrationJourney c. It counted every download request in the fixture's log, including those made by DownloadJourney earlier in the same run. The journey now counts only requests made after it starts, like the other journeys. DownloadJourney, MigrationJourney and MigrationSelectionJourney then passed 14 of 14 in that order.

## Final acceptance at ecba6a5a

On `emulator-5584` (`abs_native_android_qa`, Android 16) with the loopback fixture only: one full journey run, 21 classes and 79 tests, 0 failures. Unit tests: core 56 and app 6, 0 failures. `scripts/package.sh` built and verified `app-release.apk` (`com.audiobookshelf.app.nativepreview` 0.15.0-native-preview, signed with the local debug key), SHA-256 `872a95b30e68fb9ccdc3e822810b16130b7185975d877681b79e066ceec126e6`. Details are in `verification/android-evidence.json`. Earlier full runs at 598ba9c4 and 11060261 were diagnostic only: 598ba9c4 failed the journey isolation case above. At 11060261, PlayerToolsJourney a timed out once and passed when rerun without changes.

## Migration from the legacy Android app (#52, #53)

The preview keeps its own identity (`com.audiobookshelf.app.nativepreview`, debug key), as the Apple preview does. It cannot read the legacy app's private storage, so migration is a faithful export and import, not an in-place upgrade.

**Export, in the legacy app.** A patch to the legacy web and Android sources adds **Settings > Export for the new app** on Android, in addition to iOS:
- `LegacyMigrationExporter`, `LegacyMigrationExportPlugin`, `plugins/legacyMigrationExport.js`, `components/settings/LegacyMigrationExport.vue` and `pages/settings.vue`.
- Merging `fork/native-tv` at f51b6e9e (merge 0dc9dadf) conflicted in the last three files. Each was resolved to keep the iOS export and add Android (`v-if="isiOS || $platform === 'android'"`).
- It writes `Audiobookshelf Export <date>.absmigration`. This is a zip of the iOS format 1 (`archive.json` with `formatVersion` 1 and `platform` `android`, files under `files/<digest>/<name>`, stored uncompressed). The user saves it with the system file picker.
- Paper records are exported as the legacy app's own JSON:
  - connections, device settings and allowlisted preferences;
  - reader web storage (`ereaderSettings`, `ebookLocations-*`);
  - local items, progress, sessions and running downloads.
- Tokens, refresh tokens, custom headers and the device identity are removed. The archive is written as `.partial` and renamed only when complete, and `archive.json` is written last.
- Nothing in the legacy installation changes.
- `LegacyMigrationExportTest` (legacy androidTest) seeds a synthetic installation on the emulator and asserts these properties. `android-native/scripts/export-legacy-fixture.sh` rebuilds `core/src/test/resources/migration/legacy-export.absmigration` from it.

**Coordinator note:** `pages/settings.vue` and `plugins/legacyMigrationExport.js` are shared with the Apple export. The Android change widens `v-if="isiOS"` and the "unavailable" text; merge this with the Apple branch's copy of those lines.

**Import, in the preview.** The user opens the export in one of two ways:
- with **Import from the previous app** on the sign-in screen or in Settings, through the system picker;
- by opening it with the app from a file manager.

The import works in these stages:
- **Preflight writes nothing.** It shows:
  - the accounts and titles;
  - what is not imported (another account's rows, unscoped titles, missing or corrupt files);
  - the space needed and free.
- **Import stages and verifies files.** Each file is copied to `files/migration/staging/<sha256>` and checked against the export's digest. Every verified file is recorded, so an interrupted import continues without copying it again.
- **Commit.** `outcome.json` commits the import. The same export again says it was already imported; a different one is refused. The legacy device settings and preferences are applied once.
- **Attach after sign-in.** Nothing attaches until the matching account (canonical server and user ID) signs in here. Then:
  - Each title is checked against the server's item (track count or the running download's indexes, and the ebook's format and ino). It is adopted as a finished download without fetching again; a running download fetches only its unfinished parts.
  - Unsent legacy sessions go to the server under their own IDs with their absolute totals.
  - Audio positions and PDF pages become this device's positions unless the server's are newer.
- **Preserved, not yet used.** EPUB and other locations, and reader settings, stay in `outcome.json` until those readers exist (#65).

**Rollback.**
- The legacy app and its data are never modified, and the export file is only read.
- Uninstalling the preview, or clearing its storage, removes everything the import added on this device. The legacy app keeps working throughout.
- **Not undone by uninstalling:**
  - Unsent legacy listening that the preview already sent to the server stays there, under the legacy session IDs. The legacy app would have sent the same sessions itself.
  - PDF pages and positions the preview later publishes also stay on the server.

**Users of the public upstream app** cannot run this export, since it exists only in the locally built fork. For them:
- sign in to the preview with the same server and account;
- server-held progress, finished state, collections and playlists follow the account;
- downloads are fetched again;
- anything the upstream app never sent to the server stays in that app. Open it online once first so it sends what it holds.

**Exported but not applied:**
- `playerSettings`.
- `lastLibraryId`: the preview picks the library per account at sign-in.
- EPUB and other non-page locations.
- Reader settings.

They are kept in `files/migration/outcome.json`. Legacy pages of supplementary PDFs are not in the legacy data model, so there is nothing to carry over for them.

**In-place upgrade, not done.** Replacing the legacy app in place would need:
- the same application ID `com.audiobookshelf.app`;
- the owner's release signing key;
- a reader for the legacy Paper/Kryo database and Capacitor storage.

None of these are available or attempted here. The owner's device and key were not used.

**Evidence (emulator `emulator-5584` and fixture only):**
- `LegacyImportTest`, 8 tests: preflight, staging, corruption, interruption and resume, repeat and refusal, matching and running downloads.
- The `ListeningJournalTest` adopt test.
- `MigrationJourney`, 5 of 5. RED first, 5 of 5 failing before the implementation. It covers:
  - a non-export file refused with nothing written;
  - a corrupt PDF reported while the rest imports;
  - import before sign-in, then on sign-in: the legacy session reaches the server with 7 s, the legacy jump, theme and settings apply, book-0 is not downloaded again, and book-4 fetches only `file/1`;
  - offline: the PDF reopens at page 2 and audio resumes at 9 s;
  - the same export again says it was already imported.
- **Gaps:**
  - The legacy export UI (plugin and Vue) is compiled but not driven on a device. Only the exporter itself ran.
  - Migration of the owner's real legacy installation is a physical gate.

## Internal readiness (#54)

**Identity:**
- Application ID `com.audiobookshelf.app.nativepreview`, label "Audiobookshelf Preview".
- The existing app's mark on a teal background, so it is told apart from the legacy `com.audiobookshelf.app` on the launcher.
- `versionName` `0.15.0-native-preview`, `versionCode` 200.
- It installs beside the legacy app and never reads or changes its data.

**Packaging:** `android-native/scripts/package.sh` runs the unit tests and builds `app-release.apk`. It verifies the signature with `apksigner` and prints the package identity and SHA-256.
- Signing uses the local debug key unless `ABS_ANDROID_KEYSTORE` (with `ABS_ANDROID_KEYSTORE_PASSWORD`, `ABS_ANDROID_KEY_ALIAS` and `ABS_ANDROID_KEY_PASSWORD`) names an owner keystore. The debug-key build is for internal installs only.
- Nothing is uploaded. Install with `adb -s <device> install -r app/build/outputs/apk/release/app-release.apk`.

**Backup and rollback:**
- `allowBackup` is off, so Android cloud backup does not copy server credentials or listening state.
- Credentials sit in `noBackupFilesDir`.
- The backup of record stays the legacy app and the server. The preview's own state is listening and reading not yet sent, which it publishes when online.
- Rollback is uninstalling the preview. The legacy app is untouched throughout.
- Before uninstalling, open the preview online once so unsent listening reaches the server. Diagnostics shows anything still waiting.

**Accessibility:** `AccessibilityJourney` runs the Accessibility Test Framework's checks on these screens and passes:
- sign-in, library, item, player, downloads, search and settings.

The checks cover speakable labels, touch target size and contrast. Removing the Settings button's label made it fail with `SpeakableTextPresentCheck`, so the check is live. The journey passed when first written, so it is a guard, not test-first evidence for a fix.

Not covered:
- TalkBack navigation by a person;
- large font scales;
- the reader and import screens.

**Localization: partial.** UI text is in resources with the legacy translations (see Localization). Messages built in `core` are still English.

## Real 2.30.0 server (pinned image, synthetic data) in c4cb1087 and 27ccefd9

Before this, every Android journey had only run against the Python and Node fixtures.

**Setup**
- `scripts/verify-real-server.sh` starts the web lane's unmodified QA container from the local pinned image `ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03` (2.30.0, never pulled).
- It runs under this lane's own name and ports: `abs-android-qa`, with the server on 28870 and its helpers on 28874-28876.
- Data is the synthetic library and the synthetic `qa` account, and the server is recreated fresh on each run.
- The emulator reaches it as 10.0.2.2, so turning the emulator's networking off really cuts it off.
- No owner server, owner data, real identity provider or receiver is involved. The Apple and web QA containers are not touched.

**Results** (RealServerJourney, emulator-5584)
- a: password sign-in, browse, and streaming to 33 s of a book of three 30 s files, so into its second file, with the paused position stored on the server. Passed. It does not prove playback through all three files.
- b: a PDF page turn is stored on the server (`ebookLocation`). Passed.
- c: a downloaded book played offline with networking off, then its listening is stored on the server after reconnect. Passed.
- d: a downloaded book finished offline. **Fails on 2.30.0.**
  - After reconnect the server stores the end position (20.06 of 20.06 s) but `isFinished` stays false.
  - The server log shows "Creating new media progress" with no finished marking.
  - In 2.30.0, a local session that creates a title's first progress (`User.createUpdateMediaProgressFromPayload`, create branch) takes `isFinished` only from the payload. Its 10 s finished rule (`MediaProgress.applyProgressUpdate`) runs only for existing progress.
  - RED evidence: `artifacts/real-server-6-d`.
  - A client patch that marks such titles finished made d pass (`artifacts/green-real-server-finish`). It is held back, not merged: it adds a progress write, and its check reads progress the server may serve from its user cache, where Apple found a 2.30.0 cache race. Open for root's decision.

**Client defect found and fixed** (27ccefd9)
- A finished book showed "Finished" with a pause button, and the mini player stayed in its playing state.
- Media3 keeps `playWhenReady` at the end of the last file, and its callback overwrote the paused state set on end.
- RED: PlaybackJourney e at line 131 (`artifacts/red-playing-after-end`). GREEN: Playback 5/5 and RealServer a-c (`artifacts/green-playing-after-end`).

**Harness mistakes during these runs** (not product defects)
- The Downloads tab was tapped while the item detail covered it.
- b and c relied on an earlier test's sign-in.
- A reused server let playback start past the checked position.
- d first waited for the mini player rather than the finished state.

**Unchanged**
- 2.30.0 has no podcast progress concern for Android: it always reads episode progress with the episode ID.

## Known limits

- Listening that is held in memory because storage refuses writes is lost if the process dies before storage recovers. The player pauses and warns as soon as a write fails, which bounds the loss to the listening already played.
- `PlayerToolsJourney.a` failed in two runs at 83826111 and has not failed since; cause unknown (see Journey failures).
- While a discard is pending (offline, or listening not yet sent), the title does not play and shows "Discarding progress" until the server confirms.
- Physical-only gates are not yet exercised:
  - Bluetooth, lock screen and Android Auto controls, and a physical car or Desktop Head Unit.
  - Real metered networks.
  - Export and import of the owner's real legacy installation.
  - TalkBack use by a person, and installing the packaged APK on the owner's phone.

## Running the checks

```sh
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ANDROID_HOME=~/Library/Android/sdk
cd android-native
./gradlew :core:test :app:testDebugUnitTest
scripts/verify-journeys.sh [JourneyClass ...]   # refuses to start if any fixture port is already in use
```
