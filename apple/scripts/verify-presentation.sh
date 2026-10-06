#!/bin/bash
# Presentation QA: language, diagnostics, haptics and large text, on a dedicated simulator and fixture ports 25765/25769.
# Registers Localization and Diagnostics in a generated, git-ignored QA project until project.yml includes them.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
simulator="${ABS_PRESENTATION_SIMULATOR:-Audiobookshelf Presentation QA}"
simulator_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; name=sys.argv[1]; matches=[d["udid"] for devices in json.load(sys.stdin)["devices"].values() for d in devices if d["name"] == name]; assert len(matches) == 1, "Name an available leased simulator uniquely"; print(matches[0])' "$simulator")"
qa_root="$apple_root/build-presentation"
fixture_dir="$(mktemp -d)"
fixture_pids=()
cleanup() {
    for fixture_pid in "${fixture_pids[@]+"${fixture_pids[@]}"}"; do kill "$fixture_pid" 2>/dev/null || true; done
    for fixture_pid in "${fixture_pids[@]+"${fixture_pids[@]}"}"; do wait "$fixture_pid" 2>/dev/null || true; done
    rm -rf "$fixture_dir"
}
trap cleanup EXIT
if [[ ! -d "$repo_root/verification/realtime/node_modules" ]]; then
    echo "Install the realtime fixture first: npm ci --prefix verification/realtime" >&2
    exit 2
fi
python3 - <<'PY'
import socket
for port in [25765, 25769]:
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'Presentation fixture port {port} is already in use.')
PY
(cd "$repo_root" && exec python3 -m verification.fixture --port 25769) > "$fixture_dir/http.log" 2>&1 &
fixture_pids+=("$!")
(cd "$repo_root" && exec node verification/realtime/native-fixture.mjs 25765 25769) > "$fixture_dir/realtime.log" 2>&1 &
fixture_pids+=("$!")
python3 - <<'PY'
import socket, time
for port in [25765, 25769]:
    for attempt in range(50):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise SystemExit(f'Presentation fixture on {port} did not start.')
PY

mkdir -p "$qa_root"
spec="$qa_root/project.yml"
python3 - "$apple_root" "$spec" <<'PY'
import sys
apple_root, target = sys.argv[1:]
text = open(apple_root + '/project.yml').read()
anchor = '      - ../tvos/Core/Sources/TVCore\n'
if 'Localization/Sources/NativeLocalization' not in text:
    assert text.count(anchor) == 1, 'project.yml layout changed; register Localization and Diagnostics manually'
    text = text.replace(anchor, anchor + '      - Localization/Sources/NativeLocalization\n      - Diagnostics/Sources/NativeDiagnostics\n')
assert text.startswith('name: AudiobookshelfNative\n')
open(target, 'w').write(text.replace('name: AudiobookshelfNative\n', 'name: build-presentation-qa\n', 1))
PY
xcodegen generate --quiet --spec "$spec" --project-root "$apple_root" --project "$apple_root"
xcodebuild -project "$apple_root/build-presentation-qa.xcodeproj" -scheme AudiobookshelfNative \
    -destination "id=$simulator_id" \
    -derivedDataPath "$qa_root/derived" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "${@:--only-testing:NativeJourneyTests/PresentationJourney}" test
