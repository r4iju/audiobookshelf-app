# Apple year-review image export

A native composer that turns one immutable annual snapshot into shareable images and a text summary,
generated entirely on the device. It lives in `apple/Export` and never calls the API itself: the app
loads stats and cover bytes and hands it a snapshot. `apple/App/YearReviewView.swift` does that loading.

## Legacy source and parity

The primary sources are the mobile canvases in `components/stats/` and the Audiobookshelf 2.30.0 server
(`server/utils/queries/userStats.js`, `adminStats.js`, `StatsController.middleware`).

| Legacy canvas | Native design | Notes |
| --- | --- | --- |
| `YearInReview.vue` variant 0 (stat boxes, top narrator/genre/author/month) | Highlights | Square and portrait. Portrait adds the longest finished book, which the endpoint already returns. |
| `YearInReview.vue` variant 1 (finished-book covers) | Finished | Square and portrait. Up to 5 `finishedBooksWithCovers`, center-cropped squares, under "Some books finished this year". Offered only when at least one finished cover loaded. |
| `YearInReview.vue` variant 2 (top authors and genres lists) | Top Lists | Square and portrait. Hidden when both lists are empty. |
| `YearInReviewShort.vue` (books finished/listened banner) | Compact | 3:1 banner, like the 600×200 original. |
| `YearInReview.vue` cover mosaic background | All listener designs | 5×5-style wall of finished then other covers, rotated -25° at 25% opacity under a scrim. Falls back to the gradient when no cover loaded. |
| `YearInReviewServer.vue` variant 0 (additions with covers) | Additions | Admin and root only. Books added, authors added, sessions, collection size and duration with this year's growth, up to 5 `booksAddedWithCovers`. Without covers it shows the library book count instead. |
| `YearInReviewServer.vue` variant 1 (top authors, top narrators) | People | Names only, as in the legacy canvas. Hidden when both lists are empty. |
| `YearInReviewServer.vue` variant 2 (top authors, top genres) | Genres | Names only. Hidden when there are no genres, so it never duplicates People. |

The server canvases share the server cover mosaic background. Sizes use binary units like `$bytesPretty`;
durations use days, hours and minutes like `$elapsedPrettyExtended`.
File names keep the legacy `audiobookshelf_my_<year>.png` / `_short.png` and `audiobookshelf_server_<year>.png`
schemes, plus `_finished`, `_top`, `_people`, `_genres` and `_story` suffixes.

## Contract

- `YearExportSnapshot(stats:year:artwork:locale:)` copies the values once and fails for years outside `2000...9999`
  (the same range `APIClient.yearListeningStats` accepts). Each snapshot has a fresh `id`.
- `YearExportComposer(snapshot:)` keys all of its state to `snapshot.id`. Passing a different snapshot
  rebuilds the composer, so a preview or share item from another year or account cannot survive.
  `YearExportSheet(snapshot:onDone:)` wraps it for modal presentation.
- `YearExportRenderer.render(_:layout:)` is a pure function from snapshot and layout to PNG bytes, the file name,
  the share text and an accessibility label. It uses `UIGraphicsImageRenderer` and Core Graphics, not SwiftUI
  `ImageRenderer` (iOS 16). Every API it uses is available on iOS 14.
- Sharing always re-renders when the cached preview is for another layout. It shares a PNG file plus the
  text summary through `UIActivityViewController`, anchored to the button for the iPad popover.
- Temporary file lifetime: each share writes into its own folder with complete file protection, owned by a
  `YearExportShareFile`. The folder is deleted in these cases:
  - Failed write: deleted at once, and the share falls back to an in-memory image.
  - Completion (shared, cancelled or dismissed): deleted by the completion handler, after the consumer has finished.
  - Share sheet released without a completion (for example parent teardown): deleted when the last holder lets go.
    The holders are the pending request in composer state and the share sheet's completion closure, so the file is
    never removed while the sheet can still hand it out.
  - Presentation: deferred out of the SwiftUI update. It is skipped if the request was superseded or the presenter
    was released. It fails, releasing the file, if the composer is detached from a window or already presenting.
  - Not covered: a process kill leaves the folder for the system's temporary-directory purge.
- Zero statistics render as zeros with a "No listening recorded" panel. Long names truncate with an
  ellipsis, and large numbers shrink to fit and then truncate. Durations are formatted as `Double`, never
  converted to `Int`, so finite values beyond `Int.max` (for example `1e100` seconds) cannot trap.

