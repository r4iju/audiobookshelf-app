# Discarding progress on Apple

The legacy app (`components/modals/ItemMoreMenuModal.vue:73`, `:368`) offers "Discard Progress" for a book or episode with progress. After a `HeaderConfirm` / `MessageConfirmDiscardProgress` confirmation, it removes the local progress and calls `DELETE /api/me/progress/:id`. The native app now has the same operation as one owned player call. The confirmed button is a separate root patch.

## Server 2.30 contract

These come from the 2.30 source; nothing was invented.

- `GET /api/me/progress/:libraryItemId/:episodeId?` returns the user's `MediaProgress` with its row `id`, or 404 when there is none.
- `DELETE /api/me/progress/:id` takes that row ID, removes it (`removeById`), answers 200 even for an unknown ID and emits `user_updated`.
- `POST /api/session/local-all` (`syncLocalSession`) updates progress unless the row's `updatedAt` is later than the session's, and creates a row when none exists. Listening that is still unsent at the delete will therefore bring the deleted progress back.
- The row holds the ebook location too, so a book reset also clears where reading resumes.

## Operation

`APIClient.progressRowID(itemID:episodeID:authorization:)` looks up the row, and `APIClient.deleteProgress(rowID:authorization:)` deletes it. Both are pinned to the sign-in that started the reset. Server 2.30 creates progress with a fresh `UUIDV4` row ID (`MediaProgress.init`, `createUpdateMediaProgressFromPayload`). Deleting a recorded row ID again therefore never removes progress recreated later, and it answers 200 once the row is gone.

`ApplePlayback.resetProgress(account:itemID:episodeID:prepare:)` is the shared operation. It compiles for TV because the mobile-only work arrives through a `prepare` closure and registered cleanups. In order, it:

1. Refuses while another reset, a preparation, closing or seeking is in progress.
2. Checks the account and `authorizationRevision` before and after every await, so an A to B to A sign-in change cancels it.
3. Stops the media if it is open, and waits for any reading publication.
4. Flushes the listening journal and runs `prepare`. If listening for this media is still unacknowledged, nothing has changed and the call throws.
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

## Root handoff

`APPLE-PROGRESS-RESET-UI.patch` (next to this file) is the root-owned UI. It needs this branch's core change. It applies cleanly to `origin/fork/native-tv` (6ac3f2ee), and with `git apply -3` to `fork/apple-final-integration` at 315183c1. On the integration branch, leave out the generated string tables and `COVERAGE.md` (`--exclude='apple/Localization/COVERAGE.md' --exclude='apple/Localization/Sources/*'`), then run `python3 apple/Localization/generate.py`. The patch:

- `BookDetails`: a "Discard progress" button for a book or an individual episode whose `progress` or `ebookProgress` is above zero, as in the legacy `progressPercent > 0`. It confirms with an alert titled "Confirm", with the legacy message and a destructive "Discard progress" action. The alert sits on the button because iOS 14 shows only one `.alert` per view, and the view already has the finish confirmation. It uses `progressBusy`, cancels the detail request and shows errors through `ConnectionStore.recovery`. After success, the stale `progress` the view was opened with is no longer used as a fallback. This is independent of `clearProgressFailure`.
- `NativeMigrationStore.resetProgress`: passes its private `adopter` to the player operation. Reading cleanup is registered by `ReadingStore`, so the UI passes no store. A thrown "has not finished" error is shown through `ConnectionStore.recovery`, and confirming again finishes the saved reset.
- `CatalogStore.discardProgress`: applies the user and removes the reset book or episode from Continue Listening, which `applyProgress` keeps when progress is absent.
- Localization: maps "Discard progress", "Are you sure you want to reset your progress?" and "Confirm" to `MessageDiscardProgress`, `MessageConfirmDiscardProgress` and `HeaderConfirm`, with regenerated tables.

Root also owns realtime: the server's `user_updated` after the delete reaches other clients through the existing stream.

## Limits

- The server keeps no tombstone. A legacy import run after the reset adopts that backup's positions again, as a fresh import would. Another device's unsent listening can recreate the row through `local-all`, as it would in the legacy app.
- A pending intent waits for its account. Signed in as someone else, it stays on disk and holds back only that account's media.
- An unreadable intent file counts as pending for every media: playback refuses, and reading and carried-over positions wait, rather than risking a recreated row.
- Pages read after the confirmation while the reset is pending are kept and published once it finishes. No test distinguishes this rule; see the mutation results.
- Simulator and fixture evidence only. No live server, physical device or cross-device acceptance is claimed, and the reset was never run against the owner's server.

## Verification

`apple/NativeTests/ProgressResetTests.swift` drives the production player, journal, reading store and adoption against the in-process stub. The stub models 2.30 rows, lookup, delete, `local-all`, and a PATCH that recreates a deleted row with a new ID. A relaunch is `AdoptionHarness.openStores()`, which builds new stores from disk. No port is bound.

### Correction for the failure-order review (this commit)

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
