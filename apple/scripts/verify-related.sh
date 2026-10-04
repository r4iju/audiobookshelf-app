#!/bin/bash
# Mobile author and series journeys (RelatedAuthorSeriesJourney) against the owned related fixture on 27765:
# verification/fixture.py extended with the 2.30 author and series endpoints by tvos/scripts/related_fixture.py.
# Runs on a pooled iPhone simulator.
# Extra arguments pass to xcodebuild.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
project="$apple_root/AudiobookshelfNative.xcodeproj/project.pbxproj"
work="$(mktemp -d)"
fixture_pid=""
leased_simulator=""
cp "$project" "$work/project.pbxproj"
cleanup() {
    if [[ -n "$leased_simulator" ]]; then sim release "$leased_simulator" || true; fi
    mkdir -p "$apple_root/build-related"
    curl -s http://127.0.0.1:27765/abs/__fixture__/observations > "$apple_root/build-related/observations.json" 2>/dev/null || true
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
        raise SystemExit('Related fixture port 27765 is already in use. Finish the previous related verification first.')
PY
(cd "$repo_root" && exec python3 tvos/scripts/related_fixture.py --port 27765) > "$work/fixture.log" 2>&1 &
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
    raise SystemExit('Related fixture on 27765 did not start.')
PY
simulator="${ABS_RELATED_QA_SIMULATOR:-}"
if [[ -z "$simulator" ]]; then
    simulator="$(sim acquire iphone --no-boot --for "leafwake related verification")"
    leased_simulator="$simulator"
fi
xcodegen generate --spec "$apple_root/project.yml" > /dev/null
TEST_RUNNER_ABS_RELATED_QA=1 xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" -scheme AudiobookshelfNative \
    -destination "id=$simulator" -derivedDataPath "$apple_root/build-related" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath "${ABS_RELATED_RESULT_BUNDLE:-$apple_root/build-related/Related-$(date +%Y%m%d-%H%M%S).xcresult}" \
    -collect-test-diagnostics never -only-testing:NativeJourneyTests/RelatedAuthorSeriesJourney "$@" test