- Covers (`YearExportArtworkLoader.load`):
  - Takes the stats' own ID lists: listener `finishedBooksWithCovers` (primary, at most 5) and `booksWithCovers`
    (secondary, at most 25); server `booksAddedWithCovers` (secondary, at most 25). More IDs are never requested.
  - Refuses IDs that are not one safe path segment (`[A-Za-z0-9._-]`, not `.` or `..`) before any request.
  - `fetch` is the app's authenticated request. The app passes `APIClient.coverData(itemID:)`: the bearer token stays
    in the `Authorization` header (with refresh) and is never put in a `?token=` query, a file, the image or the text.
    `GET /api/items/:id/cover` requires a signed-in user; the IDs come from that same user's (or admin's) stats response.
  - At most 4 requests at once. A failed, missing or undecodable cover is skipped; the rest keep server order.
  - Decodes through ImageIO thumbnails capped at 512 px and 20 MB of input. Nothing is cached or written to disk.
  - Cancellation stops queueing, cancels in-flight fetches and throws `CancellationError`.
  - Account pinning: `currentAccount() == owner` is checked before every fetch, after every fetch (successful or
    failed) and at the end. The first mismatch, or a fetch throwing `accountChanged`, stops the whole load with
    `YearExportArtworkError.accountChanged`; it is never treated as a missing cover.
  - The app uses `YearExportArtworkLoader.load(year:primary:secondary:api:authorization:)`. Its owner is
    `APIClient.authorizationRevision` (the existing auth generation, new on every sign-in, sign-out and restore, not on
    token refresh), so a switch A, B, A still mismatches. Each request goes through
    `APIClient.coverData(itemID:authorization:)`, which refuses to send, and refuses a response or a 401 retry, once the
    revision has changed. No cover request is ever sent with a later session.
- Snapshots accept artwork only when its year and requested ID lists equal the stats they are built from.
  Artwork from another year, account load or response is dropped, leaving the gradient designs.
- `YearExportServerSnapshot(stats:year:artwork:locale:)` copies an admin `ServerYearStats` response. Totals are cleaned
  (non-finite or negative become 0) and byte counts clamp before `Int64` overflow, so `1e300` renders safely.
- `YearExportComposer(server:)` and `YearExportSheet(server:onDone:)` mirror the listener initialisers.

## Model types for root wiring

All in `tvos/Core` (TVCore) unless noted:

- `YearListeningStats.finishedBooksWithCovers: [String]`, `.booksWithCovers: [String]` (default `[]` for older servers).
- `ServerYearStats` (Decodable, Sendable): `numListeningSessions`, `numBooksAdded`, `numAuthorsAdded`, `numBooks`,
  `totalBooksAddedSize`, `totalBooksAddedDuration`, `totalBooksSize`, `totalBooksDuration`, `totalListeningTime`
  (null or missing totals decode as 0), `booksAddedWithCovers`, `topAuthors`, `topNarrators`, `topGenres`.
- `APIClient.serverYearStats(_ year: Int)` calls `GET api/stats/year/<year>` and rejects years outside `2000...9999`
  without a request. A non-admin gets `APIError.http(403)` from the server.
- `CurrentUser.canViewServerYearStats` is true for `root` and `admin` only.
- `APIClient.authorizationRevision: UUID` (read-only view of the existing `authGeneration`; auth mutation is unchanged)
  and `APIClient.coverData(itemID:authorization:)` (the cover request pinned to that revision).
- `YearExport` module: `YearExportArtwork`, `YearExportArtworkLoader`, `YearExportArtworkError`,
  `YearExportSnapshot(stats:year:artwork:locale:)`, `YearExportServerSnapshot`, `YearExportComposer`, `YearExportSheet`.

## Root integration

`apple/App/YearReviewView.swift` is wired in this branch:

- The store reads `authorizationRevision` before requesting stats and accepts them only if it is unchanged afterwards
  (plus the existing account check). It builds a cover-less `YearExportSnapshot`, then a stored, cancellable task loads
  covers pinned to that revision and replaces the snapshot only if the request and revision still match.
- For `canViewServerYearStats` accounts it then loads the server year. Each step (`me`, server year, server covers)
  re-checks the same request and revision, so a sign-in change at any point, even back to the same account, ends the
  sequence. A 403 or network error leaves the server share hidden.
- `load(year:)` and `invalidate()` cancel that task and clear both snapshots.
- The share button (a menu with "Share My Year" and "Share Server Year" for admins) captures the snapshot when tapped and
  presents one `.sheet(item:)`. Covers arriving later never change an open composer.

Still for the root, which owns these files:

1. Add `Export/Sources/YearExport` to the `AudiobookshelfNative` sources in `apple/project.yml` and regenerate.
   The sources use `#if canImport(TVCore)`, so they compile both inside the app target and in the standalone package.
