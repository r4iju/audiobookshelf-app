# Discarding progress on Apple

The legacy app (`components/modals/ItemMoreMenuModal.vue:73`, `:368`) offers "Discard Progress" for a book or episode with progress. After a `HeaderConfirm` / `MessageConfirmDiscardProgress` confirmation, it removes the local progress and calls `DELETE /api/me/progress/:id`. The native app now has the same operation as one owned player call. The confirmed button is a separate root patch.

## Server 2.30 contract

These come from the 2.30 source; nothing was invented.

- `GET /api/me/progress/:libraryItemId/:episodeId?` returns the user's `MediaProgress` with its row `id`, or 404 when there is none.
- `DELETE /api/me/progress/:id` takes that row ID, removes it (`removeById`), answers 200 even for an unknown ID and emits `user_updated`.
- `POST /api/session/local-all` (`syncLocalSession`) updates progress unless the row's `updatedAt` is later than the session's, and creates a row when none exists. Listening that is still unsent at the delete will therefore bring the deleted progress back.
- The row holds the ebook location too, so a book reset also clears where reading resumes.
- There is no request barrier, idempotency key or restart marker. A handler keeps running after its client gave up: a `local-all` (`syncLocalSession`), a progress PATCH (`MeController.createUpdateMediaProgress`) or a session `/sync` that reaches its progress lookup after the delete creates a new row (`User.createUpdateMediaProgressFromPayload`). A replay of the same payload being accepted, a fresh `GET`, or time passing proves nothing about the original handler. Only an answer to that exact request does. `/status`, `/ping` and `/healthcheck` carry no start time.
- A late `local-all` handler also undoes what was sent after it:
  - It replaces a stored session's `currentTime`, `timeListening` and `updatedAt` unconditionally (`syncLocalSession`), so a later cumulative revision of the same session loses listening.
  - Its progress check reads `req.user`'s progress as loaded at request start (`getUserByIdOrOldId` with `mediaProgress`, unless the LRU `userCache` hands out a shared instance). `applyProgressUpdate` then sets the row with no time comparison, so it can rewind a newer position.
  - A progress PATCH likewise sets whatever it carries.

## Operation

`APIClient.progressRowID(itemID:episodeID:authorization:)` looks up the row, and `APIClient.deleteProgress(rowID:authorization:)` deletes it. Both are pinned to the sign-in that started the reset. Server 2.30 creates progress with a fresh `UUIDV4` row ID (`MediaProgress.init`, `createUpdateMediaProgressFromPayload`). Deleting a recorded row ID again therefore never removes progress recreated later, and it answers 200 once the row is gone.

`ApplePlayback.resetProgress(account:itemID:episodeID:prepare:)` is the shared operation. It compiles for TV because the mobile-only work arrives through a `prepare` closure and registered cleanups. In order, it:

1. Refuses while another reset, a preparation, closing or seeking is in progress.
2. Checks the account and `authorizationRevision` before and after every await, so an A to B to A sign-in change cancels it.
3. Stops the media if it is open, and waits for any reading publication.
4. Throws `ApplePlayback.UnresolvedProgressWrites` with nothing changed while a progress write for the media may still be applied by the server (see "Writes the server may still apply"). It checks this:
   - before publishing anything, because such a write holds back every other write for the media;
   - when the flush or `prepare` fails;
   - after both;
   - again right before the intent is saved.

   Otherwise it flushes the listening journal and runs `prepare`. If listening for this media is still unacknowledged, nothing has changed and the call throws.
5. Looks up the row and saves a `ProgressResetIntent`, with the account, media, row ID and confirmation time, to `NativeListening/progress-resets.json`. If this write fails, nothing has changed and the call throws.
6. Finishes the intent:
   1. deletes the row;
   2. records a zero remote position, dated at the confirmation, in the listening journal;
   3. runs every registered cleanup;
   4. removes the intent.
7. Returns `GET /api/me` and remembers it.

Any failure after step 5 throws "Discarding progress has not finished", with the cause, and keeps the intent. Sign-in changes are the exception: they cancel silently, and the intent waits for the account. While an intent is pending, the media is on hold:

