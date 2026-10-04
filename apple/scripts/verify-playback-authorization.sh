#!/bin/bash
# Token renewal and server-side revocation during real playback (PlaybackAuthorizationTests) and the
# reauthentication journey (PlaybackAuthorizationJourney), against verification/fixture.py on 51769.
# Runs on the simulator "Audiobookshelf PlaybackFinal iPhone QA", leased from the shared pool. Extra arguments
# pass to xcodebuild, for example -only-testing:NativeTests/PlaybackAuthorizationTests.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
port=51769
project="$apple_root/AudiobookshelfNative.xcodeproj/project.pbxproj"
derived="${ABS_PLAYBACK_QA_DERIVED_DATA:-$apple_root/build-playback-authorization}"
work="$(mktemp -d)"
fixture_pid=""
leased_simulator=""
cp "$project" "$work/project.pbxproj"
cleanup() {
    if [[ -n "$leased_simulator" ]]; then sim release "$leased_simulator" || true; fi
    mkdir -p "$derived"
    curl -s "http://127.0.0.1:$port/abs/__fixture__/observations" > "$derived/playback-authorization-observations.json" 2>/dev/null || true
    [[ -n "$fixture_pid" ]] && { kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; }
    cp "$work/project.pbxproj" "$project"
    rm -rf "$work"
}
trap cleanup EXIT
python3 - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        listener.bind(('127.0.0.1', port))
    except OSError:
        raise SystemExit(f'Fixture port {port} is already in use. Finish the previous playback authorization verification first.')
PY
(cd "$repo_root" && python3 -m unittest verification.test_fixture)
(cd "$repo_root" && exec python3 -m verification.fixture --port "$port") > "$work/fixture.log" 2>&1 &
fixture_pid=$!
python3 - "$port" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
for attempt in range(50):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=0.2):
            break
    except OSError:
        time.sleep(0.1)
else:
    raise SystemExit(f'Synthetic fixture on {port} did not start.')
PY
simulator="${ABS_PLAYBACK_QA_SIMULATOR:-}"
if [[ -z "$simulator" ]]; then
    simulator="$(sim acquire iphone --no-boot --for "leafwake playback-authorization verification")"
    leased_simulator="$simulator"
fi
xcodegen generate --spec "$apple_root/project.yml" > /dev/null
TEST_RUNNER_ABS_PLAYBACK_FIXTURE="http://127.0.0.1:$port/abs" xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" \
    -scheme "${ABS_PLAYBACK_QA_SCHEME:-NativeTests}" -destination "id=$simulator" -derivedDataPath "$derived" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "$@" test
