#!/bin/bash
# Recovering progress saves a gateway gave up on (PublicationRecoveryJourney), against verification/fixture.py
# in its held-sync mode on ABS_PUBLICATION_QA_PORT (63769 unless set). Runs on ABS_PUBLICATION_QA_SIMULATOR
# ("ABS Mobile Publication Recovery iPhone" unless set), leased from the shared pool. Extra arguments pass to xcodebuild.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
port="${ABS_PUBLICATION_QA_PORT:-63769}"
project="$apple_root/AudiobookshelfNative.xcodeproj/project.pbxproj"
derived="${ABS_PUBLICATION_QA_DERIVED_DATA:-$apple_root/build-publication-recovery}"
work="$(mktemp -d)"
fixture_pid=""
leased_simulator=""
cp "$project" "$work/project.pbxproj"
cleanup() {
    if [[ -n "$leased_simulator" ]]; then sim release "$leased_simulator" || true; fi
    mkdir -p "$derived"
    curl -s "http://127.0.0.1:$port/abs/__fixture__/observations" > "$derived/publication-recovery-observations.json" 2>/dev/null || true
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
        raise SystemExit(f'Fixture port {port} is already in use. Finish the previous publication recovery verification first.')
PY
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
simulator="${ABS_PUBLICATION_QA_SIMULATOR:-}"
if [[ -z "$simulator" ]]; then
    simulator="$(sim acquire iphone --no-boot --for "leafwake publication-recovery verification")"
    leased_simulator="$simulator"
fi
xcodegen generate --spec "$apple_root/project.yml" > /dev/null
TEST_RUNNER_ABS_PUBLICATION_FIXTURE="http://127.0.0.1:$port/abs" xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" \
    -scheme AudiobookshelfNative -destination "id=$simulator" -derivedDataPath "$derived" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    -resultBundlePath "${ABS_PUBLICATION_RESULT_BUNDLE:-$derived/PublicationRecovery-$(date +%Y%m%d-%H%M%S).xcresult}" \
    -collect-test-diagnostics never -only-testing:NativeJourneyTests/PublicationRecoveryJourney "$@" test
