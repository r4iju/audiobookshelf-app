#!/bin/bash
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
fixture_dir="$(mktemp -d)"
fixture_pids=()
fixture_count=0
# ABS_QA_SIMULATOR takes a UDID or a device name; without it the run leases a pooled iPhone.
simulator="${ABS_QA_SIMULATOR:-}"
leased_simulator=""
if [[ -z "$simulator" ]]; then
    simulator="$(sim acquire iphone --no-boot --for "audiobookshelf apple verify-ui")"
    leased_simulator="$simulator"
fi
if [[ "$simulator" =~ ^[0-9A-F-]{36}$ ]]; then destination="id=$simulator"; else destination="platform=iOS Simulator,name=$simulator"; fi
cleanup() {
    if [[ -n "$leased_simulator" ]]; then sim release "$leased_simulator" || true; fi
    if (( fixture_count > 0 )); then
    for fixture_pid in "${fixture_pids[@]}"; do kill "$fixture_pid" 2>/dev/null || true; done
    for fixture_pid in "${fixture_pids[@]}"; do wait "$fixture_pid" 2>/dev/null || true; done
    fi
    rm -rf "$fixture_dir"
}
trap cleanup EXIT
# A focused local-fixture run does not need the qualified-host trust regression's DNS entry.
require_qualified_host=true
only_tests=()
for argument in "$@"; do
    if [[ "$argument" == -only-testing:* ]]; then only_tests+=("${argument#-only-testing:}"); fi
done
if (( ${#only_tests[@]} > 0 )); then
    require_qualified_host=false
    for selected in "${only_tests[@]}"; do
        case "$selected" in
            NativeJourneyTests|NativeJourneyTests/ConnectionJourney|NativeJourneyTests/ConnectionJourney/testQualifiedLANHTTPConnectsWithoutWeakeningHTTPSTrust)
                require_qualified_host=true ;;
        esac
    done
fi
ABS_QA_REQUIRE_QUALIFIED_HOST="$require_qualified_host" python3 - <<'PY'
import os, socket
for port in [19765, 19766, 19767, 19769]:
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'Fixture port {port} is already in use. Finish the previous owned verification before starting another.')
if os.environ['ABS_QA_REQUIRE_QUALIFIED_HOST'] == 'true' and socket.gethostbyname('dev.nginx.lan') != '127.0.0.1':
    raise SystemExit('The signed qualified-host regression requires dev.nginx.lan resolving to 127.0.0.1 on this Studio.')
PY
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
    -keyout "$fixture_dir/key.pem" -out "$fixture_dir/cert.pem" \
    -subj /CN=dev.nginx.lan -addext subjectAltName=DNS:dev.nginx.lan \
    > "$fixture_dir/certificate.log" 2>&1
(cd "$repo_root" && exec python3 -m verification.fixture --port 19769) > "$fixture_dir/http.log" 2>&1 &
fixture_pids+=("$!")
fixture_count=$((fixture_count + 1))
(cd "$repo_root" && exec node verification/realtime/native-fixture.mjs 19765 19769) > "$fixture_dir/realtime.log" 2>&1 &
fixture_pids+=("$!")
fixture_count=$((fixture_count + 1))
(cd "$repo_root" && exec python3 -m verification.fixture --port 19766) > "$fixture_dir/second-server.log" 2>&1 &
fixture_pids+=("$!")
fixture_count=$((fixture_count + 1))
(cd "$repo_root" && exec python3 -m verification.fixture --port 19767 --tls-cert "$fixture_dir/cert.pem" --tls-key "$fixture_dir/key.pem") > "$fixture_dir/https.log" 2>&1 &
fixture_pids+=("$!")
fixture_count=$((fixture_count + 1))
python3 - <<'PY'
import socket, time
for port in [19765, 19766, 19767, 19769]:
    for attempt in range(50):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise SystemExit(f'Synthetic fixture on {port} did not start.')
PY
for fixture_pid in "${fixture_pids[@]}"; do
    if ! kill -0 "$fixture_pid" 2>/dev/null; then
        echo "An owned fixture exited during startup." >&2
        exit 2
    fi
done
xcodegen generate --spec "$apple_root/project.yml"
xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" -scheme AudiobookshelfNative \
    -destination "$destination" \
    -derivedDataPath "$apple_root/build" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -collect-test-diagnostics never "$@" test
