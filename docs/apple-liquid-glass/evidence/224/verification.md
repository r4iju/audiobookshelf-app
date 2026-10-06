# Ticket 224 verification

Starts at `be12703ee1e78670e1cd942581dfb8211d0cc9a1`, verified ancestor of this change. Apple mobile presentation only. Source minimum remains iOS 14.

Library selection and filters use native lists and modern navigation stacks, with `NavigationView` fallback. Modern iPads use adaptive split navigation with an initial compact detail column, preserving the detail stack across size-class changes. Account destinations use `navigationDestination` on modern systems and retain legacy links on older systems. Native UIKit search exposes the appropriate search-field accessibility role with the existing `library-search` identifier. Its clear control and Search keyboard action are native; query debounce, pagination, related routes, catalog actions and stores are preserved.

Glass stays on native navigation/toolbars and the layout/detail action controls, using the ticket 223 availability/accessibility foundation. Covers and rows remain content surfaces. Accessibility text uses wider grid columns and untruncated title/author metadata; detail headers stack at accessibility sizes.

No new tests were added. Two existing search journeys first failed because their old `textFields` selector did not recognize the native `searchFields` role. Their existing navigation seam now supports the native role and the legacy text-field role. The final search and related behavior checks use that seam.

Build passed with Xcode 27.0, iOS 27 SDK:

```sh
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination 'generic/platform=iOS Simulator' -derivedDataPath apple/build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
```

The existing verifier builds/signs the same app with the build-only iOS 15 override; the source deployment target remains 14. Xcode 27 cannot build an iOS 14 simulator target.

Across focused verification, 16 distinct existing journeys passed. The final native search/related/artwork run executed 8 tests with 0 failures and 0 skips. Existing focused journeys passed:

- `SearchJourney`: all three search, return, episode-playback and sort/filter journeys.
- `RelatedAuthorSeriesJourney`: all four author/series/detail/ordering/recovery journeys.
- `ArtworkJourney`: cover geometry on iPhone.
- `CatalogRecoveryJourney`: all four recovery/read-only/metadata journeys.
- `ConnectionJourney/testBrowsePaginatedBooksAndExpandedMetadata` and `testConnectSelectLibraryAndRestoreAccountAfterRelaunch`.
- `CollectionJourney/testDownloadedGroupRefreshesCompletionMadeAfterOpening` and `testPodcastPlaylistRowRetainsSelectedEpisodeForDetailsAndPlayback`: programmatic collection/playlist destinations and detail playback.

These run through `ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C apple/scripts/verify-ui.sh` with explicit `-only-testing:` selections. Related verification additionally starts the owned `python3 tvos/scripts/related_fixture.py --port 27765` fixture and sets `TEST_RUNNER_ABS_RELATED_QA=1` so those journeys execute instead of skipping.

Actual pooled iPad evidence: [narrow portrait, dark](ipad-narrow-dark.png), [wide landscape, dark](ipad-wide-dark.png), [narrow portrait, light at accessibility-extra-large](ipad-narrow-large-light.png). Native Settings navigation and appearance selection also worked during inspection. The shared Device panel enumerated both devices; iPhone open succeeded, while iPad reopen reported a support communication error. Its already-open Device panel session was used successfully for inspection and screenshots.

These are portrait/landscape sizes, not Stage Manager or split-screen compact-width proof. Comprehensive multitasking, all accessibility combinations, older OS execution, physical device checks and full screenshot coverage belong to ticket 228. The small decorative missing-cover title can clip at very large text; the adjacent accessible title and author remain visible and wrap. Artwork journey confirms loaded cover containment.

The frontend skill's React/TypeScript routing patterns do not apply to the changed SwiftUI presentation. No React bars were opened; its only grep hit was a pre-existing Swift forced unwrap in `ShelfStyle.accentFill`, outside this change.

Result bundles: `apple/build/Logs/Test/Test-AudiobookshelfNative-2026.10.06_23-25-48-+0900.xcresult` (initial recovery/navigation run and observed search-role failures), `Test-AudiobookshelfNative-2026.10.06_23-36-33-+0900.xcresult` (collection/playlist and intermediate search checks), and `Test-AudiobookshelfNative-2026.10.06_23-39-11-+0900.xcresult` (final native search, related and artwork, 8/8 passed).
