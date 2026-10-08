# Ticket 231: executable phone/tablet design slice

Production source: `0894eb047a5319294dcc5e1d41f976f7eb1f4bf5`, based on start `cbede4693b72c04009150eac544210b6a4f0253d` (Apple source base `77c154b1`). Native five-destination shell, contextual selected-library sheet, visible Library group links, system search, native compact accessory and adaptive expanded listening composition are integrated into the existing app. Existing account/player/download/reading stores, preference keys, identities and notices are unchanged. No parallel feature flag or throwaway presentation remains.

Source minimum remains iOS14. The Xcode27.0 build override is iOS15; the actual simulator and generic-device binaries have minimum 15, not 14. The simulator apps are ad-hoc signed, version1.0.0(1). `simulator-builds.json` records each installed executable hash and the identical implementation `debug.dylib` hash. `baseline-build.json` identifies the original before app. Generic-device compilation was unsigned and was not a private release/install acceptance check.

## Installed-app checks

| Check | Result |
| --- | --- |
| New ShellJourney, before app implementation | Actual red on phone: Library main destination absent (1 expected failure); same baseline tablet failure |
| Final source phone ShellJourney | Green: stable five destinations, Library detail retained across Downloads/Settings, selected library shared with Search, native search query/results, Listen Now activation |
| Final source phone artwork and fractional bookmark journeys | Green; final source phone run total **3 tests, 0 failures** |
| Final source wide iPad ShellJourney | Green, **1 test, 0 failures**. Native sidebar cells required a locator-only adaptation after observed button-locator red. Assertions retained |
| Final source iPad fractional bookmark journey | Green, **1 test, 0 failures** |
| Representative phone regression | **8 tests, 0 failures**: catalog pagination/details, account relaunch restoration, cover bounds, fractional bookmarks, episode search/play, search beyond first catalog page/Back, server sort/filter, shell. This earlier run preceded the final compact artwork and 26.0 fallback adjustments; final source replays above verify those adjustments |
| Obsolete account/search locators | Observed red first in ArtworkJourney and SearchJourney; adapted to visible Settings/Library/Search with the same assertions |
| Generic iOS device build | Green with build-only deployment override15 and signing disabled |
| Full SwiftUI source diagnostic targeting iOS14 | Green: **76 Swift files** typechecked with SDK 27, Swift 5, target `arm64-apple-ios14.0-simulator`. This is availability diagnostics, not proof of an iOS14 binary or execution |
| Localization package / generated tables | **18 tests, 0 failures**; `generate.py --check` passed |

Concise original result excerpts are in `check-results.txt`; the exact source14 diagnostic argv (one argument per line) is in `source14-typecheck-command.txt`. Raw builds, XCTest results, attachment exports and recordings stay in `/tmp/231-*`; they are not committed. Representative UI commands:

```sh
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C apple/scripts/verify-ui.sh \
  -only-testing:NativeJourneyTests/ShellJourney \
  -only-testing:NativeJourneyTests/ListeningControlsJourney/testDeletingFractionalBookmarkPreservesItsIntegerNeighbor \
  -only-testing:NativeJourneyTests/ArtworkJourney -resultBundlePath /tmp/231-phone-final.xcresult
ABS_QA_SIMULATOR=CDFFEB30-07F5-4A50-AB64-57A46709335B apple/scripts/verify-ui.sh \
  -only-testing:NativeJourneyTests/ShellJourney -resultBundlePath /tmp/231-pad-shell-green.xcresult
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/231-generic-build \
  CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
swift test --package-path apple/Localization
python3 apple/Localization/generate.py --check
```

## Actual screen evidence and decisions

All screens use pooled iOS27.0 (24A434) simulators, phone `75FA9768-B15C-40B6-ACC7-790D7FCAD29C` and iPad `CDFFEB30-07F5-4A50-AB64-57A46709335B`. Before phone shows the missing-artwork catalog. Before iPad includes catalog, detail, compact and expanded players with actual synthetic cover images. Final iPad captures are actual **1210×834 landscape device displays**, with the sidebar and a two-column expanded player including every secondary tool. They establish wide composition, not compact-window acceptance. XCTest's rotated iPad screenshot export contained a black-margin artifact and is excluded in favor of direct device captures.

