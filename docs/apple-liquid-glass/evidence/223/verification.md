# Ticket 223 verification

Source starts at `4af5aae0` on `feature/apple-liquid-glass`. Xcode 27.0 (27A266a), iOS/tvOS 27 pooled simulators. Authentication, account storage, APIs, localization strings and accessibility identifiers are preserved. No new tests were added.

The mobile connection screen uses native navigation and Form sections, a width-limited adaptive layout and one custom `glassEffect` Connect control. Loading uses a system progress indicator and native glass action. Custom controls choose opaque fill for Reduce Transparency or increased contrast, disable their interactive glass motion for Reduce Motion and suppress explicit animation transactions. TV uses native bordered buttons so system glass follows focus and hardware support while retaining remote activation. Source minimums remain iOS 14 and tvOS 17.

Public Apple references verified against the installed SDK:

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), standard controls adopt the material, accessibility adapts automatically, and TV glass depends on focus and supported hardware.
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), `glassEffect`, tint and interactive effects.

Passed builds:

```sh
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination 'generic/platform=iOS Simulator' -derivedDataPath apple/build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
xcodebuild -project tvos/AudiobookshelfTV.xcodeproj -scheme AudiobookshelfTV -destination 'generic/platform=tvOS Simulator' -derivedDataPath tvos/build CODE_SIGNING_ALLOWED=NO build
```

Xcode 27 rejects a simulator build target of iOS 14; the existing verifier's build-only iOS 15 override is retained. This does not raise the source deployment target.

Passed existing UI journeys, using owned loopback fixtures:

```sh
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/ConnectionJourney/testInvalidServerShowsRecoveryWithoutLeavingConnectionForm -only-testing:NativeJourneyTests/ConnectionJourney/testConnectSelectLibraryAndRestoreAccountAfterRelaunch -only-testing:NativeJourneyTests/OpenIDJourney/testChangedAuthorizationStateIsRejectedBeforeOpeningBrowser
ABS_TV_QA_SIMULATOR=9ACC6F5B-180D-44C3-823B-F8796813D69D tvos/scripts/verify-ui.sh -only-testing:TVJourneyTests/ReadinessJourney/testFailedSignInIsDiagnosedWithoutCredentials -only-testing:TVJourneyTests/RecoveryJourney/testSigningInAgainShowsTheWholeFormAndSendsTheHeldListeningWithoutPlaying
```

Mobile: 3 tests, 0 failures. TV: 2 tests, 0 failures, including remote navigation, diagnostics, Back, credential recovery and held listening. Result bundles: `apple/build/Logs/Test/Test-AudiobookshelfNative-2026.10.06_23-16-15-+0900.xcresult` and `tvos/build/TVJourneys-20261006-231753.xcresult`.

The Apple verifier now requires `dev.nginx.lan` only when its qualified-host test is selected (or no test selection is supplied), allowing focused loopback-only journeys without changing system DNS. Explicit TV glass button styles failed remote focus/activation checks during development; the final native bordered style passed both journeys.

Inspected actual [iPhone light](iphone-light.png), [iPad dark](ipad-dark.png) and [TV credential recovery](tv-credential-recovery.png) screens. iPhone/iPad were opened in the shared Device panel; that panel does not enumerate TV, so TV evidence comes from the remote-driven XCTest journey. All simulators were leased from the pool. Full accessibility settings, iPad multitasking size coverage, older OS execution, physical TV hardware and unsigned archives remain for ticket 228.
