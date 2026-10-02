#!/bin/bash
# Second migration upload run: the first run's fixture dated the legacy app's last update before its own last server
# sync (migration.log). New sessions on the same items; only the owned abs-apple-qa container restarts.
set -uo pipefail
cd "$(dirname "$0")/../../.."
E=apple/build-qa/real-server
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
S=http://127.0.0.1:19890
trap 'git checkout -q -- apple/AudiobookshelfNative.xcodeproj/project.pbxproj 2>/dev/null; sim release "$udid" >/dev/null 2>&1' EXIT
udid="$(sim acquire iphone --no-boot --for 'audiobookshelf apple real-server probe' | tail -1)"
xcodegen generate --quiet --spec apple/project.yml
# 3. Migration upload: the legacy app's server side, as qa-other.
token() { curl -sf -X POST "$S/login" -H 'Content-Type: application/json' -H 'x-return-tokens: true' \
  -d '{"username":"qa-other","password":"qa-other-pass"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["accessToken"])'; }
play() { curl -sf -X POST "$S/api/items/$1/play" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d '{"deviceInfo":{"clientName":"Legacy QA","deviceId":"legacy-qa"},"mediaPlayer":"AVPlayer","forceDirectPlay":true}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }
sync() { curl -sf -X POST "$S/api/session/$1/sync" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$2" -o /dev/null -w "sync $1 %{http_code}\n"; }
{
T=$(token)
R=$(play 1d853118-1beb-41d1-85d2-21f699e55a79); sync "$R" '{"currentTime":5,"timeListened":5,"duration":20}'
docker restart abs-apple-qa >/dev/null && echo "restarted $(date +%T)"
for i in $(seq 1 60); do curl -sf "$S/status" >/dev/null && break; sleep 1; done
T=$(token)
O=$(play 880c5e1a-475a-40ea-b68c-7b86d320472d); sync "$O" '{"currentTime":10,"timeListened":10,"duration":60}'
curl -sf -X PATCH "$S/api/me/progress/fe3e135c-afb7-4f1a-8cb0-b40d86c452cb" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d '{"currentTime":3,"duration":4,"progress":0.75}' -o /dev/null -w "volume3 %{http_code}\n"
echo "open=$O restarted=$R"
} > "$E/migration-setup-rerun.log" 2>&1
cat "$E/migration-setup-rerun.log"
TEST_RUNNER_ABS_RS_OPEN="$O" TEST_RUNNER_ABS_RS_RESTARTED="$R" xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme NativeTests \
  -destination "id=$udid" -derivedDataPath apple/build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  -collect-test-diagnostics never -resultBundlePath "$PWD/$E/migration-rerun.xcresult" \
  -only-testing:NativeTests/RealServerAdoptionProbe test > "$E/migration-rerun.log" 2>&1
echo "migration-rerun exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[|ADOPTION_REPORT|SYNC_|SERVER " "$E/migration-rerun.log"
