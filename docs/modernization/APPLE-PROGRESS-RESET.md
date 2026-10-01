# Discarding progress on Apple

The legacy app (`components/modals/ItemMoreMenuModal.vue:73`, `:368`) offers "Discard Progress" for a book or episode with progress. After a `HeaderConfirm` / `MessageConfirmDiscardProgress` confirmation, it removes the local progress and calls `DELETE /api/me/progress/:id`. The native app now has the same operation as one owned player call. The confirmed button is a separate root patch.

## Server 2.30 contract

These come from the 2.30 source; nothing was invented.

- `GET /api/me/progress/:libraryItemId/:episodeId?` returns the user's `MediaProgress` with its row `id`, or 404 when there is none.
- `DELETE /api/me/progress/:id` takes that row ID, removes it (`removeById`), answers 200 even for an unknown ID and emits `user_updated`.
- `POST /api/session/local-all` (`syncLocalSession`) updates progress unless the row's `updatedAt` is later than the session's, and creates a row when none exists. Listening that is still unsent at the delete will therefore bring the deleted progress back.
- The row holds the ebook location too, so a book reset also clears where reading resumes.

## Operation

`APIClient.resetProgress(itemID:episodeID:authorization:)` looks up the row and deletes it. Both requests are pinned to the sign-in that started the reset, and it returns `false` when the server held no progress.

`ApplePlayback.resetProgress(account:itemID:episodeID:prepare:discardLocal:)` is the shared operation. It compiles for TV because the mobile-only work arrives as closures. In order, it:

1. Refuses while another reset, a preparation, closing or seeking is in progress.
2. Checks the account and `authorizationRevision` before and after every await, so an A to B to A sign-in change cancels it.
3. Stops the media if it is open, and waits for any reading publication.
4. Flushes the listening journal. If listening for this media is still unacknowledged after `prepare`, nothing is deleted and the call throws.
5. Deletes the row.
6. Records a zero remote position dated now in the journal, so cached and older positions cannot win over the reset.
7. Runs `discardLocal`, then returns `GET /api/me` and remembers it.

Listening for other media stays queued. `start` and `startOffline` wait for a running reset, so playback started during a reset begins from the start. `canPublishReading` is false during the reset.

On iOS, `resetProgress(account:itemID:episodeID:reading:adoption:)` adds two steps:

- `NativeMigrationAdoption.prepareProgressReset` syncs carried-over legacy listening first. It then marks this media's unsent legacy positions as resolved, so a later adoption sync cannot PATCH them back. It throws if carried-over listening is still owed to the server.
- `ReadingStore.discardProgress` replaces the primary EPUB and PDF positions with an empty, non-pending location dated now. Readers open an empty location at the start, and its date outranks older server snapshots and pending pages. Supplementary documents keep their positions.

Files changed outside `ApplePlayback.swift`: `APIClient.swift` (the route), `ListeningSync.swift` (`forgetPosition`), `ReadingStore.swift` (`discardProgress`) and `AdoptionSync.swift` (`prepareProgressReset`).

## Root handoff

`APPLE-PROGRESS-RESET-UI.patch` (next to this file) is the root-owned UI. It applies cleanly to `origin/fork/native-tv` (6ac3f2ee). On the current `fork/apple-final-integration`, the source and `legacy-equivalents.json` hunks apply. The generated string tables and `COVERAGE.md` conflict there, so apply with `--exclude='apple/Localization/COVERAGE.md' --exclude='apple/Localization/Sources/*'` and run `python3 apple/Localization/generate.py`. The patch:

- `BookDetails`: a "Discard progress" button for a book or an individual episode whose `progress` or `ebookProgress` is above zero, as in the legacy `progressPercent > 0`. It confirms with an alert titled "Confirm", with the legacy message and a destructive "Discard progress" action. The alert sits on the button because iOS 14 shows only one `.alert` per view, and the view already has the finish confirmation. It uses `progressBusy`, cancels the detail request and shows errors through `ConnectionStore.recovery`. After success, the stale `progress` the view was opened with is no longer used as a fallback. This is independent of `clearProgressFailure`.
- `NativeMigrationStore.resetProgress`: passes its private `adopter` to the player operation.
- `CatalogStore.discardProgress`: applies the user and removes the reset book or episode from Continue Listening, which `applyProgress` keeps when progress is absent.
- Localization: maps "Discard progress", "Are you sure you want to reset your progress?" and "Confirm" to `MessageDiscardProgress`, `MessageConfirmDiscardProgress` and `HeaderConfirm`, with regenerated tables.

Root also owns realtime: the server's `user_updated` after the delete reaches other clients through the existing stream.

## Limits

- The server keeps no tombstone. A legacy import run after the reset adopts that backup's positions again, as a fresh import would. Another device's unsent listening can recreate the row through `local-all`, as it would in the legacy app.
- Downloaded entries keep their `serverPosition` snapshot. The journal's dated zero position outranks it on the next offline start.
- Simulator and fixture evidence only. No live server, physical device or cross-device acceptance is claimed, and the reset was never run against the owner's server.

## Verification

`apple/NativeTests/ProgressResetTests.swift` drives the production player, journal, reading store and adoption against the in-process stub. The stub models 2.30 rows, lookup, delete and `local-all`. No port is bound.

- **RED:** the first eight tests were written against a stub `resetProgress` and failed (8 tests, 16 failures, `/tmp/playerfollow/reset-red.log`). The two adoption tests were added for the imported-position requirement and failed before `prepareProgressReset` existed (4 failures).
- **GREEN:** 10/10 in three runs. Full NativeTests 53/53 (34 existing, 9 follow, 10 reset), with and without the UI patch applied.
- **Mutations** that each failed a test:
  - no flush
  - no journal forget
  - no stop
  - no start wait
  - no reading discard
  - no ownership check with unpinned requests (the ABA test)
  - no adoption delivery
  - no legacy position retirement
- The legacy position test first survived that last mutation, because the stub's server row already superseded the legacy position. It now makes the PATCH fail during the reset and succeed afterwards, and fails without the retirement.
- One mutation survives: removing the guard that checks for unacknowledged listening after `prepare`. It is defense in depth, because a successful flush leaves nothing pending in these fixtures.
- The iOS 14 simulator typecheck of all app sources passed, with and without the patch. The TV simulator build passed; its only warning, `appWasSuspended`, predates this work. Builds used the Xcode 27 build-only iOS 15 override.

The project file is not committed. Run `xcodegen generate --spec apple/project.yml` to add the new test file.
