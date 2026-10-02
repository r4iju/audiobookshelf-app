# Apple remaining mobile QA

Local, simulator-only checks for the remaining computable iPhone and iPad gaps in story 22 (collections and playlists),
stories 42 and 43 (download recovery and storage) and story 53 (contrast and reduced motion). Branch
`fork/apple-remaining-local-qa` from `000ea3c8` (`origin/fork/native-tv`). Synthetic fixture data only. No owner
server, account or device was used, and nothing here is hardware or live-server acceptance.

## How to run

- Simulators: "ABS Remaining QA iPhone" (iPhone 17, iOS 27) and "ABS Remaining QA iPad" (iPad Air 13-inch M4, iOS 27),
  created with `xcrun simctl create`.
- `apple/scripts/verify-remaining-qa.sh [xcodebuild args]` runs the `RemainingQA*` UI journeys. It owns ports 57765
  (realtime proxy) and 57769 (HTTP fixture) and refuses to start if either is in use. It builds a generated, ignored
  copy of `project.yml` into `apple/build-remaining-qa`. Set `ABS_REMAINING_QA_SIMULATOR` to pick the iPad.
- `apple/scripts/verify-download-storage.sh [xcodebuild args]` runs the hostless `NativeTests` (default:
  `DownloadStorageTests`). It first mounts an 8 MB HFS+ image at `apple/build-remaining-qa/full-volume` and passes its
  path as `ABS_FULL_VOLUME`, so a transfer meets a full volume. It detaches the image on exit.
- `apple/scripts/measure-contrast.swift <png> <scale> <x> <y> <w> <h>` measures one element in a screenshot with the same
  method the audit uses.

## Contrast (story 53)

`RemainingQAAccessibilityJourney` runs XCUITest's contrast audit in light, dark and black on these screens: catalog,
book details, PDF reader, player, Downloads, Collections, a collection and Settings.

An issue stays a failure unless one of these holds:

- The screenshot taken just before the audit measures the element at 4.5:1 or more (WCAG 1.4.3).
- The element is disabled (WCAG 1.4.3 exempts inactive controls).

Every dismissal is printed with its measurement.

RED (`5a8a9a5b`, iPhone): 38 findings in light and 2 each in dark and black. Measured examples:

| Element | Colours | Ratio |
| --- | --- | --- |
| System secondary label | `#85858B` on `#F2F2F7` | 3.29:1 |
| System secondary label | `#8A8A8E` on white | 3.44:1 |
| Accent | `#CC4F2B` on `#F2F2F7` | 3.99:1 |
| White on the accent ("Resume listening") | | 4.45:1 |
| Dark accent on a card ("Play collection") | | 3.82:1 |
| System blue in the PDF reader and the iPad player | | 3.15:1 |

The blue appears because sheets and full screen covers do not inherit `.accentColor`.

GREEN (`30a66e60`):

- The accent is now the asset catalog's global accent: `#B5451F` in light, `#F07A54` in dark.
- White text sits on `#B5451F` in every appearance.
- Secondary text and section headers are `#6B6B70` in light and the system secondary label in dark.

On the final run, both iPhone and iPad passed with 0 findings in all three appearances.

Remaining dismissals, all evidenced:

- Liquid Glass toolbar buttons, measured 11.35 to 19.7:1.
- "Go to page", which stays disabled until a page number is typed.

**Not covered:**

- Screens outside the list above: for example the RSS sheet's orange footnotes, red error text and the migration import screen.
- A VoiceOver walkthrough.

## Reduced motion (story 53)

Searched at this branch's head, outside the deferred EPUB reader assets:

- No `withAnimation`, `.animation`, `.transition`, `matchedGeometryEffect`, `repeatForever`, phase or keyframe
  animators, symbol effects, `UIView.animate`, Core Animation or reduce-motion checks.
- The only `animated: true` is the system alert in `AppleNetworkPolicy`.
- PDF page changes use PDFKit's `go(to:)`.

Motion therefore comes only from system navigation, sheets and progress indicators, which follow Reduce Motion
themselves. This is a source observation. No journey toggles Reduce Motion, and it has not been checked on a device.

## Collections and playlists (story 22)

Every case was probed on iPhone against the fixture before any change. The probe source, its fixture patch, logs and
results are kept with the evidence. Only the failing case became a committed test.

**Permission denial: confirmed bug.**

- Symptom: when the server answers 403, the editor said "Changes could not be completed. Some membership changes may
  already be saved. The server returned HTTP 403. Please try again."
- Why it was wrong: nothing had been saved, and a retry cannot succeed.
- RED: `9768ad9e`. GREEN: `3546707d`.
- Fix: the save now reports a partial save only when a membership request had succeeded before the failure.
- Message now: a 403 on save or delete reads "Your account is not allowed to do this on the server."
- With these changes, the partial-failure and collection-editing probes still pass.

**Probes that passed on unchanged code** (documented, not committed as tests):

