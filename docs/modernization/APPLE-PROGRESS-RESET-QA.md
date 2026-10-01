# Discard progress journeys on iPhone and iPad

These journeys check the confirmed "Discard progress" action from book and episode details. The legacy action is `components/modals/ItemMoreMenuModal.vue:73`, `:368`. The production reset and its UI belong to the player worker (`APPLE-PROGRESS-RESET.md`, `APPLE-PROGRESS-RESET-UI.patch`). This branch adds only the test, the fixture, the runner and this evidence.

## Fixture

`apple/scripts/progress_reset_fixture.py` wraps `verification/fixture.py` and follows the 2.30 MeController routes:

- `GET /api/me/progress/:libraryItemId/:episodeId?` returns the row with its `id`, or 404.
- `DELETE /api/me/progress/:id` deletes by row id and answers 200, also for an unknown id. An item path such as `/api/me/progress/podcast/episode` is not a row id and gets 404.
- `POST /api/items/:id/play[/:episodeId]` starts at 0 when no row exists, as the server does. The base fixture would otherwise start at 6.

`POST /__reset__/configure` seeds rows for the synthetic qa user only: `book-0`, `book-1`, `podcast/episode` and `podcast/episode-morning`, each at 6 of 20 seconds. Each newly seeded row gets a fresh `uuid4` id and a current timestamp, matching the server’s newly created progress rows. `{"fail": "delete"}` makes the next DELETE answer 500 once. `GET /__reset__/observations` returns the progress requests, the deleted rows, the remaining rows and the play sessions served. `apple/scripts/test_progress_reset_fixture.py` checks these semantics (6 tests), including a late DELETE of an old row leaving newly created progress intact.

## Journeys

`apple/UITests/ProgressResetJourney.swift`, run only when `ABS_PROGRESS_RESET_QA=1`. Each test first waits for the seeded "6 sec listened · 30% complete" in the details. It then requires `discard-progress`; when the button is missing it fails with "No discard-progress action in these details: the progress reset UI (docs/modernization/APPLE-PROGRESS-RESET-UI.patch) is not in this build." and stops.

| Test | Checks |
| --- | --- |
| `testCancellingTheConfirmationKeepsProgressAndSendsNoDelete` | The "Confirm" alert shows the legacy message. Cancel sends no DELETE, and the row, the progress text, "Resume listening" and the action remain. |
| `testAConfirmedBookResetRemovesItsProgressAndPlaysFromTheStart` | Confirming deletes only `book-0`. The progress text and the action disappear, and the button reads "Start listening". The play session starts at 0 and the player shows under 6 seconds elapsed. Back in the library, `continue-book-0` is gone while `continue-book-1` stays. |
| `testAConfirmedEpisodeResetRemovesOnlyThatEpisodesProgress` | From the podcast library, resetting "A Quiet Evening" deletes only `podcast/episode`, and the button reads "Start episode". `book-0`, `book-1` and `episode-morning` keep their rows, and "The Morning After" still shows its progress and the action. |
| `testAFailedResetIsReportedAndDiscardingAgainSucceeds` | A 500 on DELETE shows the recovery card and keeps the progress, the row and "Resume listening". Tapping the visible "Try again" recovery button sends a second DELETE, removes `book-0` and clears the card. |

## Running

```sh
apple/scripts/verify-progress-reset.sh
```

The runner:

- refuses to start when 127.0.0.1:27765 is in use;
- runs the fixture unit tests, then starts the fixture and stops it by its own PID;
- uses the simulator "Audiobookshelf ResetQA", created on first use (here `36DFD842-5589-4837-B0EC-CCC4E0559C1A`, iPhone 17 Pro, iOS 27.0);
- builds into the ignored `apple/build-reset` and restores `project.pbxproj` on exit.

It runs whatever app the checkout contains and applies no patch.

## Evidence

All runs are local simulator runs against the synthetic fixture. No owner data or server was used.

