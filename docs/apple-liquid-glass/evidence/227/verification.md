# Ticket 227 verification

Source starts at `c71029352e6464f470f98f5de03d5d1b524c30a0` on `feature/apple-liquid-glass`; ancestry verified before editing. Xcode 27.0 (27A266a), pooled Apple TV simulator `9ACC6F5B-180D-44C3-823B-F8796813D69D`, tvOS 27.0.

The native TabView now includes platform symbols. All browsing, search, related links, detail actions, player menus and settings controls inherit the shared native bordered button presentation with capsule borders. Explicit card styles continue to keep cover tiles as content with native card focus. Library titles and counts have a separate row from sort/filter controls, avoiding competition for width. Transport and listening options are centered, the primary playback action has a larger target, and settings sections use quiet dividers rather than glass content cards. Language and Diagnostics precede long server/license text, with full-width native focus sections so remote focus can enter from the tab bar. Listening and the focusable Account action follow the notices, keeping that content reachable while preserving all disclosures. Playback, stores, authentication, localization and accessibility identifiers remain unchanged.

The system applies Liquid Glass to standard TV controls when focused on OS 26+ and supported hardware. This follows the public [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) guidance and the focus experiment documented in [ticket 223](../223/verification.md). The existing `nativeGlassButton` TV branch intentionally uses `.bordered` rather than the explicit glass styles that failed remote activation in that experiment. Native focus semantics and system accessibility treatment are preserved; no custom focusable overlays or glass backgrounds surround artwork, descriptions, settings prose or other long content. No additional custom glass surface is needed here. The source minimum remains tvOS 17.0 and older hardware/OS uses the standard bordered fallback. No older OS or physical TV hardware execution is claimed.

No new tests were added. The existing German UI journey expected the English accessibility value `Selected` after changing the interface to German; the observed failure returned the correct localized `Ausgewählt`. That stale expected value was corrected after observing the failing run. Verification uses existing externally observable Siri Remote journeys and fresh owned loopback fixtures. JavaScript dependencies are already installed, but this TV-only task uses Xcode's self-contained native app and Core sources. The frontend skill's React/TypeScript rules do not apply to SwiftUI.

Passed simulator build:

```sh
xcodebuild -project tvos/AudiobookshelfTV.xcodeproj -scheme AudiobookshelfTV -destination 'generic/platform=tvOS Simulator' -derivedDataPath tvos/build CODE_SIGNING_ALLOWED=NO build
```

The verifier's deterministic XcodeGen output adds the existing portable shared `NativeNavigation.swift` to the TV project. No shared presentation source or mobile runtime was edited.

Verification found and fixed two presentation regressions before final evidence: inherited capsule borders clipped card titles/artwork, so every card now explicitly uses its native rounded rectangle shape; remote focus could not reach Settings actions below long informational text, so Apple TV actions now lead the screen and focus sections span its content width. Existing Back/focus and Settings navigation journeys verify these corrections.

The final catalog/player/recovery source passed these seven existing journeys in `/tmp/liquid-glass-227-final.xcresult` (the stale/failing Settings journey in that bundle was corrected and rerun separately):

```sh
ABS_TV_QA_SIMULATOR=9ACC6F5B-180D-44C3-823B-F8796813D69D ABS_TV_RESULT_BUNDLE=/tmp/liquid-glass-227-final.xcresult tvos/scripts/verify-ui.sh \
  -only-testing:TVJourneyTests/CatalogJourney/testContinueListeningOpensDetailsAndBackRestoresFocus \
  -only-testing:TVJourneyTests/CatalogJourney/testServerSearchFindsTitlesOutsideLoadedPage \
  -only-testing:TVJourneyTests/CatalogJourney/testFilterAndSortAreAppliedByTheServer \
  -only-testing:TVJourneyTests/RelatedJourney/testSearchOpensAuthorWithBioSeriesAndEveryBook \
  -only-testing:TVJourneyTests/RelatedJourney/testSeriesFollowsServerSequenceAndOpensTheIntendedBook \
  -only-testing:TVJourneyTests/PlaybackJourney/testResumeShowsChapterAndTotalProgressAndRemoteToggles \
  -only-testing:TVJourneyTests/ReadinessJourney/testGermanLocalizesTheInterfaceAndPersists \
  -only-testing:TVJourneyTests/RecoveryJourney/testSigningInAgainShowsTheWholeFormAndSendsTheHeldListeningWithoutPlaying
```

Final settings runtime passed `ReadinessJourney/testCatalogFailureIsRecordedAndClearedFromSettings` in `/tmp/liquid-glass-227-settings-final.xcresult`, including entry to Diagnostics, clearing, Back and focus restoration. Its German case then reached the localized selected-value assertion, exposing the stale expectation described above.

```sh
ABS_TV_QA_SIMULATOR=9ACC6F5B-180D-44C3-823B-F8796813D69D ABS_TV_RESULT_BUNDLE=/tmp/liquid-glass-227-settings-final.xcresult tvos/scripts/verify-ui.sh \
  -only-testing:TVJourneyTests/ReadinessJourney/testGermanLocalizesTheInterfaceAndPersists \
  -only-testing:TVJourneyTests/ReadinessJourney/testCatalogFailureIsRecordedAndClearedFromSettings
ABS_TV_QA_SIMULATOR=9ACC6F5B-180D-44C3-823B-F8796813D69D ABS_TV_RESULT_BUNDLE=/tmp/liquid-glass-227-german-final.xcresult tvos/scripts/verify-ui.sh \
  -only-testing:TVJourneyTests/ReadinessJourney/testGermanLocalizesTheInterfaceAndPersists
```

Actual screenshots exported from retained XCTest attachments with `xcrun xcresulttool export attachments`: [focused detail action](detail.png), [focused sort control and rectangular library cards](filtered.png), [search](search.png), [author](author.png), [focused series card](series.png), [player](now-playing.png), [focused player transport after recovery](player-focused-control.png), [full credential recovery](credential-recovery.png), and final Settings evidence below. All catalog/player images reflect final view source; the subsequent runtime edit affected only Settings.

The shared Device panel does not enumerate TV, so screenshots and interaction evidence come from the pooled simulator and Siri Remote driven XCTest. Physical Apple TV glass rendering and hardware capability gating, older OS execution, comprehensive accessibility/appearance settings, and unsigned device archives are not claimed here. Ticket 228 owns those broader branch checks. Xcode emitted a system `_UIReplicantView` hosting warning during native menu/presentation transitions; no corresponding remote assertion failed in the final passing selections.


Final German rerun passed (1 test, 0 failures), including native language accessibility audit, Back focus restoration, retained Account section, persistence across relaunch, localized book action and returning to system language. [Focused localized Settings](settings-german.png) shows the final action-first layout. Nine distinct selected journeys passed across the final relevant bundles. Simulator released after screenshots.
