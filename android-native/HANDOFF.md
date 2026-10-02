# Native Android handoff

Branch `fork/native-android`, based on `origin/fork/native-tv` at `39ad6af65715957c585e7b0f0d20238ebe60ee8f`.
Not merged into `fork/native-tv`. The app installs as the preview identity
`com.audiobookshelf.app.nativepreview` beside the legacy `com.audiobookshelf.app`, which it never touches.

## Issue mapping (for ticket maintenance)

Source `87984807`: the full suite at `ecba6a5a` (79 of 79, see "Final acceptance at ecba6a5a"), plus layout fixes verified by Accessibility, Pdf, Browse, Download and Playback journeys (26 of 26) and screenshots. All evidence is emulator plus synthetic fixture; nothing physical is claimed. Not a full replacement: see the follow-ups.

| Issue | Status | Evidence | Open follow-ups |
| --- | --- | --- | --- |
| #31 connect and sign in | Done (emulator) | ConnectionJourney | |
| #32 OpenID, multiple servers | Done (emulator) | AccountsJourney | |
| #33 browse and inspect | Done (emulator) | BrowseJourney, FilteredScreen paths | |
| #34 stream multi-file audio | Done (emulator) | PlaybackJourney | |
| #35 durable listening progress | Done (emulator) | ListeningDurability, ListeningRecovery, LatePublication, ProgressReset | Listening held in memory while storage refuses writes is lost if the process dies first |
| #36 background playback, system controls | Partial | PlaybackJourney (media session) | Lock screen, Bluetooth and headset controls on a device |
| #37 chapters, speed, bookmarks | Done (emulator) | PlayerToolsJourney | Bookmark journey flaked once in a full run |
| #38 sleep timers, advanced playback | Done (emulator) | PlayerToolsJourney, SettingsJourney | Shake and chime on a device |
| #39 search and discovery | Done (emulator) | BrowseJourney | |
| #40 collections and playlists | Done (emulator) | GroupsJourney | |
| #41 podcasts | Done (emulator) | PodcastJourney | |
| #42 download and manage | Done (emulator) | DownloadJourney | Real metered networks |
| #43 offline and reconnection | Done (emulator) | DownloadJourney, MigrationJourney d, LatePublication | Real network loss |
| #44 local files and opening | Done (emulator) | LocalFilesJourney | |
| #46 PDF | Done (emulator) | PdfJourney (10) | |
| #49 casting | **Not implemented** | None. The legacy app has `CastManager`/`CastPlayer`; the native app has no cast code | Whole story, including a real receiver |
| #50 Android Auto | Partial | CarJourney | Car or Desktop Head Unit |
| #51 preferences, statistics, diagnostics | Done (emulator) | SettingsJourney | |
| #52 migrate accounts and listening | Done (emulator, synthetic archives) | MigrationJourney, MigrationSelectionJourney, LegacyImportTest, legacy `LegacyMigrationExportTest` | Owner device export and import; legacy export screen driven by hand; `ereaderSettings` and some preferences preserved but not applied; listening history and logs not exported |
| #53 migrate downloads and reading locations | Done for audio and PDF (emulator) | MigrationJourney c, d, f | EPUB and other locations preserved, applied when #45/#47/#48 exist; a file damaged after commit is fetched from the server, not the archive; legacy downloads in user-chosen (SAF) folders not exercised on a device |
| #54 internal readiness | Partial | `verification/android-evidence.json`, AccessibilityJourney (ATF), `scripts/package.sh` | **Localization partial**: main screens carry legacy translations in 32 languages; about 350 UI lines are still English only (see Localization); TalkBack by a person; owner signing key; install on the owner's phone |
| #45, #47, #48 | Deferred (after #65) | | Files and locations are preserved by migration |


## Localization (#54, partial)

- `app/src/main/strings/strings.tsv` lists the app's extracted strings. Each row names the legacy key in `/strings` whose meaning matches, or `-`. `scripts/import-legacy-strings.py` writes `res/values*/strings.xml` and `res/xml/locales_config.xml` from it. Only the legacy app's own translations are used; no service is involved.
- 90 strings are extracted: navigation, library shelves, item actions, player, search sections, sign-in fields and the main settings. 80 of them have a legacy translation. 32 languages translate at least 80% of those, and they are offered in the system's per-app language setting (Android 13 and later). `et`, `fa`, `gu`, `hi`, `is` and `lt` have partial files and fall back to English; `lv` and `uz` have no translations.
- Rows were left unmapped where the legacy wording means something else: the notification's jump buttons (legacy text is the setting "Jump forwards time"), screen orientation (legacy "Lock orientation"), and "Add to playlist or collection".
- **Not yet extracted:** about 350 lines of English text remain in the UI, most of them error and explanation messages, plus dialogs, downloads, PDF reader, podcasts, groups, migration, diagnostics, statistics and accessibility descriptions. They show in English in every language.
- RED: `LocalizationJourney` with the app language set to German did not find "Verbinden" on the sign-in screen. GREEN: Localization, Accessibility, Settings, PlayerTools and Browse journeys pass 12 of 12.


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
- `playerSettings` and `lang` (the preview is English only, see Localization).
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

**Localization: not met.**
- The legacy app ships 38 locales (`strings/*.json`).
- The native preview is English only, and its strings are written inline in Compose.
- Moving them to resources and carrying over the legacy translations is required before replacement.

## Known limits

- Listening that is held in memory because storage refuses writes is lost if the process dies before storage recovers. The player pauses and warns as soon as a write fails, which bounds the loss to the listening already played.
- `PlayerToolsJourney.a` (`delete-bookmark-0`) has flaked once in a full run. The fixture reset in 5068c1d3 removes the cross-class bookmark state behind the `bookmarks-empty` failure.
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