- `start` and `startOffline` first try to finish the intent and refuse to play while they cannot, so an old download snapshot never opens.
- `ReadingStore.sync` skips the book's pages.
- Adoption sync does not send the media's carried-over positions.

An intent is finished by the next `resetProgress` of the same media (without confirming again or looking up a new row), by `start` or `startOffline`, and by `restoreListening`. `ConnectionStore` already calls it on launch restore, sign-in and connection switch. Root may also call `resumeProgressResets()` on realtime reconnect. A relaunch reads the intents from disk. Finishing is repeatable: deleting the row again is harmless, and cleanups keep copies dated after the confirmation.

Two stores register cleanups when they are created, so a relaunch needs no extra wiring:

- **`ReadingStore` (reading):** `discardProgress(account:itemID:confirmedAt:)` replaces the book's primary EPUB and PDF positions with an empty, non-pending location dated at the confirmation. Readers open an empty location at the start. Positions saved after the confirmation, and supplementary documents, are kept.
- **`NativeMigrationAdoption` (carried-over):** `retireProgress` marks the media's unsent legacy positions resolved.

`NativeMigrationAdoption.prepareProgressReset` is the iOS `prepare`. It delivers carried-over legacy listening, because a later `local-all` would recreate the deleted progress, and throws while any of it is owed. It no longer retires positions before the intent exists. `canPublishReading` stays false while a reset runs.

Files changed outside `ApplePlayback.swift`:

- `APIClient.swift`: the two routes.
- `ListeningSync.swift`: `ProgressResetIntent`, its file, and `forgetPosition(at:)`.
- `ReadingStore.swift`: the cleanup, the sync skip, and an internal `player`.
- `AdoptionSync.swift` and `NativeMigrationAdoption.swift`: prepare, retire and the send gate.
- `AdoptionHarness.swift`: a per-test intent file.

## Writes the server may still apply

`PublicationLedger` (`apple/Playback/PublicationLedger.swift`, `NativeListening/publications.json`) is the one record for every progress write this app sends: listening `local-all`, primary reading PATCH, mark finished, and carried-over `local-all`, `/sync` and PATCH. Supplementary documents publish nothing and are not involved.

- **Before transmission:** each transmission (account, media, method, path and exact body, no headers or token) is saved as its own write, including a resend after a 401. `APIClient` calls an `issuing` hook right before it hands each transmission to `URLSession`, and reports that transmission's outcome to what the hook returned. Adoption saves each one in its own `send`. If it cannot be saved, nothing is sent.
- **Send gate:** while a write for the account's media is unresolved, `issue` lets through only a write that repeats it exactly: same method, path and JSON body. Whichever handler runs last then leaves the same. Anything else throws `PublicationLedger.Failure.waiting` before sending and stays on this device:
  - a later cumulative revision of the session;
  - new listening;
  - a different page;
  - mark finished;
  - carried-over sessions and positions for the media.

  The listening flush skips a waiting session and goes on with other titles. Adoption keeps waiting sessions and positions pending, never `unconfirmed`. The journal acknowledges only the revision sent, so newly earned listening stays as one cumulative session and is sent once.