2. Add `NSPhotoLibraryAddUsageDescription` to the app's `info.properties` (for example "Save your year in review image
   to Photos."). Neither the app nor the QA host declares it, and the QA share sheet offered no Save Image action.
   The root should confirm Save Image on a device after adding it.

A scratch copy with step 1 applied builds `AudiobookshelfNative` with the wired view on Xcode 27
(`IPHONEOS_DEPLOYMENT_TARGET=15.0` build-only override; Xcode 27 rejects 14.0).

## Verification

- `cd apple/Export && xcodebuild test -scheme YearExport -destination 'platform=iOS Simulator,name=Audiobookshelf Year Export QA'`
  runs eight renderer and model tests. They were written first and observed failing against a stub: 7 of 8 failed
  (25 assertions), and the long-text overflow guard passed trivially on the blank stub. All 8 pass now. The tests
  decode the PNG and check pixel size and drawn text pixels for every layout, that pixels change with the data, that
  snapshot identity, year, file name and share text match, year validation, empty-year layouts, layout validation, that
  sharing never reuses a preview for another layout, and that very long names stay bounded.
- Review fixes on top of `6463c23c`, also red first:
  - `testFiniteButEnormousDurationsRenderAndShareWithoutTrapping` crashed the test process with
    "Double value cannot be converted to Int because the result would be greater than Int.max" before the fix.
  - `YearExportShareTests` failed in 3 of 4 cases against the original share behaviour, moved unchanged behind the
    testable seams: failed-write cleanup, release without completion, and presenting from a detached composer.
    Completion cleanup already worked and passed.
  - A mutation check (removing `deinit`) makes the release and detached-presentation tests fail again.
  - All 13 tests pass.
- A throwaway XCUITest host outside the repository drove the composer on a dedicated "Audiobookshelf Year Export QA"
  simulator (iPhone 17, iOS 27) with synthetic data only. It covered switching style and format, presenting the share
  sheet (it showed `audiobookshelf_my_2025_short` as a PNG image) and the empty year hiding Top Lists. Screenshots stay local.
- Annual covers and server export, red first: `YearExportArtworkTests` (9 tests) against stubs failed 8 of 9, with an
  "Index out of range" crash in the loader-order test; the identifier-leak guard passed trivially on the blank stub.
  `AnnualStatsTests` in TVCore (4 tests) failed 4 of 4 before the decode, route and role gate existed. Now all 22 Export
  tests and all 19 TVCore tests pass. They cover server order and unsafe, failed and undecodable covers, the 5 and 25
  caps, cancellation (no artwork, no more than 4 started fetches), account change, rejecting artwork for another
  year or other covers, covers actually drawn (pixel colour) in the mosaic and Finished designs, no cover ID in the PNG,
  text or accessibility label, the server designs, file names, sizes and text, hiding unfillable server lists, and
  `1e300` totals.
- Pinning review fix on top of `dfd9bfdc`, red first against the shipped wiring (the new glue started as a stub doing
  exactly what `YearReviewView` did: `currentAccount()` owner and unpinned `coverData`):
  - `YearExportPinnedArtworkTests.testAccountSwitchAToBToAWhileCoversLoadAbortsWithoutRequestingUnderAnotherSession`
    drives the real `APIClient` through a gated URL protocol: alice's first batch of 4 is held, bob signs in, those
    covers fail with 404, alice signs in again. Before the fix covers `s4` and `s5` were requested with bob's token and
    the load ended with `CancellationError`; now it ends with `accountChanged` and no request carries another session.
  - `testAnAccountChangeReportedByAFetchIsNotTreatedAsAMissingCover` returned 1 cover before the fix.
  - TVCore `PinnedCoverTests` sent `li-2` with bob's token and `li-3` with alice's new token before the fix; now only
    the request made under the pinned revision is sent.
  - Now 24 Export tests and 20 TVCore tests pass; the pinned tests also passed 20 repeated iterations. The scratch app
    build with the wired view succeeds.
- Synthetic-cover renders of every listener and server layout were inspected locally (`/tmp/yearexport-evidence/covers`,
  not committed). That pass found and fixed a mosaic drawn at full opacity and a divider drawn in copy blend mode.
- Not verified: a live server. Loading covers and the admin year from a real account is an owner-data operation and
  needs root review first; nothing here contacted a server. Also not verified: an iOS 14 or 15 runtime (none is installed), the iPad popover on a device, saving to Photos, and physical devices.
  All physical acceptance and migration gates remain open.
