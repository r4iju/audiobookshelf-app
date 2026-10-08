# Checkpoint 233, round 1 corrections

Final runtime source: `8739a7b49b43a11950981eae7ffeb162c43d1ce0` (corrections `da05a80a41aa126a4e0ed99c2bbcecb733f871d1` plus native presentation dismissal `8739a7b4`), from clean integration `23174ab0169f453a21cc00b8c37e8c6cdd8761ef`. Only D1–D3 from `../review-round-1.md` were changed. Independent rendered round 2 remains required; this worker does not declare checkpoint acceptance.

## Corrections

- D1: current phone uses automatic native TabView presentation, a trailing system Search-role Tab with the standard role label, and `searchable` on the TabView. Guarded `tabViewSearchActivation(.searchTabSelection)` accepts input immediately on selecting Search. iPad retains sidebar-adaptable native tabs. One shell-owned LibrarySearchStore owns query/results, debounce, submission, native presented state and selected-library scope. The published ConnectionStore shelf selection synchronizes scope with a same-library guard, preserving query/results during ordinary destination switching. Selecting another destination dismisses the native search presentation, including the tablet software keyboard. Generation cancellation still rejects old requests. iOS15–25 retains the navigation-owned drawer; iOS14 retains UISearchController. No manually fixed search height or recreated search UI.
- D2: wide detail's intrinsic primary listening action sits with title/context beside the artwork. A native ControlGroup holds finish/offline/discard actions; discard has a destructive role and keeps its confirmation. Progress follows this action area. Compact and accessibility layouts retain a vertical action area. Reader, supplementary ebook, podcast, server actions, permissions, recovery and busy states remain on their existing callbacks.
- D3: available listening width selects two native tool groups on normal narrow screens, retaining complete labels/icons and 44pt minimum areas. Wider normal layouts retain four tools; accessibility sizes retain the vertical fallback. No semantic font reduction or individual decorative glass buttons.

