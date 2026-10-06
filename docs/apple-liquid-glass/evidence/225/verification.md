# Ticket 225 verification

Starts at `c283e5fcc4e683ba018e33f770939c32cc4784cc`, verified ancestor. Changes are Apple mobile presentation and the shared availability/accessibility helper only. Audio stores, media lifecycle, offline storage, progress synchronization, localization keys and control identifiers are unchanged.

The compact player uses one neutral genuine Liquid Glass surface on iOS 26+. Its nested controls remain plain, avoiding glass on glass. `safeAreaInset` reserves its actual height on iOS 15+, with measured overlay spacing on iOS 14. Expanded playback retains a native full-screen presentation with a modern navigation stack; chapter/speed/sleep/bookmark/settings panels use native large sheets with legacy navigation fallbacks. Artwork and progress content retain stable solid surfaces. Listening actions use two columns at regular text sizes and full-width rows at accessibility sizes. The primary transport uses white symbols with the light-resolved accent fill, including an opaque circular fallback. Reduce Transparency, increased contrast and Reduce Motion use the existing foundation policy.

No new tests were added. An existing offline journey initially failed because the recovery Form's lazy rows hid the downloaded-books entry below the visible viewport. Its captured hierarchy showed HTTP 503 recovery and two scroll pages. The existing conditional “Open downloads” action now lives in the native navigation toolbar, remaining immediately available when downloaded files exist. The same existing journey then passed through offline playback, file changes, termination, position restoration and reconnect synchronization. The initial subsequent playback case inherited the offline fixture's 503 state. This existing case does not reset fixture state and must run alone against a fresh fixture.

Xcode 27.0 / iOS 27 SDK simulator build passed. Source minimum remains iOS 14; build-only iOS 15 override is required by this installed simulator SDK:

```sh
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination 'generic/platform=iOS Simulator' -derivedDataPath apple/build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
```

Focused verification uses `apple/scripts/verify-ui.sh` and explicit `-only-testing:` selections. Its Node fixture dependencies were present before tests. Initial iPhone run passed existing durable-progress termination/recovery, bookmark create/edit/jump/delete, chapter/speed restoration, and short-sleep-timer stop/persistence journeys. The final iPhone run passed chapter/speed restoration and the full downloaded offline/relaunch/synchronization journey, 2 tests, 0 failures.

The iPad bookmark journey also passed. After replacing the intermediate short expanded sheet and lazy control grid, the final iPad chapter/speed restoration journey passed. The isolated real-audio cross-file/background-browsing journey passed on iPad with a fresh fixture. Running it immediately after chapter/speed had inherited that journey's final server progress and reached natural completion, so that combined run is not the cross-file proof.

Result bundles:

- Initial focused run: `apple/build/Logs/Test/Test-AudiobookshelfNative-2026.10.06_23-46-33-+0900.xcresult` (4 passed, offline recovery entry failure and its cascading fixture-state failure).
- Initial iPad sheet run: `apple/build/Logs/Test/Test-AudiobookshelfNative-2026.10.06_23-53-28-+0900.xcresult` (bookmark passed; chapter/speed label deferred below sheet viewport; subsequent playback inherited final server progress).
- Final iPad chapter/speed check: `apple/build/Logs/Test/Test-AudiobookshelfNative-2026.10.06_23-56-47-+0900.xcresult` (chapter/speed passed; subsequent cross-file request assertions failed with inherited remote progress).
- Isolated final iPad real-audio run: `apple/build/Logs/Test/Test-AudiobookshelfNative-2026.10.06_23-58-57-+0900.xcresult` (1/1 passed).
- Final iPhone run: `apple/build/Logs/Test/Test-AudiobookshelfNative-2026.10.06_23-51-27-+0900.xcresult` (2/2 passed).

An intermediate iPad sheet run exposed controls below its shorter viewport; expanded playback retains native full-screen presentation and four listening actions use eager rows. The existing chapter/speed journey provides the failed-then-passing check.

The frontend skill's React/TypeScript routing grep found only the pre-existing Swift forced unwrap in `ConnectionViews.swift:9` (`Color(UIColor(named: "AccentColor")!.resolvedColor(...)`), outside changed lines. No React bars apply or were opened. Both pooled simulators were leased with `sim acquire`, enumerated and opened successfully in the shared Device panel before visual evidence. Final [iPhone compact player](iphone-compact-light.png) and [iPhone full-screen player](iphone-player-light.png) were captured from the final built app through the device CLI. [iPad full-screen player in dark appearance](ipad-player-dark.png) was exported from the passing final chapter/speed journey. All were inspected; the white primary glyph is legible, secondary actions remain scrollable, and compact playback reserves content space without covering navigation.

Older OS execution, physical-device background/remote behavior and the complete accessibility/multitasking matrix remain integration checks for ticket 228. This presentation change introduces no audio lifecycle implementation changes.
