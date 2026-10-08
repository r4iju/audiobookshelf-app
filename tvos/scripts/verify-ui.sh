#!/bin/bash
# Remote-driven tvOS journeys against owned synthetic fixtures on 20765 (HTTP) and 20767 (HTTPS): verification/fixture.py
# extended with the 2.30 author and series endpoints by tvos/scripts/related_fixture.py.
# Extra arguments pass to xcodebuild, for example -only-testing:TVJourneyTests/CatalogJourney.
# Without ABS_TV_QA_SIMULATOR the run leases a pooled Apple TV (`sim acquire tv`). ABS_TV_QA_SIMULATOR, ABS_TV_HTTP_PORT and ABS_TV_HTTPS_PORT let a parallel worktree use its own simulator and ports.
set -euo pipefail
tvos_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$tvos_root/.." && pwd)"
simulator="${ABS_TV_QA_SIMULATOR:-}"
leased_simulator=""
if [[ -z "$simulator" ]]; then
    # Erased first so throwaway CAs from earlier runs are not still trusted.
    simulator="$(sim acquire tv --fresh --no-boot --for "audiobookshelf tvOS verify-ui")"
    leased_simulator="$simulator"
fi
export ABS_TV_HTTP_PORT="${ABS_TV_HTTP_PORT:-20765}" ABS_TV_HTTPS_PORT="${ABS_TV_HTTPS_PORT:-20767}"
# xcodebuild hands TEST_RUNNER_ variables to the journeys without the prefix.
export TEST_RUNNER_ABS_TV_HTTP_PORT="$ABS_TV_HTTP_PORT" TEST_RUNNER_ABS_TV_HTTPS_PORT="$ABS_TV_HTTPS_PORT"
fixture_dir="$(mktemp -d)"
fixture_pids=()
cleanup() {
    if [[ -n "$leased_simulator" ]]; then sim release "$leased_simulator" || true; fi
    for pid in ${fixture_pids[@]+"${fixture_pids[@]}"}; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
    rm -rf "$fixture_dir"
}
trap cleanup EXIT
python3 - <<'PY'
import os, socket
for port in [int(os.environ['ABS_TV_HTTP_PORT']), int(os.environ['ABS_TV_HTTPS_PORT'])]:
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(('127.0.0.1', port))
        except OSError:
            raise SystemExit(f'TV fixture port {port} is already in use. Finish the previous TV verification first.')
PY
# A throwaway CA-signed certificate stands in for the trusted homelab CA: the app relies on system trust only.
# Explicit config prevents host openssl req defaults from adding duplicate CA
# extensions (actual stock17 hosted setup rejected that malformed certificate).
cat > "$fixture_dir/ca.cnf" <<'CA_CONFIG'
[req]
distinguished_name = ca_name
[ca_name]
[ca_extensions]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
CA_CONFIG
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$fixture_dir/ca.key" -out "$fixture_dir/ca.pem" \
    -config "$fixture_dir/ca.cnf" -extensions ca_extensions \
    -subj "/CN=Audiobookshelf TV QA CA" > "$fixture_dir/tls.log" 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$fixture_dir/key.pem" -out "$fixture_dir/server.csr" -subj /CN=127.0.0.1 >> "$fixture_dir/tls.log" 2>&1
printf 'subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' > "$fixture_dir/server.ext"
openssl x509 -req -in "$fixture_dir/server.csr" -CA "$fixture_dir/ca.pem" -CAkey "$fixture_dir/ca.key" -CAcreateserial \
    -days 2 -extfile "$fixture_dir/server.ext" -out "$fixture_dir/cert.pem" >> "$fixture_dir/tls.log" 2>&1
openssl verify -CAfile "$fixture_dir/ca.pem" "$fixture_dir/cert.pem" >> "$fixture_dir/tls.log" 2>&1
(cd "$repo_root" && exec python3 tvos/scripts/related_fixture.py --port "$ABS_TV_HTTP_PORT") > "$fixture_dir/http.log" 2>&1 &
fixture_pids+=("$!")
(cd "$repo_root" && exec python3 tvos/scripts/related_fixture.py --port "$ABS_TV_HTTPS_PORT" --tls-cert "$fixture_dir/cert.pem" --tls-key "$fixture_dir/key.pem") > "$fixture_dir/https.log" 2>&1 &
fixture_pids+=("$!")
python3 - <<'PY'
import os, socket, time
for port in [int(os.environ['ABS_TV_HTTP_PORT']), int(os.environ['ABS_TV_HTTPS_PORT'])]:
    for attempt in range(50):
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise SystemExit(f'TV fixture on {port} did not start.')
PY
xcrun simctl boot "$simulator" 2>/dev/null || true
xcrun simctl bootstatus "$simulator" > /dev/null
xcrun simctl keychain "$simulator" add-root-cert "$fixture_dir/ca.pem"
xcodegen generate --spec "$tvos_root/project.yml" > /dev/null
python3 "$repo_root/verification/verify-native-capture-policy.py" "$tvos_root/AudiobookshelfTV.xcodeproj" AudiobookshelfTV
derived_data="${ABS_TV_DERIVED_DATA:-$tvos_root/build}"
xcodebuild -project "$tvos_root/AudiobookshelfTV.xcodeproj" -scheme AudiobookshelfTV -configuration Debug \
    -destination "id=$simulator" -derivedDataPath "$derived_data" "$@" build-for-testing
python3 "$repo_root/verification/verify-native-capture-policy.py" "$tvos_root/AudiobookshelfTV.xcodeproj" AudiobookshelfTV "$derived_data"
xcodebuild -project "$tvos_root/AudiobookshelfTV.xcodeproj" -scheme AudiobookshelfTV -configuration Debug \
    -destination "id=$simulator" -derivedDataPath "$derived_data" \
    -resultBundlePath "${ABS_TV_RESULT_BUNDLE:-$tvos_root/build/TVJourneys-$(date +%Y%m%d-%H%M%S).xcresult}" \
    -collect-test-diagnostics never "$@" test-without-building