- **Read-only account:** with `update: false`, New collection, Edit collection and Delete collection are absent.
- **Partial membership failure and retry** (`group-partial-failure`, which fails the first PATCH with 503 after
  `batch/add` and `batch/remove` succeed):
  - The editor stays open and says some membership changes may already be saved.
  - The server holds the saved membership.
  - Saving again re-reads the server, adds nothing twice (one `batch/add` in total), applies the order and closes the
    editor.
- **Collection editing:** create, rename, change the description, reorder, add two titles and remove one. The server
  holds the result, and after a relaunch the collection shows it in the same order.
- **Unavailable members:**
  - A collection that starts with an `isMissing` title with no audio lists it. The probe fixture also put one first in a
    playlist, but only the collection was exercised.
  - Play skips it and starts the next playable member: `POST /api/items/book-2/play`.
  - No session is requested for the missing title.
- **Podcast playlist membership editing:**
  - In the podcast library's playlist, the app adds a second episode through the episode picker, moves it first and
    later removes the original.
  - The server holds `podcast:episode, podcast:episode-morning`, then `podcast:episode`.
  - The committed fixture cannot express this. It checks members against books only, drops `episodeId` and removes
    by item. The probe used a fixture patch that matches episodes by `libraryItemId` and `episodeId`, as the server
    does. The patch was not committed because no committed test needs it.

**Admin without delete permission: confirmed bug.** Checked against the server 2.30.0 source read locally, with no
request to any server:

- `CollectionController.middleware` refuses a `DELETE` of a collection unless `req.user.canDelete`, and a `PATCH` or
  `POST` unless `req.user.canUpdate`.
- Those getters read only `permissions.delete` and `permissions.update` (and `isActive`). The user type is not
  consulted.
- `User.getDefaultPermissionsForUserType` gives an admin `update: true` and `delete: false`; only root defaults to
  `delete: true`. Permissions are stored per user and an admin can change them.
- `PlaylistController.middleware` allows only the playlist's owner, so playlists are unaffected.

The app also allowed both actions to any admin (`canManagePodcasts`), so a default admin was offered Delete collection
and then refused with 403. RED: `9cc81daf`, in the fixture's `podcast-admin` mode (admin, `delete: false`).
GREEN: `2d0154c8`, where collection edit and delete follow `permissions.update` and `permissions.delete` alone.

**Still open:** `CollectionJourney.testCreateReorderRemoveAndDeletePlaylistThroughRelaunch` was not rerun. It uses the
coordinator's fixture ports.

## Downloads (stories 42 and 43)

**Insufficient storage: confirmed bug.**

- Setup: the full-volume test fills the mounted volume while a transfer is held open.
- Symptom: the staging move and the manifest write both failed, the entry stayed queued in memory, and every
  completion started the same part again: 245 transfers in about four seconds, with no message.
- RED: `33eb9455`. GREEN: `3efb624c`.
- Fix: a failed part leaves the queue in memory even when the manifest cannot record it. The entry fails once with
  "There is not enough storage on this device for this download. Free up space, then retry." After the space is
  freed, Retry completes with the original bytes.
- After review, URL file-write and file-creation errors count as storage only with an underlying `ENOSPC`, `EDQUOT` or
  Cocoa out-of-space cause. RED: `63ed02cf`, an `EACCES` cause. GREEN: `553fd012`. The real full-volume test still
  passes.

**PDF added after the audio: confirmed bug.**

- Trigger: when the server item gains a PDF after its audio was downloaded, "Download for offline" queues the ready
  entry again for the PDF alone.
- Symptom: if that transfer failed, offline audio refused the finished, intact audio files with `signInRequired`,
  before and after a relaunch.
- RED: `02bbb418`. GREEN: `b405a805`.
- Fix:
  - Offline audio needs every audio part saved, and offline reading needs the ebook part.
  - Downloads shows Play offline beside Retry download.
  - A group plays such a member offline.
- Primary and supplementary entries keep their meaning: a supplementary entry has no audio parts.

**Lost connection mid-transfer** (probe, passed on unchanged code):

- One part failing with `networkConnectionLost` fails the entry and cancels its other running part.
- Retry fetches the unfinished parts and the entry becomes ready.
- Through the in-process stub the stored message was the generic `NSURLErrorDomain error -1005` text. A real session's
  wording was not observed.

**Unsized transfer shorter than the listed size: confirmed bug.**

- Server 2.30 contract:
  - Track lists are clones of the AudioFile, so every track and podcast episode `audioTrack` carries
    `metadata.size`. Ebook files carry it too.
  - `downloadLibraryFile` serves the file with `res.download`, which sends its Content-Length. A reverse proxy that
    streams the body can drop that header (or use `X-Accel-Redirect`), so an unknown length is legitimate.
- Symptom: with no Content-Length, half of the audio file and 100 bytes of the PDF were saved as finished and the entry
  became ready.
- RED: `7e21dbc2`. GREEN: `a39281f1`.
- Fix:
  - `TrackMetadata` keeps the optional listed `size`.
  - When the response has no Content-Length and the server listed a size, the body must match it.
  - With neither a Content-Length nor a listed size, the transfer is accepted as before.
  - Migrated entries list no size and are unchanged.
- The same test checks the unknown-length case still becomes ready.
- Wrong media with an HTML or JSON type was already refused by the MIME check (`OfflineJourney`).

