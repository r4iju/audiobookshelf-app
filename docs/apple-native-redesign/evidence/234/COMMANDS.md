# Verification and capture commands

All commands ran from `/Users/emanuel/code/leafwake-fullstack`. Raw results remain under `/tmp/234-*`; per-case outcomes are in checks.json. Pooled devices were leased, never cloned. Existing verification/realtime/node_modules was reused; the obsolete root Nuxt install was not run.

```sh
# Source2f phone selected15
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native234-phone-final apple/scripts/verify-ui.sh  -only-testing:NativeJourneyTests/ConnectionJourney/testConnectSelectLibraryAndRestoreAccountAfterRelaunch  -only-testing:NativeJourneyTests/ConnectionJourney/testBrowsePaginatedBooksAndExpandedMetadata  -only-testing:NativeJourneyTests/ConnectionJourney/testContinueListeningIncludesBookOutsideFirstCatalogPage  -only-testing:NativeJourneyTests/ArtworkJourney -only-testing:NativeJourneyTests/SearchJourney  -only-testing:NativeJourneyTests/CatalogRecoveryJourney -only-testing:NativeJourneyTests/ShellJourney  -only-testing:NativeJourneyTests/PodcastJourney/testEpisodeCompletionPersistsAndFiltersThePodcastList  -only-testing:NativeJourneyTests/PodcastJourney/testPodcastEpisodeSelectionKeepsIndependentProgressThroughRelaunch  -resultBundlePath /tmp/234-phone-final.xcresult

# Source2f tablet selected3 (Shell establishes landscape)
ABS_QA_SIMULATOR=CDFFEB30-07F5-4A50-AB64-57A46709335B ABS_QA_DERIVED_DATA=/tmp/native234-ipad-final apple/scripts/verify-ui.sh  -only-testing:NativeJourneyTests/CatalogRecoveryJourney/testLongMetadataAndMissingArtworkRemainNavigableForReadOnlyAccount  -only-testing:NativeJourneyTests/ConnectionJourney/testBrowsePaginatedBooksAndExpandedMetadata  -only-testing:NativeJourneyTests/ShellJourney -resultBundlePath /tmp/234-ipad-final.xcresult

ABS_RELATED_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native234-phone-final ABS_ITEM_ACTIONS_RESULT_BUNDLE=/tmp/234-item-actions-modal-green.xcresult apple/scripts/verify-item-actions.sh
ABS_RESET_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native234-phone-final ABS_PROGRESS_RESET_RESULT_BUNDLE=/tmp/234-progress-recovery-green.xcresult apple/scripts/verify-progress-reset.sh
ABS_RELATED_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native234-phone-final ABS_RELATED_RESULT_BUNDLE=/tmp/234-related-pinned-final.xcresult apple/scripts/verify-related.sh
ABS_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native234-phone-final apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/CollectionJourney/testEstablishedCollectionAndPlaylistPlayInTheirOwnOrder -resultBundlePath /tmp/234-group-order-green.xcresult

# Successful isolated Cancel diagnostic: skip the other three, because class+method only-testing is a union.
ABS_RESET_QA_SIMULATOR=75FA9768-B15C-40B6-ACC7-790D7FCAD29C ABS_QA_DERIVED_DATA=/tmp/native234-phone-final ABS_PROGRESS_RESET_RESULT_BUNDLE=/tmp/234-cancel-only.xcresult apple/scripts/verify-progress-reset.sh  -skip-testing:NativeJourneyTests/ProgressResetJourney/testAConfirmedBookResetRemovesItsProgressAndPlaysFromTheStart  -skip-testing:NativeJourneyTests/ProgressResetJourney/testAConfirmedEpisodeResetRemovesOnlyThatEpisodesProgress  -skip-testing:NativeJourneyTests/ProgressResetJourney/testAFailedResetIsReportedAndDiscardingAgainSucceeds

# Fresh per-device capture products, after committing runtime b703
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 build -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native234-phone-verified-final
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 build -destination id=CDFFEB30-07F5-4A50-AB64-57A46709335B -derivedDataPath /tmp/native234-ipad-verified-final
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination generic/platform=iOS -derivedDataPath /tmp/native234-generic CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build
# Exact source14 diagnostic argv (one argument per line): source14-typecheck-command.txt, invoked via Python subprocess.run.

codesign --verify --deep --strict --verbose=2 /tmp/native234-phone-verified-final/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app
codesign --verify --deep --strict --verbose=2 /tmp/native234-ipad-verified-final/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app
xcrun simctl install 75FA9768-B15C-40B6-ACC7-790D7FCAD29C /tmp/native234-phone-verified-final/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app
xcrun simctl install CDFFEB30-07F5-4A50-AB64-57A46709335B /tmp/native234-ipad-verified-final/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app
# get_app_container identifies installed bundles; strict verification and SHA256 of every file compare them with products before/after capture (builds.json).

ABS_QA_COVER_DIRECTORY=/tmp/234-covers python3 /tmp/native234-capture-fixture.py
node verification/realtime/native-fixture.mjs 25765 25769
# configure POST /abs/__fixture__/configure modes: baseline, large-cover-art, edge-metadata, empty, catalog-error.
# Owned control file /tmp/native234-capture-state: normal, loading, search-failure, valid-long-metadata.
```

T3 device_list and device_open supplied these exact CLI target flags, retained for all interactions:

```text
/Users/emanuel/.t3/userdata/device/bin/agent-device <command> --platform ios --udid 75FA9768-B15C-40B6-ACC7-790D7FCAD29C --config /Users/emanuel/.t3/userdata/device/hosts/25bf8e1a2393f1108d37029b.json --session t3-d6ff91d9b9c99b7f2f82a487
/Users/emanuel/.t3/userdata/device/bin/agent-device <command> --platform ios --udid CDFFEB30-07F5-4A50-AB64-57A46709335B --config /Users/emanuel/.t3/userdata/device/hosts/25bf8e1a2393f1108d37029b.json --session t3-05a6735f17a06f07a7d420a3
```

Flows use snapshot refs, click/fill/scroll --settle, keyboard enter/dismiss and screenshot. The final31 image hashes/cases are in captures.json. No missing keyboard was labelled visible. Native phone Close restored the open Library series. No private owner data or production NAS was contacted. Raw agent sessions/diagnostics remain local temporary evidence, not bulk Git exports.
