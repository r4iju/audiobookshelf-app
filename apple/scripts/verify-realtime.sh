#!/bin/bash
# Runs the realtime journeys on their own loopback ports and simulator, so they can run beside verify-ui.sh.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
fixture_dir="$(mktemp -d)"
fixture_pids=()
cleanup() {
    if (( ${#fixture_pids[@]} > 0 )); then
    for fixture_pid in "${fixture_pids[@]}"; do kill "$fixture_pid" 2>/dev/null || true; done
    for fixture_pid in "${fixture_pids[@]}"; do wait "$fixture_pid" 2>/dev/null || true; done
    fi
    rm -rf "$fixture_dir"
}
trap cleanup EXIT
python3 - <<'PY'
import socket
for port in [26765, 26769]:
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'Fixture port {port} is already in use. Finish the previous owned realtime verification first.')
PY
(cd "$repo_root" && exec python3 -m verification.fixture --port 26769) > "$fixture_dir/http.log" 2>&1 &
fixture_pids+=("$!")
(cd "$repo_root" && exec node verification/realtime/native-fixture.mjs 26765 26769) > "$fixture_dir/realtime.log" 2>&1 &
fixture_pids+=("$!")
python3 - <<'PY'
import socket, time
for port in [26765, 26769]:
    for attempt in range(50):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise SystemExit(f'Synthetic fixture on {port} did not start.')
PY
xcodegen generate --spec "$apple_root/project.yml"
xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" -scheme AudiobookshelfNative \
    -destination "platform=iOS Simulator,name=${ABS_QA_SIMULATOR:-Audiobookshelf Realtime QA}" \
    -derivedDataPath "$apple_root/build" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never \
    -only-testing:NativeJourneyTests/RealtimeJourney "$@" test
