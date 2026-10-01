#!/bin/bash
# Remaining mobile acceptance journeys (RemainingQAJourney*) against the synthetic fixture on owned ports 57765 (realtime
# proxy, used by the app) and 57769 (HTTP fixture), on a dedicated simulator ("ABS Remaining QA iPhone" unless
# ABS_REMAINING_QA_SIMULATOR names another, such as "ABS Remaining QA iPad"). Builds a generated, git-ignored copy of
# project.yml into apple/build-remaining-qa. Results: apple/build-remaining-qa/results/<name>-<time>.xcresult, fixture
# logs beside it. Extra arguments pass to xcodebuild (default: every RemainingQA journey).
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
simulator_name="${ABS_REMAINING_QA_SIMULATOR:-ABS Remaining QA iPhone}"
qa_root="$apple_root/build-remaining-qa"
stamp="$(date +%Y%m%d-%H%M%S)"
label="$(echo "$simulator_name" | tr ' ' '-')-$stamp"
mkdir -p "$qa_root/results"
fixture_pids=()
cleanup() {
    for fixture_pid in "${fixture_pids[@]+"${fixture_pids[@]}"}"; do kill "$fixture_pid" 2>/dev/null || true; done
    for fixture_pid in "${fixture_pids[@]+"${fixture_pids[@]}"}"; do wait "$fixture_pid" 2>/dev/null || true; done
}
trap cleanup EXIT
if [[ ! -d "$repo_root/verification/realtime/node_modules" ]]; then
    echo "Install the realtime fixture first: npm ci --offline --prefix verification/realtime" >&2
    exit 2
fi
python3 - <<'PY'
import socket
for port in [57765, 57769]:
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'Remaining QA fixture port {port} is already in use; refusing to share it.')
PY
simulator="$(xcrun simctl list devices available | sed -n "s/^ *$simulator_name (\([0-9A-F-]*\)).*/\1/p" | head -1)"
[[ -n "$simulator" ]] || { echo "Create the simulator \"$simulator_name\" first (see docs/modernization/APPLE-REMAINING-QA.md)." >&2; exit 2; }
(cd "$repo_root" && exec python3 -m verification.fixture --port 57769) > "$qa_root/results/$label-http.log" 2>&1 &
fixture_pids+=("$!")
(cd "$repo_root" && exec node verification/realtime/native-fixture.mjs 57765 57769) > "$qa_root/results/$label-realtime.log" 2>&1 &
fixture_pids+=("$!")
python3 - <<'PY'
import socket, time
for port in [57765, 57769]:
    for attempt in range(50):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise SystemExit(f'Remaining QA fixture on {port} did not start.')
PY
python3 - "$apple_root/project.yml" "$qa_root/project.yml" <<'PY'
import sys
source, target = sys.argv[1:]
text = open(source).read()
assert text.startswith('name: AudiobookshelfNative\n')
open(target, 'w').write(text.replace('name: AudiobookshelfNative\n', 'name: build-remaining-qa\n', 1))
PY
xcodegen generate --quiet --spec "$qa_root/project.yml" --project-root "$apple_root" --project "$apple_root"
echo "simulator: $simulator_name ($simulator); results: $qa_root/results/$label.xcresult"
test_filters=("$@")
if (( ${#test_filters[@]} == 0 )); then
    test_filters=(-only-testing:NativeJourneyTests/RemainingQAAccessibilityJourney -only-testing:NativeJourneyTests/RemainingQAGroupJourney)
fi
TEST_RUNNER_ABS_REMAINING_QA=1 xcodebuild -project "$apple_root/build-remaining-qa.xcodeproj" -scheme AudiobookshelfNative \
    -destination "id=$simulator" -derivedDataPath "$qa_root/derived" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath "$qa_root/results/$label.xcresult" \
    -collect-test-diagnostics never "${test_filters[@]}" test