**Background transfer across a kill and relaunch** (ephemeral probe, passed on unchanged code):

- Setup:
  - A temporary `slow-download` fixture mode streamed each track of `book-1` over about 20 seconds, with
    Content-Length, through the 57765 proxy. It logged whether each stream finished or was aborted.
  - A temporary journey started "Download for offline" and waited until both parts were requested.
  - It then killed the app with `XCUIApplication.terminate()`, once from the foreground and once after pressing Home.
  - It waited 35 seconds and launched the app again.
- Results, the same in both runs:
  - Each part was requested exactly once.
  - The fixture finished streaming both parts about 13 seconds after the kill, while the app was not running.
  - After the relaunch, Downloads showed `book-1` as Available offline without any new request.
- Conclusion: `nsurlsessiond` continued the transfer, and the relaunched store adopted the result.
- Limits: the probe cannot tell whether the files were delivered by a background relaunch through
  `handleEventsForBackgroundURLSession` or by the user relaunch. `terminate()` is a system kill, not a user
  force-quit from the app switcher, which iOS documents as cancelling background transfers.
- The probe source, fixture patch, logs, fixture log and screenshots are kept with the evidence. Neither the probe nor
  the patch is committed.

`NativeTests` result: 68 of 68 at `a39281f1`.

**Still open:**

- **Background transfers:**
  - Behaviour after a user force-quit, and on a device, is unverified.
  - A device restart and real cellular transitions are untested.
- **Storage limits:**
  - A whole-device full condition, where the system cannot even stage the transfer, was not reproduced. Only the
    app's own volume was full.
  - A body cut short with neither a Content-Length nor a listed size still cannot be detected.
- **Missing files** (from the source, not run):
  - A downloaded ebook removed while the app runs is only detected at the next launch.
  - A missing entry folder makes Retry fail, because only enqueue creates it. Neither has a realistic trigger: the
    folder lives in Application Support and is excluded from backup.

## Evidence

All under `/tmp/abs-remaining-qa-evidence`:

- **`contrast-red/`:** RED logs. `light.xcresult` holds the light run.
- **`contrast-green/`:** iPhone and iPad logs, results and exported screenshots.
- **`groups/`:**
  - The probe source `RemainingQAGroupJourney-probes.swift` and its `fixture-probe-modes.patch`.
  - Probe logs and results: `probe-1`, `probe-podcast`, `forbidden-red`, `forbidden-green-with-probes`.
- **`downloads/`:**
  - `storage-red`, `storage-green`, `pdf-added-red`, `write-failure-red` and `interruption-probe`.
  - `NativeTests` runs: 65, 66 and 67 tests.
- **`final/`:**
  - iPhone and iPad runs of the three contrast audits and the forbidden-edit journey, with exported screenshots.
  - These ran at `b405a805`. `553fd012` changes only the storage classification, which the 67-test run covers.
- **`round2/`:**
  - `truncation-red` and `admin-delete-red`.
  - `nativetests-68` and `groups-green` (iPhone only; the admin journey was not run on iPad).
  - `background-probe/`: the probe source, `slow-download-fixture.patch`, `probe.log`, `fixture-http.log`, the
    result bundle and screenshots.

## Integrated verification, 2026-10-02

Source `23abaa51`, on top of merged realtime integration `39609d08`, passes:

- NativeTests: 70 of 70, zero skipped, including the owned 8 MiB full-volume case. Result: `apple/build-remaining-qa/results/storage-Audiobookshelf-Root-Related-QA-20261002-063820.xcresult`; log `/tmp/abs-root-polish-final-native-tests.log`.
- Core: 72 of 72; log `/tmp/abs-root-polish-final-core.log`.
- Default remaining-QA UI invocation: all three light/dark/black contrast audits and both collection-permission journeys, 5 of 5. Result: `apple/build-remaining-qa/results/Audiobookshelf-Root-Related-QA-20261002-064337.xcresult`; log `/tmp/abs-root-polish-final-ui.log`.
- Synthetic fixture tests: 10 passed; log `/tmp/abs-root-polish-fixture-tests.log`.
- iOS 14 source typecheck, localization generation check, project generation and diff check passed. Runtime compatibility on iOS 14 remains unverified.

The earlier integrated light-theme run failed while opening the player because the synthetic realtime proxy returned HTTP 503. A separate RED experiment suspended only the owned fixture and queued 40 connections: the previous five-connection listen queue rejected 35 connections. The fixture factory now queues 128 connections; the final default UI invocation passed all five cases. This changes synthetic fixture capacity, not production retry or error handling.

The runner previously selected a base journey class containing no test methods. Its default now selects both concrete journey classes; the final invocation used those defaults. The root run used owned temporary ports 64765/64769, restored to the documented defaults afterward.

These results cover local synthetic simulators. They do not establish owner-device acceptance, whole-device storage exhaustion, iOS 14 runtime compatibility, or user force-quit background-transfer behavior. The metadata truncation test proves the audio rejection path; its sibling PDF is cancelled by that audio failure, so it is not an independent PDF-size rejection proof.
