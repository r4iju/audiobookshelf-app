# Ticket 228 integration verification

Application source: `1064bd6cf34e21f8edd1bda0ab0b4f22303ba32b`, verified ancestor on `feature/apple-liquid-glass`. Verification-only fixes: `b28fddedc9c0c2105fbc2c106454a347aa05b603`. Xcode 27.0 (`27A266a`). Personal context/preferences, all six tickets, spec, manifest and evidence 223–227 were loaded. Existing Node fixture dependencies were present. All fixtures are fresh owned synthetic loopback data. No owner server, NAS, credentials or physical devices were accessed.

## Passed checks

[Exact counts and local result bundles](checks.tsv) identify every final selected run. Existing Apple NativeTests passed 88/88; their six fixture-dependent tests were run with the proper dedicated fixtures rather than counted as skipped: playback authorization 4/4 and actual full-volume download/publication storage 2/2. TVAppTests passed 17/17. Relevant packages passed Localization 18, Diagnostics 21, Migration 39 and TVCore 72. UIKit-only YearExport ran through its iOS package scheme, 28/28. A macOS `swift test` attempt was inappropriate for UIKit and was replaced by that passing simulator run; its temporary manifest experiment was reverted.

Final mobile UI runs passed light/dark/black contrast (3), iPhone27 authentication recovery/chapter-speed/PDF with audio (3), iPad27 large-player/Arabic/German localization (3), iPhone27 largest-text search (1), Reduce Transparency download retry/offline lifecycle (2), and combined Reduce Transparency/Increase Contrast/Reduce Motion with largest player text (1). TV remote focus/Back, remote playback and main-screen accessibility audit passed 3/3. Existing measured contrast dismissals were preserved without changes; no audit was weakened and no unsupported dismissal was added.

Core commands (run from the repository root, except YearExport):

```sh
xcodegen generate --spec apple/project.yml
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme NativeTests -destination 'id=CDFFEB30-07F5-4A50-AB64-57A46709335B' -derivedDataPath /tmp/lg228/native-final CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath /tmp/lg228/native-pass.xcresult -collect-test-diagnostics never -skip-testing:NativeTests/DownloadStorageTests -skip-testing:NativeTests/PublicationStorageTests -skip-testing:NativeTests/PlaybackAuthorizationTests test
ABS_PLAYBACK_QA_SIMULATOR=B1D2244C-1D78-47FF-A7CD-027B9028051C apple/scripts/verify-playback-authorization.sh -only-testing:NativeTests/PlaybackAuthorizationTests
ABS_REMAINING_QA_SIMULATOR='Pool iPhone 1 (iOS 26.0)' apple/scripts/verify-download-storage.sh -only-testing:NativeTests/DownloadStorageTests -only-testing:NativeTests/PublicationStorageTests
ABS_REMAINING_QA_SIMULATOR='Pool iPhone 1 (iOS 26.0)' apple/scripts/verify-remaining-qa.sh -only-testing:NativeJourneyTests/RemainingQAAccessibilityJourney
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/ConnectionJourney/testInvalidServerShowsRecoveryWithoutLeavingConnectionForm -only-testing:NativeJourneyTests/ListeningControlsJourney/testChapterSeekAndSpeedSurviveSessionRestoration -only-testing:NativeJourneyTests/ReaderJourney/testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference
ABS_PRESENTATION_SIMULATOR='Pool iPad 1 (iOS 27.0)' apple/scripts/verify-presentation.sh -only-testing:NativeJourneyTests/PresentationJourney/testAccessibilityTextSizeKeepsPlayerControlsOnScreen -only-testing:NativeJourneyTests/PresentationJourney/testSavedLanguageTranslatesNativeScreensAndSurvivesRelaunch -only-testing:NativeJourneyTests/PresentationJourney/testRightToLeftLanguageMirrorsNativeLayout
ABS_PRESENTATION_SIMULATOR='Pool iPad 1 (iOS 27.0)' apple/scripts/verify-presentation.sh -only-testing:NativeJourneyTests/PresentationJourney/testSavedLanguageTranslatesNativeScreensAndSurvivesRelaunch
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/SearchJourney/testSearchFindsBookBeyondFirstPageAndReturnsFromDetails
ABS_QA_SIMULATOR=B1D2244C-1D78-47FF-A7CD-027B9028051C apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/OfflineJourney/testSuccessfulHTTPErrorPageIsRejectedAndRetryRecoversTheDownload
ABS_QA_SIMULATOR=B1D2244C-1D78-47FF-A7CD-027B9028051C apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/OfflineJourney/testDownloadedBookPlaysAcrossFilesOfflineAfterRelaunchAndSynchronizesOnReconnect
ABS_PRESENTATION_SIMULATOR='Pool iPhone 1 (iOS 26.0)' apple/scripts/verify-presentation.sh -only-testing:NativeJourneyTests/PresentationJourney/testAccessibilityTextSizeKeepsPlayerControlsOnScreen
ABS_TV_QA_SIMULATOR=9ACC6F5B-180D-44C3-823B-F8796813D69D ABS_TV_RESULT_BUNDLE=/tmp/lg228/tv.xcresult tvos/scripts/verify-ui.sh -only-testing:TVAppTests -only-testing:TVJourneyTests/ReadinessJourney/testMainScreensPassTheAccessibilityAudit -only-testing:TVJourneyTests/CatalogJourney/testContinueListeningOpensDetailsAndBackRestoresFocus -only-testing:TVJourneyTests/PlaybackJourney/testResumeShowsChapterAndTotalProgressAndRemoteToggles
swift test --package-path apple/Localization
swift test --package-path apple/Diagnostics
swift test --package-path apple/Migration
swift test --package-path tvos/Core
# From apple/Export:
xcodebuild -scheme YearExport -destination 'platform=iOS Simulator,id=CDFFEB30-07F5-4A50-AB64-57A46709335B' -derivedDataPath /tmp/lg228/export test
```

