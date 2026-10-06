# Ticket 226 verification

Starts at `a67b33be6967a5bae187d52b685fce4bb148ca02`, verified ancestor. Changes cover Apple mobile presentation, its generated Xcode source references, one existing UI selector, and this evidence. No domain stores, persistence, API contracts, localization keys, Android, browser, backend or TV source changed.

Reading, downloads, feeds, queue editors, RSS utilities and saved accounts use the shared `NativeNavigation` stack on iOS 16+, retaining `NavigationView` on iOS 14/15. The helper and its file were renamed together, including scoped existing catalog/player callers and regenerated project references. Settings and network preferences use native Forms with retained radio-choice identifiers and stored values. Diagnostics status values stack at accessibility sizes; statistics and year review use inline native navigation, with separate 44-point year controls. Saved accounts keep Add server in the toolbar, and feed queueing stays reachable in the native bottom toolbar even with long episode lists.

PDF and EPUB content remain solid. Short page controls use the existing genuine-glass/accessibility foundation; PDF page entry, rotation and listening controls occupy a bounded scroll area that accommodates larger text. Native reader settings retain every existing preference and identifier. Download retry and offline reading/playback actions use the same native button policy. Increase Contrast and Reduce Transparency select the existing opaque fallback; Reduce Motion retains the shared policy. Source minimum remains iOS 14.

Final Xcode 27.0 / iOS 27 simulator build passed after the helper file move and project regeneration:

```sh
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination 'generic/platform=iOS Simulator' -derivedDataPath apple/build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
```

The iOS 15 override is build-only, required by the installed SDK. No deployment target was raised in source. Fixture Node dependencies were present before tests.

Ten distinct existing journeys passed, zero final failures or skips. Each ran independently against fresh owned fixtures. [Exact selections and result bundles](checks.tsv) cover PDF with audio/continuous display persistence, downloaded offline EPUB chapter restoration, failed download retry, feed selection/queueing, theme/haptic persistence, separate network policies, saved-server/library/unsent-listening recovery, server listening statistics, year totals/navigation, and diagnostics redaction/report/share/clear/relaunch persistence. The first nine use this form:

```sh
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/<journey>
```

Diagnostics uses its dedicated presentation fixture ports and verifier:

```sh
ABS_PRESENTATION_SIMULATOR='Pool iPhone 1 (iOS 27.0)' apple/scripts/verify-presentation.sh -only-testing:NativeJourneyTests/PresentationJourney/testDiagnosticsExplainAConnectionFailureWithoutExposingCredentials
```

No new tests were added. The first diagnostics attempt used the wrong verifier and stopped before UI because port 25765 was absent. The dedicated run then exposed an existing singular-query ambiguity: the one error `Label` in `ConnectionViews.swift` contains one `Text(error)` and combines its icon for accessibility, but iOS 27 exposes a nested static wrapper and child with the same identifier and complete label. The existing test now selects `firstMatch`; its error-content, credential redaction and report assertions are unchanged. That same full journey passed afterward. A helper file move overlapped an intermediate year-review compile and reported the obsolete source path missing; regeneration and the isolated rerun passed. Neither failed attempt was waived.

Actual pooled devices were acquired through `sim acquire`, enumerated and opened successfully in the shared Device panel before evidence. Inspected [iPhone PDF with audio controls](iphone-pdf-light.png), [iPhone black settings](iphone-settings-black.png), [iPhone diagnostics](iphone-diagnostics-light.png), [iPad EPUB with dark chrome](ipad-epub-dark-chrome.png), and [iPad reading settings at accessibility-extra-large with Increase Contrast](ipad-reading-settings-large-contrast.png). iPhone captures were exported from passing XCTest attachments. iPad captures use the final installed app through the device CLI and a separate owned fixture on port 27770. The large-text capture shows wrapped native preferences and an opaque outlined page-control fallback. The device CLI's accessibility runner stopped responding after the text-size change; screenshots remained available, so this evidence does not claim additional preference activation or scrolling checks at that size. Device settings were reset and leases released afterward.

The frontend skill's React/TypeScript routing does not apply to these SwiftUI files. Its only grep hits were pre-existing `ConnectionViews.swift:9` (`AccentColor` forced unwrap) and `YearReviewView.swift:35` (the prose “: any” pattern in a comment); no React bars were opened. `git diff --check` passed. Older OS execution, actual VoiceOver speech, full Reduce Transparency/Motion and multitasking coverage, unsigned archives and physical-device behavior remain the comprehensive ticket 228 checks.
