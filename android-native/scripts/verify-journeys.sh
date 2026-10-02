#!/bin/bash
# Runs production-UI journeys on a dedicated emulator against synthetic loopback fixtures.
# Usage: scripts/verify-journeys.sh [JourneyClass[#method] ...]
# Ports 2876x are reserved for Android; Apple owns 19765-19769.
set -euo pipefail
android_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$android_root/.." && pwd)"
serial="${ANDROID_SERIAL:-emulator-5584}"
export ANDROID_SERIAL="$serial"
export JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
adb="$ANDROID_HOME/platform-tools/adb"

if [[ "$("$adb" -s "$serial" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r')" != "1" ]]; then
    echo "Refusing to run journeys on $serial: it is not an emulator. Physical devices are only used for explicit physical acceptance." >&2
    exit 2
fi

fixture_dir="$(mktemp -d)"
pids=()
cleanup() {
    for pid in "${pids[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done
    for port in 28765 28766 28767; do "$adb" -s "$serial" reverse --remove tcp:$port >/dev/null 2>&1 || true; done
    rm -rf "$fixture_dir"
}
trap 'status=$?; cleanup; exit $status' EXIT

# Never take over a port another worker holds: a listener on any address, or anything accepting a
# connection, means the port is occupied and this run stops without touching it. Sockets merely
# lingering in TIME_WAIT after an earlier run are not listeners and do not block the fixtures.
for port in 28765 28766 28767 28769; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || nc -z -G 1 127.0.0.1 "$port" >/dev/null 2>&1; then
        echo "Android fixture port $port is already in use; choose a free emulator run or stop only your own fixture." >&2
        exit 1
    fi
done

if [[ ! -d "$repo_root/verification/realtime/node_modules/socket.io" ]]; then
    npm ci --prefix "$repo_root/verification/realtime" --ignore-scripts --no-audit --no-fund >/dev/null
fi
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$fixture_dir/key.pem" -out "$fixture_dir/cert.pem" \
    -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 >/dev/null 2>&1

(cd "$repo_root" && exec python3 android-native/scripts/android_fixture.py --port 28769) > "${ABS_FIXTURE_LOG:-$fixture_dir/http.log}" 2>&1 & pids+=("$!")
(cd "$repo_root" && exec node verification/realtime/native-fixture.mjs 28765 28769) > "$fixture_dir/realtime.log" 2>&1 & pids+=("$!")
(cd "$repo_root" && exec python3 android-native/scripts/android_fixture.py --port 28766) > "$fixture_dir/second.log" 2>&1 & pids+=("$!")
(cd "$repo_root" && exec python3 android-native/scripts/android_fixture.py --port 28767 --tls-cert "$fixture_dir/cert.pem" --tls-key "$fixture_dir/key.pem") > "$fixture_dir/https.log" 2>&1 & pids+=("$!")
python3 - <<'PY'
import socket, time
for port in [28765, 28766, 28767, 28769]:
    for _ in range(80):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2): break
        except OSError: time.sleep(0.1)
    else: raise SystemExit(f'Fixture on {port} did not start.')
PY
# A listener that appeared meanwhile could answer the probe above; the fixtures must be this run's own.
for pid in "${pids[@]}"; do
    kill -0 "$pid" 2>/dev/null || { echo "A fixture process this run started ($pid) exited; its port may have been taken." >&2; exit 1; }
done
for port in 28765 28766 28767; do "$adb" -s "$serial" reverse tcp:$port tcp:$port >/dev/null; done
# Unrelated system notification sounds take audio focus, which pauses spoken-word playback mid-journey.
"$adb" -s "$serial" shell cmd notification set_dnd priority >/dev/null 2>&1 || true
# Chrome's own notification prompt can cover the sign-in page during browser journeys.
"$adb" -s "$serial" shell pm grant com.android.chrome android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true

args=()
if (( $# > 0 )); then
    classes=""
    for name in "$@"; do classes+="${classes:+,}com.audiobookshelf.android.journeys.$name"; done
    args+=("-Pandroid.testInstrumentationRunnerArguments.class=$classes")
fi
cd "$android_root"
./gradlew :app:connectedDebugAndroidTest --console=plain ${args[@]+"${args[@]}"}
