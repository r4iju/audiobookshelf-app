#!/bin/bash
# Discard progress journeys (ProgressResetJourney) against the owned progress reset fixture on 27765:
# apple/scripts/progress_reset_fixture.py over verification/fixture.py.
# Runs the app as built from this checkout on the simulator "Audiobookshelf ResetQA", created on first use.
# Extra arguments pass to xcodebuild.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
project="$apple_root/AudiobookshelfNative.xcodeproj/project.pbxproj"
simulator_name="${ABS_RESET_QA_SIMULATOR:-Audiobookshelf ResetQA}"
work="$(mktemp -d)"
fixture_pid=""
cp "$project" "$work/project.pbxproj"
cleanup() {
    mkdir -p "$apple_root/build-reset"
    curl -s http://127.0.0.1:27765/abs/__reset__/observations > "$apple_root/build-reset/progress-reset-observations.json" 2>/dev/null || true
    [[ -n "$fixture_pid" ]] && { kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; }
    cp "$work/project.pbxproj" "$project"
    rm -rf "$work"
}
trap cleanup EXIT
python3 - <<'PY'
import socket
with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        listener.bind(('127.0.0.1', 27765))
    except OSError:
        raise SystemExit('Fixture port 27765 is already in use. Finish the previous related, item actions or progress reset verification first.')
PY
(cd "$repo_root" && python3 -m unittest apple/scripts/test_progress_reset_fixture.py)
(cd "$repo_root" && exec python3 apple/scripts/progress_reset_fixture.py --port 27765) > "$work/fixture.log" 2>&1 &
fixture_pid=$!
python3 - <<'PY'
import socket, time
for attempt in range(50):
    try:
        with socket.create_connection(('127.0.0.1', 27765), timeout=0.2):
            break
    except OSError:
        time.sleep(0.1)
else:
    raise SystemExit('Progress reset fixture on 27765 did not start.')
PY
simulator="$(xcrun simctl list devices available | sed -n "s/^ *$simulator_name (\([0-9A-F-]*\)).*/\1/p" | head -1)"
if [[ -z "$simulator" ]]; then
    simulator="$(xcrun simctl create "$simulator_name" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
fi
xcodegen generate --spec "$apple_root/project.yml" > /dev/null
TEST_RUNNER_ABS_PROGRESS_RESET_QA=1 xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" -scheme AudiobookshelfNative \
    -destination "id=$simulator" -derivedDataPath "$apple_root/build-reset" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath "${ABS_PROGRESS_RESET_RESULT_BUNDLE:-$apple_root/build-reset/ProgressReset-$(date +%Y%m%d-%H%M%S).xcresult}" \
    -collect-test-diagnostics never -only-testing:NativeJourneyTests/ProgressResetJourney "$@" test