Apple primary guidance: [Search and native tab ownership](https://developer.apple.com/videos/play/wwdc2025/323/) (Search chapter); [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). Installed SDK signatures confirmed Search-tab activation is iOS26+. Explicit custom Search-tab title/style alone failed to produce the requested running presentation; actual source-pinned images below establish the resulting composition, not API names alone.

## Red and verification record

The new actual-input tracer was written before activating Search on tab selection. It observed red: “Selecting Search exposes its native input” (22.498s), then green (18.218s in the final committed-source regression). It types and submits without tapping the field, and requires the beyond-first-page result. No modifier, constants, SDK pixel or mirrored tests were added.

Existing Search/Shell journeys also exposed actual regressions during the correction: input absent with placement/style-only changes; podcast Search incorrectly retained Audiobooks scope; native active Search replaced the full tab group, so Listen Now was absent. The scope bug was fixed and episode playback replay passed25.104s. Shell's exit flow was adapted only after the observed red to use the native Close action before switching destination; all selected-library/detail/destination assertions remain and replay passed47.204s. Existing detail/play/download/progress and player tool identifiers were retained. D2/D3 are visual corrections using existing behavioral seams; no tests were backfilled for their layout.

Final source minimum remains iOS14; SDK/toolchain27 builds use build-only iOS15 override. Full76-source target14 Swift5 diagnostic passed (exact argv in `source14-typecheck-command.txt`), which does not establish an iOS14 binary or execution. No TV source/tests, Android/web/backend source, identities or notices were changed. React frontend grep bars are inapplicable to these SwiftUI corrections.

Final committed-source phone replay: **6 tests, 0 failures**, covering all four Search journeys (including immediate native activation), Shell and fractional bookmark deletion. Generic unsigned iOS device build passed with build-only target15. Final same-code wide iPad Shell replay passed **1/1** (35.149s). The prior `da05a80a` iPad run passed bookmark deletion (21.955s) but failed Shell (35.887s): its keyboard remained after selecting Library and obscured the selected-library header. That observed red caused the final presented-state dismissal correction; the selected-library assertion was retained. All intermediate/raw logs, xcresults, UUID exports and videos remain in `/tmp/233-*`; no interim captures are claimed as final source.


## Final actual presentation

All 13 PNGs and screenshot digests in `screenshots.json` are from final source `8739a7b4`, installed with no subsequent runtime edits. Captures use actual T3 devices, the returned agent configuration/session/UDID flags, native snapshot refs, and real software keyboards. Screens are unaltered. Some captures are native-resolution PNGs; later agent captures use its 1x output. No XCTest black-margin rotated attachments or interim images are included.

| Actual capture | State demonstrated |
| --- | --- |
| `iphone-library-search-inactive.png` | Cover-rich Library with four primary tabs and separated trailing native Search |
| `iphone-search-active-keyboard.png` | Selecting native Search, empty focused bottom field above visible software keys |
| `iphone-search-results-keyboard.png` | Typed Tomorrow 61, selected Audiobooks scope, result and software keyboard |
| `iphone-search-submitted.png` | Native keyboard Search/enter submission, retained result, keyboard dismissed |
| `iphone-search-cleared.png` | Native Clear text removes query/result and restores empty-search prompt with keys visible |
| `iphone-search-cancelled.png` | Native Close returns to Library and full destination group |
| `iphone-detail-compact-player.png` | Existing compact phone detail actions and playing/paused native accessory |
| `iphone-player-overview.png` | Artwork, context and primary transport at initial scroll position |
| `iphone-player-tools.png` | Scrolled normal-size phone transport, two native tool groups, complete Bookmarks label, playback settings and Close playback |
| `ipad-library.png` | Wide sidebar, Library context, equal artwork canvases and appropriate native toolbar search |
| `ipad-search-software-keyboard.png` | Wide sidebar Search, native toolbar field and actual empty software keyboard |
| `ipad-search-results-keyboard.png` | Wide Search with Tomorrow 61 result and actual software keyboard |
| `ipad-detail-actions.png` | Artwork/context beside intrinsic Resume action, native finish/offline/destructive-progress group and bounded progress area |

The phone full tab group disappears in active native search mode. A faint rendering of the native collapsed previous-destination button remains beneath the translucent software keyboard at its lower left; it is visible in the unaltered captures and remains for independent round 2 judgment. No custom search/tab/keyboard paint or recreated controls were introduced. The native iPad ControlGroup renders as adjacent text actions; independent review must judge the resulting grouping and hierarchy, rather than infer acceptance from its API. Source-pinned images are review evidence, not declarations of pass.

The player tools require scrolling at this normal phone viewport; the overview and tools frames deliberately document that complete composition. Portrait artwork cropping elsewhere in the existing player remains later ticket235 scope. New mobile translations remain237/239 scope. Full compact-window actions, largest text, spoken VoiceOver and old-OS runtime gates remain required for239; source14 typechecking does not waive them.

## Reproduction and binary provenance

- Final phone: `ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/SearchJourney -only-testing:NativeJourneyTests/ShellJourney -only-testing:NativeJourneyTests/ListeningControlsJourney/testDeletingFractionalBookmarkPreservesItsIntegerNeighbor -resultBundlePath /tmp/233-phone-final-2.xcresult` (final8739; six tests, zero failures).
- iPad dismissal tracer: `ABS_QA_SIMULATOR=CDFFEB30-07F5-4A50-AB64-57A46709335B apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/ShellJourney -resultBundlePath /tmp/233-ipad-dismiss-green.xcresult` (exact final8739 content, committed immediately after this green build; no runtime edit between build and commit).
- Generic: `xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination generic/platform=iOS -derivedDataPath /tmp/233-generic-build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build` (8739, succeeded).
- Diagnostic: exact Swift5 SDK27 source14 command in `source14-typecheck-command.txt`, all76 current mobile/core source files, exit0 (`/tmp/233-source14-final.log`). Not old-OS binary/execution acceptance.
- Real screenshot fixtures: replayed `baseline` then `large-cover-art` on loopback25769, using the same generated synthetic square/portrait covers as231 (`../../231/fixture-covers/generate.swift`, only output directory changed to `/tmp/233-covers`). QA account only; phone loopback19765 and tablet25765 realtime proxies point to this backend. Book01 initially has6sec/30% progress, same baseline case as the earlier comparison; phone playback advances to14sec before pause. No production server or owner library data.
- `simulator-builds.json` records installed executable and debug-library SHA256, version1.0.0/build1, binary minimum15.0, source minimum14, SDK27/runtime iOS27.0 (24A434), and ad hoc signature details. Both installed runtime executable/debug hashes match. Installed tablet bundle signature verification passes. Installed phone and current build product verification report modified `Assets.car`; that signature-resource failure is recorded, not represented as a pass. Runtime code hashes match tablet and the functional phone tests executed successfully. No signature identities or app assets were edited by these corrections.

All captured images were actually viewed. Curated image payload is about2.49MB; raw logs, xcresults, exports and videos remain under `/tmp/233-*`. Independent round2 is pending. No public uploads, TV source/test changes or broader234–237 redesign occurred.

Cleanup: owned Python fixture16156 and realtime proxies19360/42293 stopped; no listeners remain on25769/25765/19765. Both owned phone/tablet leases were released and `sim list` reports them free. Devices remain booted for the T3 stream; no clones were created. Final source tree was unchanged after8739, and only this evidence directory was committed.
