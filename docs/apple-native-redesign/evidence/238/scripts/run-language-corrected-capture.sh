#!/bin/bash
set -euo pipefail
cd /Users/emanuel/code/leafwake-fullstack
xcrun simctl install 9ACC6F5B-180D-44C3-823B-F8796813D69D /tmp/native238-capture-7c69/Build/Products/Debug-appletvsimulator/AudiobookshelfTV.app
python3 /tmp/native238-checkpoint.py tv_settings_capture before-correct-language-render
ABS_QA_COVER_DIRECTORY=/tmp/232-covers python3 /tmp/native238-capture-fixture.py 33775 >/tmp/238-capture-7c69-fixture.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true' EXIT
python3 -c 'import socket,time; time.sleep(.3); socket.create_connection(("127.0.0.1",33775),timeout=2).close()'
TEST_RUNNER_ABS_TV_HTTP_PORT=33775 TEST_RUNNER_ABS_TV_HTTPS_PORT=33777 xcodebuild -project tvos/AudiobookshelfTV.xcodeproj -scheme AudiobookshelfTV -configuration Debug -destination id=9ACC6F5B-180D-44C3-823B-F8796813D69D -derivedDataPath /tmp/native238-capture-7c69 -resultBundlePath /tmp/238-capture-7c69-language.xcresult -collect-test-diagnostics never -only-testing:TVJourneyTests/RenderJourney/testRenderNativeSettingsLanguageAndNotices test-without-building > /tmp/238-capture-7c69-language.log 2>&1
python3 /tmp/native238-checkpoint.py tv_settings_capture after-correct-language-render
