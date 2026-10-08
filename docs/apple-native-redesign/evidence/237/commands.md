# Verification commands and retained logs

Run from the integration checkout. Frozen runtime is4524ee1635057f581174b4e770339fe995a093cb. Earlier exact source scopes are in RESULT.md and builds-d7/2e records.

```sh
xcodegen generate --spec apple/project.yml
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native237-phone-capture-current CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 build
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=CDFFEB30-07F5-4A50-AB64-57A46709335B -derivedDataPath /tmp/native237-ipad-capture-current CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 build
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination generic/platform=iOS -derivedDataPath /tmp/native237-generic-current CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native237-import-frozen bash apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/PreferencesJourney/testDismissingExportPickerAllowsChoosingAgain -only-testing:NativeJourneyTests/PreferencesJourney/testIncompleteExportShowsAnErrorAndCanBeChosenAgain -only-testing:NativeJourneyTests/PreferencesJourney/testLegacyImportOpensBeforeSigningIntoAServer -only-testing:NativeJourneyTests/PreferencesJourney/testLegacyImportExplainsExportAndReauthentication -resultBundlePath /tmp/237-import-frozen.xcresult
python3 apple/Localization/generate.py --check
```

The harness adds signed simulator flags and build-only15.0. See checks.json for every actual selected test xcodebuild invocation (including diagnostics/presentation and revoked-auth harness), unchanged failures and log SHA256. Build logs are `/tmp/237-phone-build-current.log`, `/tmp/237-ipad-build-current.log`, `/tmp/237-generic-build-current.log`. Earlier cohorts use `-capture` and `-capture-final` DerivedData and corresponding build logs. Source14 argv is a newline-separated argument vector; it was passed directly through Python subprocess, not shell-evaluated. Empty `/tmp/237-source14-current.log` and process exit0 establish only source typecheck.

For every frozen product and its installed bundle:

```sh
codesign --verify --deep --strict --verbose=2 /tmp/native237-phone-capture-current/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app
xcrun simctl get_app_container 75FA9768-B15C-40B6-ACC7-790D7FCAD29C com.forkzed.audiobookshelf.native.preview app
```

The same command is run for Pad and the returned installed paths; Python hashes every file relative to the bundle and asserts complete dictionary equality. Recorded actual output and checks are in builds-*.json. No damaged bundle is re-signed.

Owned capture startup, outside the repository:

```sh
ABS_QA_COVER_DIRECTORY=/tmp/234-covers python3 /tmp/native237-capture-fixture.py
node verification/realtime/native-fixture.mjs 35765 35769
```

`/tmp/native237-capture-state` selects the documented adapter mode. T3 device_list then device_open returned the leased UDID and exact config/session flags; `/tmp/237-capture.py` forwards those flags for each command and records source/product/time/SHA after a settled original screenshot. The phone session was t3-d6ff91d9b9c99b7f2f82a487; Pad t3-05a6735f17a06f07a7d420a3; config `/Users/emanuel/.t3/userdata/device/hosts/25bf8e1a2393f1108d37029b.json`. Raw captures/logs remain/tmp. Cleanup closes/shuts down only those sessions and releases only their two owned leases.
