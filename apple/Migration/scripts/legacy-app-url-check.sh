#!/bin/zsh
# URL handling of the legacy app under the scene life cycle, on the dedicated simulator used by
# legacy-app-launch-check.sh (run that first): an audiobookshelf:// URL opened while the app runs
# must reach Capacitor's appUrlOpen listener once, and one opened while it is not running must launch
# it (the console of a launch by the system cannot be captured, so its delivery is not observed).
# A UI test opens each URL through the system, confirming the prompt the system may show.
set -euo pipefail

migration=${0:A:h:h}
device_name=${ABS_LEGACY_SIMULATOR:-ABS Legacy Export}
bundle=com.audiobookshelf.app.dev
out=$(mktemp -d /tmp/abs-legacy-url.XXXXXX)
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == sys.argv[1]))' "$device_name")

mkdir -p "$out/runner"
xcodegen --spec "$migration/LegacyExportJourney/project.yml" --project "$out/runner" --quiet
open_url() {
  TEST_RUNNER_ABS_LEGACY_URL=$1 xcodebuild test -project "$out/runner/LegacyExportJourney.xcodeproj" \
    -scheme LegacyExportJourneyUITests -destination "id=$udid" -derivedDataPath "$out/dd" \
    -collect-test-diagnostics never -only-testing:LegacyExportJourneyUITests/OpenURLThroughSystem >> "$out/open.log" 2>&1 \
    || { grep -E "error:" "$out/open.log" | tail -3; echo "FAIL: opening $1 did not bring the app to the foreground"; exit 1; }
}
failed=0

xcrun simctl terminate "$udid" "$bundle" > /dev/null 2>&1 || true
xcrun simctl launch --console-pty "$udid" "$bundle" > "$out/warm.log" 2>&1 &
console=$!
sleep 10
open_url "audiobookshelf://scene-check-warm"
sleep 3
kill $console 2> /dev/null || true
# Capacitor logs each appUrlOpen event it sends to the web view, with the URL's slashes escaped.
delivered=$(grep -c 'TO JS .*audiobookshelf:\\/\\/scene-check-warm' "$out/warm.log" || true)
if [[ $delivered != 1 ]]; then
  echo "FAIL: a URL opened while the app runs reached appUrlOpen $delivered times, not once"; failed=1
fi

xcrun simctl terminate "$udid" "$bundle" > /dev/null 2>&1 || true
sleep 2
open_url "audiobookshelf://scene-check-cold"
sleep 8
running=$(xcrun simctl spawn "$udid" launchctl list)
if [[ $running != *"UIKitApplication:$bundle"* ]]; then
  echo "FAIL: a URL opened while the app is not running did not launch it"; failed=1
fi
xcrun simctl io "$udid" screenshot "$out/cold.png" > /dev/null 2>&1 || true

echo "logs: $out"
(( failed == 0 )) && echo "PASS: URLs reach Capacitor while running, and launch the app when it is not"
exit $failed
