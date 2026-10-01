#!/bin/bash
set -euo pipefail

tv_root="$(cd "$(dirname "$0")/.." && pwd)"
tv_devices="$(mktemp)"
trap 'rm -f "$tv_devices"' EXIT

if [[ "${1:-}" == "--build-only" ]]; then
    tv_profile="$(python3 "$tv_root/scripts/provision.py")"
else
    xcrun devicectl list devices --json-output "$tv_devices" >/dev/null
    tv_udid="$(python3 - "$tv_devices" "${1:-}" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))['result']['devices']
target = sys.argv[2]
candidates = []
for device in devices:
    props = device.get('properties', {})
    hardware = props.get('hardware', device.get('hardwareProperties', {}))
    state = props.get('state', device.get('deviceProperties', {}))
    connection = props.get('connection', device.get('connectionProperties', {}))
    if hardware.get('platform') != 'tvOS' or hardware.get('reality') == 'simulated':
        continue
    # Older physical TVs omit reality; require their hardware identity instead.
    if hardware.get('reality') != 'physical' and not (hardware.get('deviceType') == 'appleTV' and hardware.get('ecid') and hardware.get('udid')):
        continue
    if connection.get('pairingState') != 'paired':
        continue
    udid = hardware['udid']
    if not target or target in [state.get('name'), udid, device.get('identifier')]:
        candidates.append(udid)
if len(candidates) != 1:
    print('Pair one Apple TV in Xcode Device Hub first. On the TV: Settings > Remotes and Devices > Remote App and Devices. If multiple TVs are paired, pass its name or UDID.', file=sys.stderr)
    sys.exit(2)
print(candidates[0])
PY
)"
    tv_profile="$(python3 "$tv_root/scripts/provision.py" --udid "$tv_udid")"
fi

xcodebuild -project "$tv_root/AudiobookshelfTV.xcodeproj" \
    -scheme AudiobookshelfTV -configuration Release \
    -destination 'generic/platform=tvOS' -derivedDataPath "$tv_root/build" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
    PROVISIONING_PROFILE_SPECIFIER="$tv_profile" clean build

tv_app="$tv_root/build/Build/Products/Release-appletvos/AudiobookshelfTV.app"
codesign --verify --deep --strict "$tv_app"
if [[ "${1:-}" == "--build-only" ]]; then
    echo "Signed Apple TV build: $tv_app"
else
    xcrun devicectl device install app --device "$tv_udid" "$tv_app"
    xcrun devicectl device process launch --device "$tv_udid" com.forkzed.audiobookshelf.tv
    echo 'Audiobookshelf is installed and launched on your Apple TV.'
fi