## Observed failures and corrections

No new tests were added. Initial NativeTests executed 94 with six fixture-dependent skips and 24 ProgressReset failures. The stale stub omitted item GET responses now required by the production post-reset callback (and no-row refresh). A minimal existing stub item route restored all 25 reset tests and all 88 ordinary native tests. GET/DELETE assertions and server behavior remain unchanged. The six skipped tests then passed on their proper fixtures. No domain API or store was edited.

Localization's legacy selectable-language test referenced a deleted `plugins/i18n.js`. Its current tree no longer contains that legacy web runtime. A minimal 30-language map, taken from `fcd4bcdae10ae20abba0dff68f31bab63d55bc1b^:plugins/i18n.js` with provenance, is now local test data; the original ordering/names assertions remain. It passed 18/18 afterward.

The iPad German journey found the chosen row below a virtualized list's viewport. Its existing journey now scrolls to the row before tapping and passed. Largest phone text similarly put the authentication fields below the lazy Form's first screen; the existing sign-in seam scrolls to each field, preserving credential and navigation assertions. Largest-text search then passed, including typing, keyboard Search, result details and Back. One initial iPad keyboard-focus failure coincided with a Settings inspection; the clean rerun exposed the independent below-fold row issue above and was rerun after correction.

The presentation verifier initially selected implicit `OS:latest` for the correctly named iOS26 pool device and failed to resolve it. It now resolves the provided leased device name to its exact available UDID before xcodebuild; the same combined fallback test passed on iOS26. Two attempted runs refused already-owned fixture ports and were rerun after those fixtures finished. No failed attempt was waived as passing evidence.

## Actual platform inspection and limitations

Pooled devices were leased through `sim acquire` and opened in the shared Device panel using T3 `device_list`/`device_open`. The exact returned CLI config/session flags were retained. iPhone26, iPhone27 and iPad27 were available. The panel does not enumerate TV, so retained remote-driven XCTest/platform screenshots provide its legitimate interaction seam.

Inspected final [iPhone26 light player](iphone26-light-player.png), [PDF controls](iphone26-light-pdf-reader.png), [dark catalog](iphone26-dark-catalog.png), [black settings](iphone26-black-settings.png), [iPhone27 player](iphone27-player.png), [iPad largest player](ipad-Native-player-with-accessibility-text-size.png), [Arabic](ipad-Native-language-settings-in-Arabic.png), [focused TV details](tv-detail.png) and [TV player](tv-now-playing.png). Content remains solid, primary glyphs are legible, and existing player/PDF activation checks pass.

On iPhone26, native Settings UISwitch actions enabled Reduce Transparency, Increase Contrast and Reduce Motion, each observed with value `1`. The [combined largest player](iphone26-player-largest-opaque-reduced-motion.png) was captured from the passing final journey. Reduce Transparency alone passed independent Retry recovery and full offline playback/relaunch/synchronization without removing the download, so the suspected List-button coactivation was not reproduced. No runtime change was made based only on that suspicion. Physical animation timing/haptics are not inferred from simulator screenshots.