- **Resolved** only when the request itself was answered by the server, or certainly never left the device (no connection, host not found, TLS refused, no sign-in, cancelled before sending). A 408, 502, 503 or 504 is a gateway answering and counts as unknown, like a timeout, lost connection or cancellation in flight.
- **Never resolved** by a replay being accepted, a later `GET`, a heartbeat or elapsed time. Each replay is its own write. The listening journal acknowledges only the revision a request carried, and reading clears its pending page only when the revision sent is still current, so a replay never acknowledges a newer payload.
- **Reset gate:** after the flush and `prepare`, `resetProgress` throws `UnresolvedProgressWrites` while any unresolved write covers the account's media. Nothing is deleted, the intent is not saved, and local positions and history stay. Other titles are unaffected.
- **Relaunch:** writes are on disk; one saved but never answered (the app stopped mid-request) stays unresolved.
- **Unreadable record:** the file is copied to `publications-unreadable-<ms>.json`, kept for recovery, then atomically replaced by a new record that marks every earlier write to every server unknown. Every write waits and all resets refuse until a restart is confirmed. If it cannot even be read from disk, copied or replaced, nothing is sent and every reset refuses, and the unreadable record stays in place, so a later launch sets it aside again rather than starting an empty record. `PublicationStorageTests` checks this on a full volume (`apple/scripts/verify-download-storage.sh -only-testing:NativeTests/PublicationStorageTests`).
- **Resolution:** server 2.30 offers no way to learn that a held handler finished. A server restart ends them all, so recovery has two steps:
  1. `ApplePlayback.requestServerRestart(account:)` records the server's unresolved write IDs before the owner is told to restart.
  2. `confirmServerRestarted(account:)` then resolves only those IDs, and the unreadable-record marker set before the request. It throws when no restart was requested.

  A write issued after the request may have reached the restarted server and stays unresolved. The moment of confirmation is never taken as the restart time.

  `BookDetails` offers two ways in, and both request the restart before showing "Restart the server now", then confirm with "Server restarted":
  - the reset refusal's "Try again";
  - a notice on any title with an unresolved write, with "Restart the server". It refreshes on `PublicationLedger.changed` for the signed-in account and that title, so it appears while the details are open when a background save, such as the player's on pause, gets no answer. After confirming, it sends what waited. `PublicationRecoveryJourney` checks this on phone and pad (`apple/scripts/verify-publication-recovery.sh`, held-sync fixture on `ABS_PUBLICATION_QA_PORT`). A gateway that queues a request across the restart and forwards it afterwards would defeat this, which common proxies do not do for POST or PATCH by default.

Carried-over adoption follows the same rule. Its replay paths (the downloaded-session `local-all` resend, the closed-row resend of the issued total) record each attempt. `prepareProgressReset` still skips sessions marked `unconfirmed`, because they are never sent again; whether a write of theirs may still be running is the ledger's question, so the reset still refuses while one is.

## Root handoff

