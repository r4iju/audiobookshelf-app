#!/bin/bash
# Focused reader journeys against synthetic authored books. No owner account or server is used.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
evidence="${ABS_READER_EVIDENCE:-/Volumes/ai-ssd/code/audiobookshelf-delivery/2026-10-03/reader-expansion/apple}"
simulator="${ABS_QA_SIMULATOR:-}"
lease=""
fixture_pid=""
realtime_pid=""
cleanup() {
    if [[ -n "$fixture_pid" ]]; then kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; fi
    if [[ -n "$realtime_pid" ]]; then kill "$realtime_pid" 2>/dev/null || true; wait "$realtime_pid" 2>/dev/null || true; fi
    if [[ -n "$lease" ]]; then sim release "$lease" || true; fi
}
trap cleanup EXIT
mkdir -p "$evidence"
if [[ "${ABS_READER_FIXTURE_EXTERNAL:-0}" != '1' ]]; then
    python3 - <<'PY'
import socket
for port in [19765, 19769]:
    with socket.socket() as listener:
        try: listener.bind(('127.0.0.1', port))
        except OSError: raise SystemExit(f'Port {port} is occupied. Do not stop a fixture owned by another task.')
PY
    python3 "$repo/apple/scripts/make-reader-fixtures.py" "$evidence/media" > "$evidence/media-build.log" 2>&1
    npm ci --prefix "$repo/verification/realtime" --prefer-offline > "$evidence/fixture-dependencies.log" 2>&1
    (cd "$repo" && PYTHONPATH=. exec python3 apple/scripts/reader_fixture.py --media "$evidence/media") > "$evidence/fixture.log" 2>&1 &
    fixture_pid="$!"
    (cd "$repo" && exec node verification/realtime/native-fixture.mjs 19765 19769) > "$evidence/realtime.log" 2>&1 &
    realtime_pid="$!"
    python3 - <<'PY'
import socket, time
for port in [19765, 19769]:
    for _ in range(50):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2): break
        except OSError: time.sleep(0.1)
    else: raise SystemExit(f'Synthetic fixture on {port} did not start')
PY
fi
if [[ -z "$simulator" ]]; then
    simulator="$(sim acquire iphone --no-boot --for apple-reader-expansion)"
    lease="$simulator"
fi
xcodegen generate --spec "$repo/apple/project.yml"
if [[ $# -eq 0 ]]; then set -- -only-testing:NativeJourneyTests/ExpandedReaderJourney; fi
xcodebuild -project "$repo/apple/AudiobookshelfNative.xcodeproj" -scheme AudiobookshelfNative -destination "id=$simulator" -derivedDataPath "$evidence/build" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "$@" test
