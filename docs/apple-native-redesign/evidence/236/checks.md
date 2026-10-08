# Actual XCTest observations

Logs and raw xcresults remain under `/tmp/236-*`. These are separate runs and overlapping cases, not an aggregate unique-test total. Exact source scopes are in RESULT.md.

## reader-entry-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch" "-only-testing:NativeJourneyTests/ReaderJourney/testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch" -resultBundlePath /tmp/236-reader-entry-red.xcresult test
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:170: error: -[NativeJourneyTests.ReaderJourney testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch] : XCTAssertTrue failed
Test Case '-[NativeJourneyTests.ReaderJourney testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch]' failed (19.085 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:391: error: -[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch] : XCTAssertTrue failed
Test Case '-[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch]' failed (17.894 seconds).
	 Executed 2 tests, with 2 failures (0 unexpected) in 36.979 (36.981) seconds
	 Executed 2 tests, with 2 failures (0 unexpected) in 36.979 (36.982) seconds
	 Executed 2 tests, with 2 failures (0 unexpected) in 36.979 (36.983) seconds
** TEST FAILED **
```

## reader-route-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch" "-only-testing:NativeJourneyTests/ReaderJourney/testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch" -resultBundlePath /tmp/236-reader-route-red.xcresult test
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:175: error: -[NativeJourneyTests.ReaderJourney testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch] : XCTAssertTrue failed
Test Case '-[NativeJourneyTests.ReaderJourney testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch]' failed (18.296 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:396: error: -[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch] : XCTAssertTrue failed
Test Case '-[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch]' failed (17.680 seconds).
	 Executed 2 tests, with 2 failures (0 unexpected) in 35.977 (35.979) seconds
	 Executed 2 tests, with 2 failures (0 unexpected) in 35.977 (35.980) seconds
	 Executed 2 tests, with 2 failures (0 unexpected) in 35.977 (35.980) seconds
** TEST FAILED **
```

## pdf-panel-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch" -resultBundlePath /tmp/236-pdf-panel-red.xcresult test
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:398: error: -[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch] : Failed to tap "Rotate page" Button: No matches found for Elements matching predicate '"Rotate page" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch]' failed (22.736 seconds).
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
** TEST FAILED **
```

## feed-entry-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/PodcastJourney/testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer" -resultBundlePath /tmp/236-feed-entry-red.xcresult test
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/PodcastJourney.swift:106: error: -[NativeJourneyTests.PodcastJourney testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.PodcastJourney testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer]' failed (16.813 seconds).
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
** TEST FAILED **
```

## controls-entry-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch" "-only-testing:NativeJourneyTests/ReaderJourney/testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch" "-only-testing:NativeJourneyTests/PodcastJourney/testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer" "-only-testing:NativeJourneyTests/CollectionJourney/testCreateReorderRemoveAndDeletePlaylistThroughRelaunch" -resultBundlePath /tmp/236-controls-entry-red.xcresult test
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/CollectionJourney.swift:103: error: -[NativeJourneyTests.CollectionJourney testCreateReorderRemoveAndDeletePlaylistThroughRelaunch] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.CollectionJourney testCreateReorderRemoveAndDeletePlaylistThroughRelaunch]' failed (16.557 seconds).
Test Case '-[NativeJourneyTests.PodcastJourney testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer]' passed (26.800 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 26.800 (26.803) seconds
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:186: error: -[NativeJourneyTests.ReaderJourney testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch]' failed (26.461 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:405: error: -[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch]' failed (27.352 seconds).
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
** TEST FAILED **
```

## reader-groups-green

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch" "-only-testing:NativeJourneyTests/ReaderJourney/testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch" "-only-testing:NativeJourneyTests/PodcastJourney/testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer" "-only-testing:NativeJourneyTests/CollectionJourney/testCreateReorderRemoveAndDeletePlaylistThroughRelaunch" -resultBundlePath /tmp/236-reader-groups-green.xcresult test
Test Case '-[NativeJourneyTests.CollectionJourney testCreateReorderRemoveAndDeletePlaylistThroughRelaunch]' passed (44.585 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 44.585 (44.587) seconds
Test Case '-[NativeJourneyTests.PodcastJourney testAdminCanSelectFeedEpisodesAndQueueThemOnTheExistingServer]' passed (26.674 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 26.674 (26.675) seconds
Test Case '-[NativeJourneyTests.ReaderJourney testEPUBChapterLocationSurvivesDownloadedOfflineRelaunch]' passed (36.429 seconds).
Test Case '-[NativeJourneyTests.ReaderJourney testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch]' passed (46.333 seconds).
	 Executed 2 tests, with 0 failures (0 unexpected) in 82.763 (82.764) seconds
	 Executed 4 tests, with 0 failures (0 unexpected) in 154.021 (154.028) seconds
	 Executed 4 tests, with 0 failures (0 unexpected) in 154.021 (154.029) seconds
** TEST SUCCEEDED **
```

## relevant-routes-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference" "-only-testing:NativeJourneyTests/ReaderJourney/testInvalidPDFRecoveryAndLongDocumentPageNavigation" "-only-testing:NativeJourneyTests/ReaderJourney/testEPUBVolumeNavigationPreferencesSurviveRelaunch" "-only-testing:NativeJourneyTests/ReaderJourney/testInvalidEPUBRecoveryOpensLongDocument" "-only-testing:NativeJourneyTests/ReaderJourney/testSupplementaryPDFDownloadsAndRetainsItsOwnPage" "-only-testing:NativeJourneyTests/ReaderJourney/testDownloadedEPUBRemainsReadableWithUnreadableProgressStorage" "-only-testing:NativeJourneyTests/ReaderJourney/testReadingWaitsForPendingAudioAndPreservesBothPositionsOnReconnect" "-only-testing:NativeJourneyTests/ReaderJourney/testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio" "-only-testing:NativeJourneyTests/PodcastJourney/testAdminDiscoversAPodcastByNameAndCreatesTheSelectedFeed" "-only-testing:NativeJourneyTests/PodcastJourney/testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder" "-only-testing:NativeJourneyTests/PodcastJourney/testFailedServerDownloadWhileBrowsingIsRecoveredOnReturningToPodcast" "-only-testing:NativeJourneyTests/CollectionJourney/testPodcastPlaylistRowRetainsSelectedEpisodeForDetailsAndPlayback" "-only-testing:NativeJourneyTests/OfflineJourney" -resultBundlePath /tmp/236-relevant-routes-red.xcresult test
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/CollectionJourney.swift:74: error: -[NativeJourneyTests.CollectionJourney testPodcastPlaylistRowRetainsSelectedEpisodeForDetailsAndPlayback] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.CollectionJourney testPodcastPlaylistRowRetainsSelectedEpisodeForDetailsAndPlayback]' failed (16.638 seconds).
Test Case '-[NativeJourneyTests.OfflineJourney testDownloadedBookPlaysAcrossFilesOfflineAfterRelaunchAndSynchronizesOnReconnect]' passed (45.095 seconds).
Test Case '-[NativeJourneyTests.OfflineJourney testNewerRemoteRewindBecomesTheNextOfflineResumeWithoutRedownloading]' passed (44.610 seconds).
Test Case '-[NativeJourneyTests.OfflineJourney testSuccessfulHTTPErrorPageIsRejectedAndRetryRecoversTheDownload]' passed (28.324 seconds).
	 Executed 3 tests, with 0 failures (0 unexpected) in 118.029 (118.032) seconds
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/PodcastJourney.swift:64: error: -[NativeJourneyTests.PodcastJourney testAdminDiscoversAPodcastByNameAndCreatesTheSelectedFeed] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.PodcastJourney testAdminDiscoversAPodcastByNameAndCreatesTheSelectedFeed]' failed (15.973 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/PodcastJourney.swift:43: error: -[NativeJourneyTests.PodcastJourney testFailedServerDownloadWhileBrowsingIsRecoveredOnReturningToPodcast] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.PodcastJourney testFailedServerDownloadWhileBrowsingIsRecoveredOnReturningToPodcast]' failed (16.420 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/PodcastJourney.swift:155: error: -[NativeJourneyTests.PodcastJourney testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.PodcastJourney testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder]' failed (16.170 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:22: error: -[NativeJourneyTests.ReaderJourney testDownloadedEPUBRemainsReadableWithUnreadableProgressStorage] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testDownloadedEPUBRemainsReadableWithUnreadableProgressStorage]' failed (22.499 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:62: error: -[NativeJourneyTests.ReaderJourney testEPUBVolumeNavigationPreferencesSurviveRelaunch] : XCTAssertEqual failed: ("Optional("0")") is not equal to ("Optional("1")")
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:69: error: -[NativeJourneyTests.ReaderJourney testEPUBVolumeNavigationPreferencesSurviveRelaunch] : XCTAssertEqual failed: ("Optional("0")") is not equal to ("Optional("1")")
Test Case '-[NativeJourneyTests.ReaderJourney testEPUBVolumeNavigationPreferencesSurviveRelaunch]' failed (36.248 seconds).
Test Case '-[NativeJourneyTests.ReaderJourney testInvalidEPUBRecoveryOpensLongDocument]' passed (32.318 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:374: error: -[NativeJourneyTests.ReaderJourney testInvalidPDFRecoveryAndLongDocumentPageNavigation] : XCTAssertTrue failed - Long documents need direct page navigation
Test Case '-[NativeJourneyTests.ReaderJourney testInvalidPDFRecoveryAndLongDocumentPageNavigation]' failed (21.075 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:446: error: -[NativeJourneyTests.ReaderJourney testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio]' failed (17.794 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:291: error: -[NativeJourneyTests.ReaderJourney testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference] : XCTAssertTrue failed
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:292: error: -[NativeJourneyTests.ReaderJourney testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference] : XCTAssertTrue failed - Listening controls must remain reachable while reading
Test Case '-[NativeJourneyTests.ReaderJourney testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference]' failed (30.307 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:332: error: -[NativeJourneyTests.ReaderJourney testReadingWaitsForPendingAudioAndPreservesBothPositionsOnReconnect] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testReadingWaitsForPendingAudioAndPreservesBothPositionsOnReconnect]' failed (17.988 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:208: error: -[NativeJourneyTests.ReaderJourney testSupplementaryPDFDownloadsAndRetainsItsOwnPage] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testSupplementaryPDFDownloadsAndRetainsItsOwnPage]' failed (25.920 seconds).
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
** TEST FAILED **
```

## reader-controls-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference" "-only-testing:NativeJourneyTests/ReaderJourney/testEPUBVolumeNavigationPreferencesSurviveRelaunch" -resultBundlePath /tmp/236-reader-controls-red.xcresult test
Test Case '-[NativeJourneyTests.ReaderJourney testEPUBVolumeNavigationPreferencesSurviveRelaunch]' passed (37.914 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:300: error: -[NativeJourneyTests.ReaderJourney testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference] : Failed to get matching snapshot: No matches found for Descendants matching type Switch from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference]' failed (24.715 seconds).
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
** TEST FAILED **
```

## native-paths-green

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference" "-only-testing:NativeJourneyTests/ReaderJourney/testInvalidPDFRecoveryAndLongDocumentPageNavigation" "-only-testing:NativeJourneyTests/ReaderJourney/testSupplementaryPDFDownloadsAndRetainsItsOwnPage" "-only-testing:NativeJourneyTests/ReaderJourney/testDownloadedEPUBRemainsReadableWithUnreadableProgressStorage" "-only-testing:NativeJourneyTests/ReaderJourney/testReadingWaitsForPendingAudioAndPreservesBothPositionsOnReconnect" "-only-testing:NativeJourneyTests/ReaderJourney/testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio" "-only-testing:NativeJourneyTests/PodcastJourney/testAdminDiscoversAPodcastByNameAndCreatesTheSelectedFeed" "-only-testing:NativeJourneyTests/PodcastJourney/testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder" "-only-testing:NativeJourneyTests/PodcastJourney/testFailedServerDownloadWhileBrowsingIsRecoveredOnReturningToPodcast" "-only-testing:NativeJourneyTests/CollectionJourney/testPodcastPlaylistRowRetainsSelectedEpisodeForDetailsAndPlayback" -resultBundlePath /tmp/236-native-paths-green.xcresult test
Test Case '-[NativeJourneyTests.CollectionJourney testPodcastPlaylistRowRetainsSelectedEpisodeForDetailsAndPlayback]' passed (22.814 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 22.814 (22.817) seconds
Test Case '-[NativeJourneyTests.PodcastJourney testAdminDiscoversAPodcastByNameAndCreatesTheSelectedFeed]' passed (26.898 seconds).
Test Case '-[NativeJourneyTests.PodcastJourney testFailedServerDownloadWhileBrowsingIsRecoveredOnReturningToPodcast]' passed (24.762 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/PodcastJourney.swift:156: error: -[NativeJourneyTests.PodcastJourney testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.PodcastJourney testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder]' failed (17.158 seconds).
Test Case '-[NativeJourneyTests.ReaderJourney testDownloadedEPUBRemainsReadableWithUnreadableProgressStorage]' passed (32.282 seconds).
Test Case '-[NativeJourneyTests.ReaderJourney testInvalidPDFRecoveryAndLongDocumentPageNavigation]' passed (27.369 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/ReaderJourney.swift:454: error: -[NativeJourneyTests.ReaderJourney testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio] : Failed to tap "Done" Button: No matches found for Elements matching predicate '"Done" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.ReaderJourney testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio]' failed (20.536 seconds).
Test Case '-[NativeJourneyTests.ReaderJourney testPDFReadingKeepsAudioPlayingAndRetainsDisplayPreference]' passed (33.782 seconds).
Test Case '-[NativeJourneyTests.ReaderJourney testReadingWaitsForPendingAudioAndPreservesBothPositionsOnReconnect]' passed (45.795 seconds).
Test Case '-[NativeJourneyTests.ReaderJourney testSupplementaryPDFDownloadsAndRetainsItsOwnPage]' passed (34.540 seconds).
	 Executed 3 tests, with 0 failures (0 unexpected) in 114.117 (114.120) seconds
	 Executed 3 tests, with 0 failures (0 unexpected) in 114.117 (114.121) seconds
	 Executed 3 tests, with 0 failures (0 unexpected) in 114.117 (114.122) seconds
** TEST FAILED **
```

## final-two

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-red CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/PodcastJourney/testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder" "-only-testing:NativeJourneyTests/ReaderJourney/testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio" -resultBundlePath /tmp/236-final-two.xcresult test
Test Case '-[NativeJourneyTests.PodcastJourney testPodcastCreationRequiresAdminAndUsesTheSelectedServerFolder]' passed (31.914 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 31.914 (31.916) seconds
Test Case '-[NativeJourneyTests.ReaderJourney testOriginalPDFOrientationAndEbookUpgradeRetainDownloadedAudio]' passed (35.081 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 35.081 (35.082) seconds
	 Executed 2 tests, with 0 failures (0 unexpected) in 66.995 (67.000) seconds
	 Executed 2 tests, with 0 failures (0 unexpected) in 66.995 (67.001) seconds
** TEST SUCCEEDED **
```

## group-permissions-red

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/build-remaining-qa.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /Volumes/ai-ssd/code/leafwake-fullstack/apple/build-remaining-qa/derived CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath "/Volumes/ai-ssd/code/leafwake-fullstack/apple/build-remaining-qa/results/Pool-iPhone-1-(iOS-27.0)-20261008-143955.xcresult" -collect-test-diagnostics never "-only-testing:NativeJourneyTests/RemainingQAGroupJourney" test
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/RemainingQAJourney.swift:37: error: -[NativeJourneyTests.RemainingQAGroupJourney testAdminWithoutDeletePermissionIsNotOfferedCollectionDeletion] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.RemainingQAGroupJourney testAdminWithoutDeletePermissionIsNotOfferedCollectionDeletion]' failed (16.514 seconds).
/Volumes/ai-ssd/code/leafwake-fullstack/apple/UITests/RemainingQAJourney.swift:37: error: -[NativeJourneyTests.RemainingQAGroupJourney testServerRejectedCollectionEditSaysTheAccountIsNotAllowedAndSavesNothing] : Failed to tap "account" Button: No matches found for Elements matching predicate '"account" IN identifiers' from input {(
Test Case '-[NativeJourneyTests.RemainingQAGroupJourney testServerRejectedCollectionEditSaysTheAccountIsNotAllowedAndSavesNothing]' failed (16.079 seconds).
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
** TEST FAILED **
```

## group-permissions-green

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/build-remaining-qa.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /Volumes/ai-ssd/code/leafwake-fullstack/apple/build-remaining-qa/derived CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath "/Volumes/ai-ssd/code/leafwake-fullstack/apple/build-remaining-qa/results/Pool-iPhone-1-(iOS-27.0)-20261008-144105.xcresult" -collect-test-diagnostics never "-only-testing:NativeJourneyTests/RemainingQAGroupJourney" test
Test Case '-[NativeJourneyTests.RemainingQAGroupJourney testAdminWithoutDeletePermissionIsNotOfferedCollectionDeletion]' passed (20.063 seconds).
Test Case '-[NativeJourneyTests.RemainingQAGroupJourney testServerRejectedCollectionEditSaysTheAccountIsNotAllowedAndSavesNothing]' passed (20.792 seconds).
	 Executed 2 tests, with 0 failures (0 unexpected) in 40.855 (40.859) seconds
	 Executed 2 tests, with 0 failures (0 unexpected) in 40.855 (40.860) seconds
	 Executed 2 tests, with 0 failures (0 unexpected) in 40.855 (40.862) seconds
** TEST SUCCEEDED **
```

## pad-final

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=CDFFEB30-07F5-4A50-AB64-57A46709335B -derivedDataPath /tmp/native236-ipad-tests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ShellJourney" "-only-testing:NativeJourneyTests/CollectionJourney/testCreateReorderRemoveAndDeletePlaylistThroughRelaunch" -resultBundlePath /tmp/236-pad-final.xcresult test
Test Case '-[NativeJourneyTests.CollectionJourney testCreateReorderRemoveAndDeletePlaylistThroughRelaunch]' passed (45.920 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 45.920 (45.924) seconds
Test Case '-[NativeJourneyTests.ShellJourney testDestinationsKeepLibrarySelectionAndDetailsWhileBrowsing]' passed (34.800 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 34.800 (34.801) seconds
	 Executed 2 tests, with 0 failures (0 unexpected) in 80.721 (80.726) seconds
	 Executed 2 tests, with 0 failures (0 unexpected) in 80.721 (80.728) seconds
** TEST SUCCEEDED **
```

## corrected-paths-green

```text
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project /Volumes/ai-ssd/code/leafwake-fullstack/apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination id=75FA9768-B15C-40B6-ACC7-790D7FCAD29C -derivedDataPath /tmp/native236-phone-corrected-tests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "-only-testing:NativeJourneyTests/ReaderJourney/testInvalidPDFRecoveryAndLongDocumentPageNavigation" "-only-testing:NativeJourneyTests/OfflineJourney/testDownloadedAudioRejectsAHTTP200ErrorPageAndRetries" test
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Case '-[NativeJourneyTests.ReaderJourney testInvalidPDFRecoveryAndLongDocumentPageNavigation]' passed (28.763 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 28.763 (28.768) seconds
	 Executed 1 test, with 0 failures (0 unexpected) in 28.763 (28.769) seconds
	 Executed 1 test, with 0 failures (0 unexpected) in 28.763 (28.771) seconds
** TEST SUCCEEDED **
```