- **RED on 8c1e94a5, as is:** 4 tests, 4 failures (`ProgressResetJourney.swift:36`). In each test, the only failure was the missing-action message above. The seeded progress was visible before it, so the action was missing rather than still loading. Fixture tests: 5/5.
- **Diagnostic on uncorrected e3536adf (not a pass claim):** in a throwaway worktree, I built 8c1e94a5 with e3536adf cherry-picked. I applied `APPLE-PROGRESS-RESET-UI.patch` with `git apply -3` and the localization excludes, then ran `generate.py`. The result was 4 tests, 4 failures. `discard-progress` existed, was hittable and was tapped, but no "Confirm" alert appeared within 5 seconds (`:41`). The patch puts the discard alert on the button, inside the view whose `.alert` holds the finish confirmation. On iOS 27 that nested alert never presents.
- **Same diagnostic, alert moved:** with only that alert moved to `.background(Color.clear.alert(isPresented: $confirmDiscard) { … })` beside the finish alert, 4/4 passed. This shows the journeys exercise the reset end to end. It is not GREEN evidence for production, because the player worker is still correcting e3536adf and the moved alert is not in any patch.

## Root integration

After applying the corrected player commits and a UI patch whose discard alert presents (see the diagnostic above):

```sh
git cherry-pick <fork/apple-reset-qa commit>
git apply -3 --exclude='apple/Localization/COVERAGE.md' --exclude='apple/Localization/Sources/*' docs/modernization/APPLE-PROGRESS-RESET-UI.patch
python3 apple/Localization/generate.py
apple/scripts/verify-progress-reset.sh
```

The patch does not apply to 8c1e94a5 without `-3`, because `BookDetails.swift` has moved since 6ac3f2ee. With `-3` it applies cleanly. To use a different simulator, set `ABS_RESET_QA_SIMULATOR`; do not use the root QA devices or ports 19765 to 19769.

## Final recovery correction

The earlier integrated phone and iPad runs passed 4/4, but retried through the discard action. Strengthening the failed-reset journey to tap the visible "Try again" button produced RED: it reloaded details, sent no second DELETE and left the failed reset pending (`/tmp/abs-root-reset-recovery-red.log`). `BookDetails` now retains the failure operation so this button retries the durable reset.

A subsequent full run passed the retry journey and two others, but the first book journey exposed fixture ID reuse after a pending reset survived relaunch. The fixture contract regression failed before the correction: reseeding produced the same row ID. Fresh UUIDv4 rows prevent a delayed reset of the original row from deleting a newly created row. All six fixture tests pass after that correction. This fixes the fixture rather than clearing the application's durable journal to hide the mismatch.

Independent review then found that a foreground refresh could erase the discard-specific error. The strengthened journey backgrounds and activates the app, observes a new detail GET, and requires the pending-reset recovery to remain before tapping "Try again". It failed before the correction (`/tmp/abs-root-reset-foreground-red.log`): the error and recovery button disappeared. Unrelated detail and download refreshes now change only load failures; a discard failure remains until retry completes.

The final four iPhone journeys pass with both recovery corrections and fresh fixture row IDs: `/tmp/abs-root-reset-foreground-green-phone.log`, `apple/build-reset/ProgressReset-20261002-050144.xcresult`. Independent review cleared the updated failure dispatch and foreground preservation. The iOS 14 source typecheck and signed internal build also pass (`/tmp/abs-root-reset-foreground-minimum.log`, `/tmp/abs-root-reset-final-device-build.log`).

The same final four journeys pass on the actual iPad Pro 13-inch M4 simulator, iOS 27, in a separate frozen worktree with fixture port 49765: `/tmp/abs-root-reset-foreground-green-ipad.log`, `/Users/emanuel/code/audiobookshelf-reset-final-tablet/apple/build-reset/ProgressReset-20261002-050316.xcresult`. The source matches the final production correction; the only journey difference is the isolated fixture port. This is simulator evidence, not physical acceptance.