On iPhone27, `xcrun simctl ui <UDID> content_size accessibility-extra-extra-extra-large` selected the largest category before the passing search journey. Manual [typed query, clear action and result](iphone27-largest-search.png) inspection then used a fresh owned fixture. Tapping Clear changed the field back to its placeholder, removed the result and Clear control, and disabled keyboard Search, as shown in [cleared search](iphone27-largest-search-cleared.png). The native field horizontally scrolls long text while editing; no vertical label clipping or failed Search/clear activation was observed.

The iPad was genuinely resized using native Settings > Multitasking & Gestures > Windowed Apps and the OS bottom-right resize handle. [Actual compact window](ipad-compact-window-dark.png) shows the desktop/dock around the 375 × 779-point app (confirmed by AX Window bounds), with compact Library back navigation and readable catalog content. This is an actual window geometry, not a resized screenshot or portrait-only claim. Full-width iPad player/localization journeys passed before resizing.

Compact-window action acceptance remains **unverified**. Agent-device returned window-local coordinates but dispatched taps outside their apparent offset, regular AX snapshots failed with `node escaped its cumulative clip`, and expansion gestures were rejected against the compact viewport. A fresh existing XCTest largest-player attempt in that retained compact window returned only `Application` and failed before authentication, so it supplies no compact-player proof. Native desktop CUA was unavailable (`CUA_REPL_ENABLED_SURFACES is required`). Full Screen Apps was restored with a native OS action. No black/empty capture is counted as detail evidence, and retained-detail/sidebar/player behavior in a compact window is not claimed. This is a precise remaining tooling/acceptance limitation for integration review.

Accessible roles, labels, selected states, errors and order were observed through AX/XCTest (including localized Selected, native search role/clear state, transport and TV focus/Back) and the unchanged TV accessibility audit. Actual VoiceOver speech and physical VoiceOver traversal remain unavailable. Older supported iOS14/15 and tvOS17 execution, physical TV glass capability gating, hardware background/remote/headset/haptic behavior and owner-data/live-server acceptance are not claimed. Simulators and fixtures were reset/released after evidence.

## Private Release candidates

Exact application source remains `1064bd6cf34e21f8edd1bda0ab0b4f22303ba32b`; #228 only changes tests/verifier/docs. No signing identity, license, entitlement, bundle identity or source deployment minimum changed. Both commands completed `ARCHIVE SUCCEEDED`:

```sh
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/lg228/release-ios -archivePath "$HOME/.local/share/leafwake/apple-liquid-glass/1064bd6cf34e21f8edd1bda0ab0b4f22303ba32b/iOS.xcarchive" CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 archive
xcodebuild -project tvos/AudiobookshelfTV.xcodeproj -scheme AudiobookshelfTV -configuration Release -destination 'generic/platform=tvOS' -derivedDataPath /tmp/lg228/release-tv -archivePath "$HOME/.local/share/leafwake/apple-liquid-glass/1064bd6cf34e21f8edd1bda0ab0b4f22303ba32b/tvOS.xcarchive" CODE_SIGNING_ALLOWED=NO archive
```

Archives and ZIP copies stay privately under that exact-source directory. iOS architecture `arm64`, actual minimum runtime `15.0`; tvOS architecture `arm64`, minimum runtime `17.0`. Source minimum remains iOS14/tvOS17. Xcode27's build-only iOS15 override does not establish iOS14 runtime acceptance or change the approved support requirement.

| Private artifact | SHA-256 |
| --- | --- |
| `iOS.xcarchive.zip` | `d98d37fc18c6ee1117acff6c3b147d2751c258f60f6594c64a2011b28b6dec17` |
| iOS app executable | `8d77442e3f3fc32ce5c69ee4fe804bc24b1898debda54bbdcea4c0eef62d9b26` |
| `tvOS.xcarchive.zip` | `3c2ed0f7a210d0175d6173eb3230f1703710798c579638983eec2210dd5a03e1` |
| tvOS app executable | `370383d7e34e3f6578703f8e0ac6f33db3ba9feaffcb7c5bfa6c74a6ff646471` |

Public Apple distribution rights/terms remain a gate. These unsigned candidates have not been uploaded, published, installed on owner hardware or represented as App Store acceptance.

`git diff --check`, scoped source inspection and relative documentation link validation passed. Only Apple/tvOS verification and Apple redesign documentation changed. Frontend React/TypeScript routing bars do not apply to SwiftUI verification; grep found only the existing `episode as Any?` test conversion in ProgressResetTests, with no applicable bar opened. Final independent two-axis review, PR merge and tracker updates remain with the integration coordinator.
