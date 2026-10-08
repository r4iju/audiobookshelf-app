# Ticket 232: bounded native TV design slice

Production source is `5acca8c1a39cdcf9525e67874583651eef9e6900`, following shell commit `cb8ebda8a3bf45e4a3f519e1f136802c7acffb76`, based on integration `d9e92a4cff92f99db9e3959147f3e80d068450cc`. The native TV shell has Listen Now, Library, Search and Settings, with Now Playing only when applicable. One Library destination owns the selected server library, with every configured library in its native List chooser. Selection and the current stack survive destination changes; choosing a different library starts its own catalog. Existing all-library TV Search, account, listening and storage identities remain authoritative.

The root no longer applies button styling or capsule shapes to its entire descendant tree. Catalog links use native card focus with their content shape. Artwork fits completely inside equal square canvases, including portrait art. The player places transport beside artwork and progress, with a separate compact secondary control row. Native focus makes card metadata primary while focused and secondary otherwise. The focused screenshot exposed the earlier dim author text, so that correction and singular library counts were committed separately and rebuilt before retained final captures. No app source changed after the final capture source above.

## Installed-app verification

| Check | Result |
| --- | --- |
| New twelve-library ShellJourney, before runtime edits | Actual red: native root exposed 10 tab buttons rather than the required 4; before screenshot saved before the assertion |
| Chooser locator replay | Actual red: native List focus belongs to the enclosing Cell, not its inner Button; locator adapted with behavior assertions retained |
| Back observation replay | Actual red from checking focus before the return transition completed; matched existing CatalogJourney's bounded wait for the catalog to reappear, retaining the focus assertion |
| Earlier locator replays | Observed Audiobooks, Podcasts, Home, German Startseite and Arabic Home-label failures before adapting to Library's chooser and Listen Now; behavioral assertions retained |
| Shell, pagination, chapter/leave-player and podcast replay | 4 behavior journeys passed; separate German/Arabic old-label failures were then corrected |
| Representative source `cb8ebda8` replay | **10 tests, 0 failures**: many-library shell, detail/Back, server filters/sort, chapter/leave-player, remote Play/Pause, podcasts, German persistence, Arabic RTL, existing accessibility audit and unsent-listening recovery |
| Final source `5acca8c1` replay | **4 tests, 0 failures**: many-library shell/chooser/Back/all-library Search, detail/Back, remote Play/Pause and unchanged main accessibility audit; retained final focused/unfocused captures |
| TVCore package | **72 tests, 0 failures** |
| Localization package and generated tables | **18 tests, 0 failures**, including a repeat after the final generated copy change; `generate.py --check` passed |
| Final generic tvOS device build | Green, signing disabled; compile evidence only |

The earlier ten-check run preceded only the focused metadata foreground and singular count corrections. Final relevant replays cover the altered visible surfaces and required remote behavior. Concise original excerpts are in `check-results.txt`. Raw XCTest bundles, logs, recordings and attachment exports remain under `/tmp/232-*`, not in Git.

```sh
ABS_QA_COVER_DIRECTORY=/tmp/232-covers \
ABS_TV_QA_SIMULATOR=9ACC6F5B-180D-44C3-823B-F8796813D69D \
ABS_TV_RESULT_BUNDLE=/tmp/232-final-focus-captures.xcresult \
tvos/scripts/verify-ui.sh CODE_SIGN_IDENTITY=- \
  -only-testing:TVJourneyTests/ShellJourney \
  -only-testing:TVJourneyTests/CatalogJourney/testContinueListeningOpensDetailsAndBackRestoresFocus \
  -only-testing:TVJourneyTests/PlaybackJourney/testResumeShowsChapterAndTotalProgressAndRemoteToggles \
  -only-testing:TVJourneyTests/ReadinessJourney/testMainScreensPassTheAccessibilityAudit
xcodebuild -project tvos/AudiobookshelfTV.xcodeproj -scheme AudiobookshelfTV \
  -destination 'generic/platform=tvOS' -derivedDataPath /tmp/232-generic-build \
  CODE_SIGNING_ALLOWED=NO build
swift test --package-path tvos/Core
swift test --package-path apple/Localization
python3 apple/Localization/generate.py --check
```

## Actual screen and artifact evidence

`build-records.json` records source, version 1.0.0(1), unchanged bundle identifier, executable and implementation-library SHA256, minimum version, SDK, Mach-O platform and signing state. Both simulator and generic device binaries have actual minimum **17.0**, matching the retained source minimum. Final simulator builds are ad-hoc signed; the generic device build is unsigned. The installed app and corresponding build product have identical binary hashes. Runtime is pooled Apple TV 4K (3rd generation), **tvOS 27.0 (24J360)**, built with Xcode 27.0 (27A266a). These checks do not establish execution on tvOS17, whose runtime remains unavailable in the known #239 support investigation.

Before screenshots come from the preserved baseline production app and default synthetic cover placeholders. Final screenshots use generated square/portrait synthetic artwork, so the visual before/after is not a same-fixture artwork comparison. The source's fit-versus-crop decision is deliberate: portrait artwork is narrower inside the common canvas, with metadata aligned to equal columns. No Apple artwork or owner media is used. Reproduce the art with `mkdir -p /tmp/232-covers` and `swift fixture-covers/generate.swift /tmp/232-covers` from this evidence directory.

Retained screenshots are actual XCTest rasters at 2048×1152. The final manifest pins each screen to its source and installed binary hashes. They cover the bounded many-library shell, chooser beginning/end, focused/unfocused catalog and Back restoration, square and portrait details, focused/unfocused primary detail controls, focused/unfocused player, and multi-library Search. System text entry and remote Select/Menu/Play-Pause are driven through XCUIRemote and the existing keyboard seam.

T3 device discovery listed the mobile devices and a pooled iPhone was opened in the Device panel. TV is absent from T3's enumerated device list, so TV interaction and capture used the actual pooled tvOS/XCTest platform seam. This is not an alternative-platform execution claim.

React/Next.js frontend bars are inapplicable to SwiftUI. Routing grep on the four changed production Swift files returned no React state/types/data/component matches; no bar was opened. TDD used a meaningful installed-app many-library journey with observed red before implementation. No modifier-mirror or backfilled green tests were added. Capture-only steps were added to existing journeys without removing their assertions. Touched public-facing test commentary now names Listen Now; internal HomeView/TVTab.home names remain unchanged.

## Bounded acceptance and cleanup

No product failure remains identified in the bounded replay. Fresh independent #233 visual review is required. Broader TV content/utilities and long notices remain #238; complete localization/accessibility/durability and actual old-runtime coverage remain #239. New Listen Now, chooser, loading and singular-count labels retain disclosed English fallbacks where untranslated. German/Arabic results establish existing localization, saved choice and RTL behavior, not complete translation of those new labels. Screenshots and AX audits do not prove spoken VoiceOver, viewing-distance hardware acceptance or combined accessibility settings. No mobile offline features, backend runtime changes, identity/storage/auth migration, GPL/origin notice change, Cast/license change, public upload or owner-device install was performed.

Both owned synthetic fixture processes were stopped by verify-ui cleanup. A final bind check found no listener on 20765 or 20767. The owned pooled TV lease was released with `sim release`; `sim list` reports it shutdown and free. No manual simulator clones were created. No push, PR, merge or issue close was performed by this worker. Checkout is clean after the evidence commit.