`after-iphone-search-software-keyboard.png` shows the actual software keyboard after tapping the final-source native Search field through the pinned device CLI. Its visible keys were checked against the device screenshot. The system hides the compact accessory and blurs tabs beneath the keyboard in this composition. This is representative geometry evidence, not complete keyboard interaction acceptance. Uncertain interim missing-artwork/focused-search exports were removed; all retained `after-*` captures represent source `0894eb04`. Before images represent the baseline app above.

The grid uses equal square artwork canvases. Portrait images intentionally fit completely inside them, so visible portrait artwork is narrower than square artwork. Metadata aligns to equal columns; artwork is not cropped merely to equalize apparent image width. This is a deliberate visual decision for independent #233 review.

iOS18+ uses native sidebar-adaptable tabs. iOS16/17 iPad keeps a stable native TabView in split-view detail to retain its stacks when sidebar selection changes. Older systems use native tabs. Native search is `searchable` on 15+, with navigation-owned UISearchController on 14; the fixed-height embedded bar is removed. API signatures were checked against the installed SDK and Apple's [search documentation](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:)), [sidebar-adaptable tabs](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable), and [bottom accessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)).

The disableable native accessory overload begins 26.1. An always-attached empty 26.0 accessory produced an idle pill; replacing the entire TabView conditionally would risk losing detail state. Therefore 26.0 uses the stable safe-area compact-player fallback, while 26.1+ uses the native accessory with `isEnabled`. Final source does not retain the known empty idle accessory. The actual26.0 fallback must be reviewed in #239. Expanded listening uses native ControlGroup for chapters/speed/bookmarks/timer, plain skip controls, and a standard prominent glass primary button on 26+. Artwork and listening content remain solid.

Synthetic visual covers are reproducible from `fixture-covers/generate.swift` into `/tmp/231-covers`. Visual fixture: `ABS_QA_COVER_DIRECTORY=/tmp/231-covers python3 -m verification.fixture --port 25769`, node proxies 25765 (and 19765 only after XCTest fixtures stopped), configured to `large-cover-art`. Owned synthetic accounts only. No production NAS, owner media, public Apple upload or messaging was used.

Current Search forces `.navigationBarDrawer(displayMode: .always)` and the phone search role appears in the attached native tab group. This top-field/attached-tab composition remains pending #233 judgment against the [current Apple adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), which shows phone bottom search moving above the keyboard, iPad toolbar search and a separate trailing semantic search tab. System API usage alone does not establish latest Search design acceptance. The normal phone grouped tools retain all labels, but Bookmarks hyphenates across two lines; #233/#235 should review that compact label composition and largest-text interactions.

The React frontend grep bars are inapplicable to SwiftUI; the only grep match was the pre-existing UIColor asset force unwrap in ConnectionViews. TDD used the actual installed-app XCTest seam, with a real red before implementation. No view-modifier/constant assertions or backfilled green tests were added.

## Remaining acceptance

#233 independent visual review remains required. #234–237 complete catalog, listening panels, readers/download/podcast composition and utilities. New Listen Now/suggestion labels currently retain disclosed English fallbacks; complete mobile localization review belongs to #237/#239. Existing utility content is reused behind working destinations and is not represented as fully redesigned.

#239 must still verify actual compact iPad window geometry/resizing and selection retention, largest text interaction, combined OS accessibility settings, spoken VoiceOver, old-OS runtime/binary support, all durability/offline/recovery journeys, and 26.0 compact-player fallback. Screenshots, typechecking and these focused tests do not satisfy those gates. #240 owns private candidates and owner installations. Parent issues 230/222 remain unchanged. No push, PR, merge or issue close was performed by this worker.

## Handoff resource cleanup

Owned synthetic fixture processes on 19765, 25765 and 25769 were stopped; a final listener check found none. Both owned simulator leases were released with `sim release`; `sim list` reports both devices free (the T3 live-device service may keep them booted). No clones were created.
