# Ticket235 commands

From the shared checkout, pooled phone75FA9768-B15C-40B6-ACC7-790D7FCAD29C and tabletCDFFEB30-07F5-4A50-AB64-57A46709335B were acquired with sim acquire iphone/ipad --os27 --for "native235 listening" --hours4. T3 device_list then device_open returned these exact interaction targets:

```text
/Users/emanuel/.t3/userdata/device/bin/agent-device <command> --platform ios --udid 75FA9768-B15C-40B6-ACC7-790D7FCAD29C --config /Users/emanuel/.t3/userdata/device/hosts/25bf8e1a2393f1108d37029b.json --session t3-d6ff91d9b9c99b7f2f82a487
/Users/emanuel/.t3/userdata/device/bin/agent-device <command> --platform ios --udid CDFFEB30-07F5-4A50-AB64-57A46709335B --config /Users/emanuel/.t3/userdata/device/hosts/25bf8e1a2393f1108d37029b.json --session t3-05a6735f17a06f07a7d420a3
```

The /tmp/235-capture.py wrapper forwards these arguments unchanged for open, snapshot, click, fill, scroll, orientation, keyboard, screenshot. Its screenshot manifest records source, device, time and SHA256; only curated frames enter captures.json. Source0b was committed before isolated final builds/captures. The dedicated leased fixture app’s existing --reset-preview-account seam reset only owned synthetic QA data; no owner account or NAS calls.

```sh
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native235-phone-tests apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/OfflineJourney/testDownloadedBookPlaysAcrossFilesOfflineAfterRelaunchAndSynchronizesOnReconnect -resultBundlePath /tmp/235-offline-entry-red.xcresult
# Adapt first observed obsolete locator only, then remaining two observed actual reds:
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native235-phone-tests apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/OfflineJourney -resultBundlePath /tmp/235-offline-routes.xcresult
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native235-phone-tests apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/ListeningControlsJourney -only-testing:NativeJourneyTests/OfflineJourney -only-testing:NativeJourneyTests/PlaybackJourney/testMediaHTTPFailureShowsErrorAndCanBeReopened -only-testing:NativeJourneyTests/DurableProgressJourney/testUnsentListeningSurvivesTerminationAndRestoresServerProgress -resultBundlePath /tmp/235-listening-green.xcresult
ABS_PRESENTATION_SIMULATOR='Pool iPad 1 (iOS 27.0)' ABS_QA_DERIVED_DATA=/tmp/native235-ipad-tests apple/scripts/verify-presentation.sh -only-testing:NativeJourneyTests/PresentationJourney/testChapterTrackFollowsTheChapterWithTheTotalTrackAlongside -only-testing:NativeJourneyTests/PresentationJourney/testElapsedTimeScalesWithPlaybackSpeedUntilTurnedOff -only-testing:NativeJourneyTests/PresentationJourney/testLockedPlayerPreventsAccidentalSeekingUntilUnlocked -only-testing:NativeJourneyTests/PresentationJourney/testAccessibilityTextSizeKeepsPlayerControlsOnScreen -resultBundlePath /tmp/235-presentation-ipad.xcresult
ABS_PLAYBACK_QA_SCHEME=AudiobookshelfNative ABS_PLAYBACK_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_PLAYBACK_QA_DERIVED_DATA=/tmp/native235-auth-final apple/scripts/verify-playback-authorization.sh -only-testing:NativeJourneyTests/PlaybackAuthorizationJourney -resultBundlePath /tmp/235-auth-final.xcresult

xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native235-phone-capture-0b4733e6 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 build
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=CDFFEB30-07F5-4A50-AB64-57A46709335B -derivedDataPath /tmp/native235-ipad-capture-0b4733e6 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 build
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination generic/platform=iOS -derivedDataPath /tmp/native235-generic-0b4733e6 CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
# Full source14 argv is one argument per line in source14-typecheck-command.txt, invoked via subprocess.run; exit0,76 sources.
```

Product and installed paths/hashes are in builds.json. Each verification used codesign --verify --deep --strict --verbose=2, and SHA256 of every bundle file. simctl install/get_app_container located and compared the actual installed products. No re-signing.

Owned capture fixture: ABS_QA_COVER_DIRECTORY=/tmp/235-covers python3 /tmp/235-capture-fixture.py (25769), node verification/realtime/native-fixture.mjs 25765 25769. Baseline/long-audio/broken-audio modes, real synthetic bookmark operations and qa revocation/reauthentication use the existing loopback protocol. capture-fixture.py documents only api/me503 and cover404 presentation states. Cover mapping/hashes are in fixture.json. No runtime overrides of playback/domain/media/preferences.
