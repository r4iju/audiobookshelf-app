#!/bin/bash
# Mobile author and series journeys (RelatedAuthorSeriesJourney) against the owned related fixture on 27765:
# verification/fixture.py extended with the 2.30 author and series endpoints by tvos/scripts/related_fixture.py.
# Runs on its own simulator, "Audiobookshelf RelatedQA", created on first use.
# --wired temporarily applies docs/modernization/apple-related-author-series-wiring.patch, the search and details links
# the presentation owner applies for real, and reverts it on exit. Without it the journeys run against the app as it is.
# Extra arguments pass to xcodebuild.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
patch="$repo_root/docs/modernization/apple-related-author-series-wiring.patch"
project="$apple_root/AudiobookshelfNative.xcodeproj/project.pbxproj"
simulator_name="${ABS_RELATED_QA_SIMULATOR:-Audiobookshelf RelatedQA}"
wired=0
if [[ "${1:-}" == "--wired" ]]; then wired=1; shift; fi
work="$(mktemp -d)"
fixture_pid=""
applied=0
cp "$project" "$work/project.pbxproj"
cleanup() {
    mkdir -p "$apple_root/build-related"
    curl -s http://127.0.0.1:27765/abs/__fixture__/observations > "$apple_root/build-related/observations.json" 2>/dev/null || true
    [[ -n "$fixture_pid" ]] && { kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; }
    if (( applied )); then git -C "$repo_root" apply -R "$patch"; fi
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
if (( wired )); then git -C "$repo_root" apply "$patch"; applied=1; fi
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
simulator="$(xcrun simctl list devices available | sed -n "s/^ *$simulator_name (\([0-9A-F-]*\)).*/\1/p" | head -1)"
if [[ -z "$simulator" ]]; then
    simulator="$(xcrun simctl create "$simulator_name" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
fi
xcodegen generate --spec "$apple_root/project.yml" > /dev/null
TEST_RUNNER_ABS_RELATED_QA=1 xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" -scheme AudiobookshelfNative \
    -destination "id=$simulator" -derivedDataPath "$apple_root/build-related" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath "${ABS_RELATED_RESULT_BUNDLE:-$apple_root/build-related/Related-$(date +%Y%m%d-%H%M%S).xcresult}" \
    -collect-test-diagnostics never -only-testing:NativeJourneyTests/RelatedAuthorSeriesJourney "$@" test
