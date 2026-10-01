# Apple year-review image export

A native composer that turns one `YearListeningStats` response and its Gregorian year into
shareable images and a text summary, generated entirely on the device. It lives in
`apple/Export` and has no API, account or navigation coupling. The root integrates it.

## Legacy source and parity

The primary sources are the mobile canvases in `components/stats/`:

| Legacy canvas | Native design | Notes |
| --- | --- | --- |
| `YearInReview.vue` variant 0 (stat boxes, top narrator/genre/author/month) | Highlights | Square and portrait. Portrait adds the longest finished book, which the endpoint already returns. |
| `YearInReview.vue` variant 1 (finished-book covers) | Not offered | Needs `finishedBooksWithCovers` plus cover downloads. `YearListeningStats` does not decode them, and the composer must not fetch. |
| `YearInReview.vue` variant 2 (top authors and genres lists) | Top Lists | Square and portrait. Hidden when both lists are empty. |
| `YearInReviewShort.vue` (books finished/listened banner) | Compact | 3:1 banner, like the 600×200 original. |
| `YearInReviewServer.vue` (admin server totals from `/api/stats/year`) | Not offered | Different payload and admin permission. The root owns fetching and permissions, so the composer does not fabricate it. |

The legacy cover-art background mosaic is replaced by an artwork-free gradient for the same reason.
File names keep the legacy `audiobookshelf_my_<year>.png` / `_short.png` scheme, plus `_top` and `_story` suffixes.

## Contract

- `YearExportSnapshot(stats:year:locale:)` copies the values once and fails for years outside `2000...9999`
  (the same range `APIClient.yearListeningStats` accepts). Each snapshot has a fresh `id`.
- `YearExportComposer(snapshot:)` keys all of its state to `snapshot.id`. Passing a different snapshot
  rebuilds the composer, so a preview or share item from another year or account cannot survive.
  `YearExportSheet(snapshot:onDone:)` wraps it for modal presentation.
- `YearExportRenderer.render(_:layout:)` is a pure function from snapshot and layout to PNG bytes, the file name,
  the share text and an accessibility label. It uses `UIGraphicsImageRenderer` and Core Graphics, not SwiftUI
  `ImageRenderer` (iOS 16). Every API it uses is available on iOS 14.
- Sharing always re-renders when the cached preview is for another layout. It shares a PNG file
  (temporary directory, complete file protection, removed when the activity finishes) plus the text summary
  through `UIActivityViewController`, anchored to the button for the iPad popover.
- Zero statistics render as zeros with a "No listening recorded" panel. Long names truncate with an
  ellipsis, and large numbers shrink to fit and then truncate.

## Root integration

1. Add `Export/Sources/YearExport` to the `AudiobookshelfNative` sources in `apple/project.yml` and regenerate.
   The sources use `#if canImport(TVCore)`, so they compile both inside the app target and in the standalone package.
2. Build a snapshot in `YearReviewStore` at the same point the account-checked stats are accepted. Capture it
   when the share button is tapped, and present `.sheet(item:)`:

```diff
--- a/apple/App/YearReviewView.swift
+++ b/apple/App/YearReviewView.swift
@@ @MainActor private final class YearReviewStore: ObservableObject {
     @Published private(set) var stats: YearListeningStats?
+    @Published private(set) var export: YearExportSnapshot?
@@ func load(year: Int) async {
-        self.year = year; stats = nil; error = nil; loading = true
+        self.year = year; stats = nil; export = nil; error = nil; loading = true
@@
             stats = value
+            export = YearExportSnapshot(stats: value, year: year)
@@
-    func invalidate() { revision = UUID(); stats = nil; loading = false }
+    func invalidate() { revision = UUID(); stats = nil; export = nil; loading = false }
@@ struct YearReviewView: View {
-    @State private var share = false
+    @State private var exporting: YearExportSnapshot?
@@
-    private var shareText: String { ... }            // remove
@@
-            .toolbar { ... Button { share = true } ... .disabled(store.stats == nil) }
-            .sheet(isPresented: $share) { YearReviewShare(text: shareText) }
+            .toolbar { ... Button { exporting = store.export } ... .disabled(store.export == nil) }
+            .sheet(item: $exporting) { YearExportSheet(snapshot: $0) { exporting = nil } }
@@
-private struct YearReviewShare: UIViewControllerRepresentable { ... }   // remove
```

3. Add `NSPhotoLibraryAddUsageDescription` to the app's `info.properties` (for example "Save your year in review image
   to Photos."). Neither the app nor the QA host declares it, and the QA share sheet offered no Save Image action.
   The root should confirm Save Image on a device after adding it.

The scratch integration build of `AudiobookshelfNative` with this exact patch succeeded on Xcode 27
(`IPHONEOS_DEPLOYMENT_TARGET=15.0` build-only override; Xcode 27 rejects 14.0).

A server-year mode needs a separate snapshot type fed by a root-owned, admin-gated fetch. It is not part of this component.

## Verification

- `cd apple/Export && xcodebuild test -scheme YearExport -destination 'platform=iOS Simulator,name=Audiobookshelf Year Export QA'`
  runs eight renderer and model tests. They were written first and observed failing against a stub: 7 of 8 failed
  (25 assertions), and the long-text overflow guard passed trivially on the blank stub. All 8 pass now. The tests
  decode the PNG and check pixel size and drawn text pixels for every layout, that pixels change with the data, that
  snapshot identity, year, file name and share text match, year validation, empty-year layouts, layout validation, that
  sharing never reuses a preview for another layout, and that very long names stay bounded.
- A throwaway XCUITest host outside the repository drove the composer on a dedicated "Audiobookshelf Year Export QA"
  simulator (iPhone 17, iOS 27) with synthetic data only. It covered switching style and format, presenting the share
  sheet (it showed `audiobookshelf_my_2025_short` as a PNG image) and the empty year hiding Top Lists. Screenshots stay local.
- Not verified: an iOS 14 or 15 runtime (none is installed), the iPad popover on a device, saving to Photos, and physical devices.
  All physical acceptance and migration gates remain open.
