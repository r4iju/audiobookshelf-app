#!/bin/bash
set -euo pipefail
cd /Users/emanuel/code/leafwake-fullstack
xcrun simctl install 9ACC6F5B-180D-44C3-823B-F8796813D69D /tmp/native238-capture-17869645/Build/Products/Debug-appletvsimulator/AudiobookshelfTV.app
python3 /tmp/native238-checkpoint.py tv_capture before-corrected-render-pass
ABS_QA_COVER_DIRECTORY=/tmp/232-covers python3 /tmp/native238-capture-fixture.py 33775 >/tmp/238-capture-recheck-fixture.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true' EXIT
python3 -c 'import socket,time; time.sleep(.3); socket.create_connection(("127.0.0.1",33775),timeout=2).close()'
TEST_RUNNER_ABS_TV_HTTP_PORT=33775 TEST_RUNNER_ABS_TV_HTTPS_PORT=33777 xcodebuild -project tvos/AudiobookshelfTV.xcodeproj -scheme AudiobookshelfTV -configuration Debug -destination id=9ACC6F5B-180D-44C3-823B-F8796813D69D -derivedDataPath /tmp/native238-capture-17869645 -resultBundlePath /tmp/238-capture-recheck-17869645.xcresult -collect-test-diagnostics never \
-only-testing:TVJourneyTests/CaptureRecoveryJourney/testMediaFailureOffersRestartRatherThanSavingProgress \
-only-testing:TVJourneyTests/CaptureRecoveryJourney/testUnsentListeningSurvivesTerminationAndSyncsOnRelaunch \
-only-testing:TVJourneyTests/LongInspectionJourney/testRenderLongMetadata \
-only-testing:TVJourneyTests/RenderJourney/testRenderAuthenticationRecoveryAlertAndKeyboard \
-only-testing:TVJourneyTests/RenderJourney/testRenderDetailLoadingFailureAndLibraryEmpty \
-only-testing:TVJourneyTests/RenderJourney/testRenderLibrarySortFilter \
-only-testing:TVJourneyTests/RenderJourney/testRenderMissingArtworkAndEmptyPodcast \
-only-testing:TVJourneyTests/RenderJourney/testRenderNativeSettingsLanguageAndNotices \
-only-testing:TVJourneyTests/RenderJourney/testRenderPodcastAndEpisode \
-only-testing:TVJourneyTests/RenderJourney/testRenderCatalogFailureAndRetry test-without-building > /tmp/238-capture-recheck-17869645.log 2>&1
python3 /tmp/native238-checkpoint.py tv_capture after-corrected-render-pass
