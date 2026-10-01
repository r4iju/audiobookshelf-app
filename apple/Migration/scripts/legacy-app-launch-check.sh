#!/bin/zsh
# Launch regression for the legacy app (ios/App): builds it unsigned for the simulator, installs it
# on a dedicated simulator and fails unless the app is still running with its web view loaded.
#
#   apple/Migration/scripts/legacy-app-launch-check.sh
#
# ABS_LEGACY_SIMULATOR names the simulator (created on first use; never a shared QA device),
# ABS_LEGACY_DERIVED_DATA the build directory, ABS_LEGACY_SKIP_BUILD=1 reuses the last build.
# Xcode 27 builds nothing below iOS 15, so the build overrides the deployment target on the
# command line only; the project keeps its iOS 14 minimum.
set -euo pipefail

root=${0:A:h:h:h:h}
device_name=${ABS_LEGACY_SIMULATOR:-ABS Legacy Export}
derived=${ABS_LEGACY_DERIVED_DATA:-/tmp/abs-legacy-export-dd}
bundle=com.audiobookshelf.app.dev
app=$derived/Build/Products/Debug-iphonesimulator/Audiobookshelf.app
logs=$(mktemp -d /tmp/abs-legacy-launch.XXXXXX)

udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == name:
            print(device["udid"]); sys.exit()
' "$device_name")
if [[ -z $udid ]]; then
  runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
print([r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]][-1])')
  udid=$(xcrun simctl create "$device_name" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$runtime")
fi
xcrun simctl bootstatus "$udid" -b > /dev/null

if [[ ${ABS_LEGACY_SKIP_BUILD:-0} != 1 ]]; then
  xcodebuild -workspace "$root/ios/App/App.xcworkspace" -scheme App -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 build > "$logs/build.log" 2>&1 \
    || { tail -20 "$logs/build.log"; echo "FAIL: build (log: $logs/build.log)"; exit 1; }
fi

xcrun simctl terminate "$udid" "$bundle" > /dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"
started=$(date '+%Y-%m-%d %H:%M:%S')
# A terminal keeps the app's stdout line-buffered, so Capacitor's log lines arrive while it runs.
xcrun simctl launch --console-pty "$udid" "$bundle" > "$logs/console.log" 2>&1 &
console=$!
sleep 15

xcrun simctl spawn "$udid" log show --start "$started" --style compact \
  --predicate 'process == "Audiobookshelf"' > "$logs/system.log" 2>/dev/null || true
failed=0
running=$(xcrun simctl spawn "$udid" launchctl list)
kill $console 2> /dev/null || true
if [[ $running != *"UIKitApplication:$bundle"* ]]; then
  echo "FAIL: the app is not running 15 seconds after launch"; failed=1
fi
if grep -q "UIScene life cycle is required" "$logs/system.log"; then
  echo "FAIL: UIKit refused the launch: UIScene life cycle is required"; failed=1
fi
if ! grep -q "WebView loaded" "$logs/console.log"; then
  echo "FAIL: the Capacitor web view did not load"; failed=1
fi
xcrun simctl io "$udid" screenshot "$logs/launch.png" > /dev/null 2>&1 || true
echo "simulator: $device_name ($udid), logs and screenshot: $logs"
(( failed == 0 )) && echo "PASS: the legacy app launched and loaded its web view"
exit $failed