`APPLE-PROGRESS-RESET-UI.patch` (next to this file) is the root-owned UI. It needs this branch's core change. It applies cleanly to 6ac3f2ee, and with `git apply -3` to the current `origin/fork/native-tv` and to `fork/apple-final-integration` at 713c93f8. On the integration branch, leave out the generated string tables and `COVERAGE.md` (`--exclude='apple/Localization/COVERAGE.md' --exclude='apple/Localization/Sources/*'`), then run `python3 apple/Localization/generate.py`. The patch:

- `BookDetails`: a "Discard progress" button for a book or an individual episode whose `progress` or `ebookProgress` is above zero, as in the legacy `progressPercent > 0`. It confirms with an alert titled "Confirm", with the legacy message and a destructive "Discard progress" action. The alert is attached to a clear background of the button. The view's existing finish confirmation suppresses alerts attached to its descendants, so attaching it to the button itself never showed it (reset UI QA, iOS 27). The background form also works on iOS 14, which shows only one `.alert` per view. It uses `progressBusy`, cancels the detail request and shows errors through `ConnectionStore.recovery`. After success, the stale `progress` the view was opened with is no longer used as a fallback. This is independent of `clearProgressFailure`.
- `NativeMigrationStore.resetProgress`: passes its private `adopter` to the player operation. Reading cleanup is registered by `ReadingStore`, so the UI passes no store. A thrown "has not finished" error is shown through `ConnectionStore.recovery`, and confirming again finishes the saved reset.
- `CatalogStore.discardProgress`: applies the user and removes the reset book or episode from Continue Listening, which `applyProgress` keeps when progress is absent.
- Localization: maps "Discard progress", "Are you sure you want to reset your progress?" and "Confirm" to `MessageDiscardProgress`, `MessageConfirmDiscardProgress` and `HeaderConfirm`, with regenerated tables.

Root also owns realtime: the server's `user_updated` after the delete reaches other clients through the existing stream.

## Limits

- The server keeps no tombstone. A legacy import run after the reset adopts that backup's positions again, as a fresh import would. Another device's unsent listening can recreate the row through `local-all`, as it would in the legacy app.
- A pending intent waits for its account. Signed in as someone else, it stays on disk and holds back only that account's media.
- An unreadable intent file counts as pending for every media: playback refuses, and reading and carried-over positions wait, rather than risking a recreated row.
- Pages read after the confirmation while the reset is pending are kept and published once it finishes. No test distinguishes this rule; see the mutation results.
- A write can stay unresolved for good until the owner confirms a server restart. Until then, all later progress for that media (listening, pages, finished, carried-over) waits on this device. A single timeout therefore holds a title's progress back until a restart, which is the cost of not inventing a server guarantee. Exact replays still go out.
- tvOS recovers in Settings rather than at a reset (TV has no reset).
  - **Notice:** a "Saves waiting" section appears while the account has an unresolved write or an unreadable record. It counts the titles and names the server and signed-in account. Now Playing says when the current title's newer listening waits.
  - **Step 1:** "Start server restart" calls `requestServerRestart` before the owner restarts.
  - **Step 2:** "The server has restarted" confirms and sends what waited. "Start again" takes a new snapshot. The step survives a relaunch.
  - **Refresh:** both views refresh on `PublicationLedger.changed`, which the ledger posts after every change, so the state never expires on its own.
  - **Reset:** `--reset-tv-state` clears the ledger, so journeys cannot inherit an earlier run's unanswered writes.
  - **Evidence:** the remote-driven `RecoveryJourney.testLaterListeningWaitsForARequestedAndConfirmedServerRestart` runs against the fixture's `held-sync` mode:
    - the first book-0 `local-all` gets a 504 while the fixture keeps its handler;
    - `/__fixture__/restart` ends kept handlers unapplied;
    - `/__fixture__/release-held` applies them.

    The journey checks that newer listening stays on the TV, that a manual resend does not send it, that the request survives a relaunch, and that after the fixture restart and the confirmation the session reaches the server once with both plays' listening.
    - RED: `b1ddd70e`, run on a fresh simulator, where the notice is missing.
    - Source: `d4d68b62`.
- Requests sent by builds before the ledger left no record, so they cannot hold back a reset.
- tvOS keeps the same rule with the ledger in Application Support, next to the intents, which the system may purge. TV has no reset, so the ledger only gates resets on the device that sent the writes, and a ledger write that fails stops TV listening from being sent until it succeeds, shown through the existing progress recovery.
- Simulator and fixture evidence only. No live server, physical device or cross-device acceptance is claimed, and the reset was never run against the owner's server.

## Verification

`apple/NativeTests/ProgressResetTests.swift` drives the production player, journal, reading store and adoption against the in-process stub. The stub models 2.30 rows, lookup, delete, `local-all`, and a PATCH that recreates a deleted row with a new ID. A relaunch is `AdoptionHarness.openStores()`, which builds new stores from disk. No port is bound.

### Correction for the cumulative-history and restart-cutoff reviews

- **Stub additions:**
  - session rows that `local-all` replaces by ID, recording any lowered total;
  - a progress step run against the row as loaded at request start;
  - holds filtered by item;
  - `restart()`, which ends held handlers unapplied.

  Tests drive the production `ListeningSync` directly, and `ApplePlayback.listening` is internal for this.
- **RED** (`bccdcbeb`, with an unrecorded `requestServerRestart` seam; `/tmp/pubsafe-red2-committed.log`): 20 tests, 9 failures, all in the three new tests:
  - `testASyncThatGotNoAnswerCannotReplaceLaterListeningOfItsSession`: the held first sync replaced the session's accepted 90 s with 30 s.
  - `testCarriedOverListeningThatGotNoAnswerCannotRewindLaterListening`: the held carried-over send rewound a later position from 12 s to 150 s.
  - `testARestartConfirmationDoesNotSettleWritesSentAfterTheRestart`: a retry issued after the restart but before the confirmation was resolved by it, and recreated the row after the reset.
- **Fix** `5179aeec`: the send gate, per-transmission outcomes, and two-phase restart. `testAReopenedPositionSurvivesAFailedUpdateAndALostResponseButNotNewerListening` now expects the position after a lost un-finish PATCH to wait until a confirmed restart, instead of following the possibly running PATCH.
- **`b1ad57ab`:**
  - the waiting notice;
  - `ListeningSync.publicationsFile` removed by `--reset-preview-account` (debug simulator only);
  - tests that fail against the mutants that stop the flush at a waiting title, or send through an unreadable record.
- **RED** `97574ac2` (`/tmp/pubsafe-red3-committed.log`): with later listening held back, or carried-over listening gated, the reset threw a generic busy or "still waiting" error that `BookDetails` offers no restart for.
- **Fix** `11ba8750`: the reset ordering in step 4.
- **`439c94e6`:**
  - a test where the reset's own sync gets no answer, which fails against rethrowing the timeout;
  - the teardown sends held-back listening, because `ListeningSync.file` is shared by all tests and runs. An aborted mutant run had left a session that failed later tests.
- **GREEN:** `NativeTests` 75/75 (`/tmp/pubsafe-full5.log`).
- **Mutations that failed a test** (the reset class, 20 to 25 tests):
  - no send gate;
  - no exact repeat allowed;
  - confirmation resolving every write;
  - any outcome resolving;
  - transport errors reported as answers;
  - no restart mark;
  - sends through an unreadable record;
  - a flush stopping at a waiting title;
  - no intent-time recheck;
  - no conversion of a failed publish.
- **Survivors:**
  - The first and post-publish reset checks each cover for the other.
  - Adoption treating a waiting `/sync` as sent (`notSent`) has no test.
  - A behavioral RED for 401 resends is not possible against 2.30: auth middleware answers a 401 before any handler runs, so the first transmission is always settled. Each transmission now has its own record.
- **Builds:**
  - the app;
  - TV;
  - `tvos/Core` 63/63;
  - the iOS 14 typecheck;
  - `generate.py --check`.

### Correction for the publication-ordering review

- **Stub:** a held write is answered with a client timeout (`URLError.timedOut`) while its handler keeps running on its own thread, waiting before its progress lookup until the test releases it. It then applies as 2.30 does: it updates the row, or creates one under a new ID. No 25-second wait. The handler is never killed early.
- **RED** (`971ccaa9`, run against `a1c92b03`'s sources plus a no-op `confirmServerRestarted` so the tests compile): 17 tests, 9 failures, all in the three new tests; the 14 existing ones passed (`/tmp/pubsafe-red-committed.log`):
  - `testListeningWhoseFirstSyncGotNoAnswerKeepsTheResetRefusedAfterItsReplayIsAccepted`: the reset ran after the replay was accepted, and the released first `local-all` recreated the row under a new ID. After a relaunch, the reset ran again; with the record unreadable, it ran again.
  - `testAPrimaryPDFPageWhosePublicationGotNoAnswerKeepsTheResetRefusedAfterItsReplayIsAccepted`: the reset ran, and the released first PATCH recreated the row at page 7.
  - `testCarriedOverListeningWhoseFirstSendGotNoAnswerKeepsTheResetRefusedAfterItsReplayIsAccepted`: the reset ran after the carried-over replay was accepted, and the released first send recreated the row at 400 s.
- **GREEN:** the 17 reset tests pass, and the full `NativeTests` passes 67/67 (`/tmp/pubsafe-full-final.log`).
- **Mutations** that each failed a test: no reset gate; a timeout counted as answered; an accepted replay resolving the media's earlier writes; no marker for an unreadable record; an unreadable record moved aside before its replacement was written; a restart confirmation that resolves nothing; adoption writes not recorded; reading published outside the ledger; a ledger kept only in memory.
- **Survivors:** a gateway status counted as answered, and `URLError.cancelled` counted as never sent. No test drives either. Mark finished goes through the ledger, and the "Has the server restarted?" alert in `BookDetails` was added; neither has a test.
- **Builds:** the `AudiobookshelfNative` app builds; the TV app builds for the tvOS simulator; `tvos/Core` passes 63/63; and every app-target source typechecks for `arm64-apple-ios14.0-simulator`. `generate.py --check` passes after the new strings. No server, device or owner data was used.

### Correction for the failure-order review

- **RED:** three regressions were written first and run against e3536adf's sources. The only change was an unused `progressResets:` init parameter so the harness compiles. 13 tests ran with 14 failures, all in the three new tests (`/tmp/playerfollow/durable-red-final.log`):
  - `testARefusedLocalCleanupKeepsTheResetPendingUntilItFinishes`: the reading document cannot be written after the delete. The stale download opened, and after writes were allowed the old page survived.
  - `testADeleteAppliedWithoutAnAnswerFinishesAfterRelaunch`: the server applies the delete but answers 500, then the app relaunches. The old page was PATCHed back and recreated the deleted row.
  - `testARejectedDeleteKeepsThisDevicesProgressUntilTheServerAcceptsIt`: the delete is rejected and nothing is applied. This device's reading is kept, but the confirmed reset never finished once the server accepted.
- **GREEN:** 14/14 in three runs. Full NativeTests passed 57/57, with and without the UI patch applied.
- **Mutations** that each failed a test:
  - no offline start gate
  - no reading sync gate
  - no durable intent
  - no finish on `restoreListening`
  - removing the intent before the cleanups
  - swallowing finish failures
  - no carried-over cleanup registration
- The mutation without the adoption send gate survived the first set. `testACarriedOverPositionWaitsForAnUnfinishedResetAndIsRetiredByIt` was then added; it fails against that mutant and passes with the implementation. It was written after the implementation.
- **Survivors:**
  - Keeping pages read after the confirmation (see Limits).
  - The pending-listening guard after `prepare`, as before.

### Earlier evidence (e3536adf)

The first eight tests failed against a stub (16 failures), and the two adoption tests failed before `prepareProgressReset` existed. Mutations of the flush, stop, start wait, reading cleanup, ownership pinning, adoption delivery and legacy retirement each failed a test, and still apply.

### Builds

The iOS 14 simulator typecheck of all app sources passed, with and without the UI patch. The TV simulator build passed, and `tvos/Core` builds; the only TV warning, `appWasSuspended`, predates this work. Builds used the Xcode 27 build-only iOS 15 override.

The project file is not committed. Run `xcodegen generate --spec apple/project.yml` to add the test file.

## Root production integration

The actual root app uses one `ProgressConfirmation` enum and one `.alert(item:)` for completion and discard. A button alert and a separate background alert both failed to present in the combined app; `/tmp/abs-root-reset-alert-red.log` and `/tmp/abs-root-reset-ui-green.log` record those failures. The latter filename is historical and is not a green claim.

All four iPhone reset journeys pass with the unified alert, `/tmp/abs-root-reset-unified-scoped-ui.log`, `apple/build-reset/ProgressReset-20261002-043629.xcresult`. They exercise cancel, confirmed book reset and playback from zero, episode isolation, and failed DELETE followed by retry. The failure assertion identifies the unfinished-reset message specifically. The shared fixture now implements the server's authorization response so an unrelated item-action error does not masquerade as reset failure.

NativeTests: 64/64 pass (`/tmp/abs-root-reset-native-tests.log`). Core: 63/63 pass (`/tmp/abs-root-reset-core.log`). iOS 14 source typecheck passes (`/tmp/abs-root-reset-minimum.log`). Durability correction `8a2401fe` cleared independent review. Hardware and owner-data acceptance remain open.

The same four reset journeys pass on iPad Pro 13-inch M4, iOS 27 (`/tmp/abs-root-reset-ipad-ui.log`, `apple/build-reset/ProgressReset-20261002-044036.xcresult`). The existing three completion-confirmation journeys also pass on the frozen integration `635767b6` (`/tmp/abs-root-finish-confirmation-ui.log`, `/Users/emanuel/code/audiobookshelf-finish-qa/apple/build/RootFinishConfirmation.xcresult`), including live listening cancellation, filtered-catalog removal and completion/reversal across relaunch.

Final recovery integration `56990f46` keeps discard-specific retry across foreground loads. Both final iPhone and iPad reset suites pass 4/4; details are in `APPLE-PROGRESS-RESET-QA.md`. The signed Release artifact was verified and installed on the owner’s paired iPhone and iPad without launching (`/tmp/abs-root-reset-final-device-build.log`, `/tmp/abs-root-reset-final-phone-install.log`, `/tmp/abs-root-reset-final-ipad-install.log`). Installation is confirmed, while interactive device acceptance remains open. PR #79 merged as `000ea3c8`.
