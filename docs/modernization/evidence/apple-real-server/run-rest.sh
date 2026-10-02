#!/bin/bash
# After run-phone.sh: the podcast case alone (probe fixed), the TV probe, then the migration upload probe.
# Only the owned abs-apple-qa container (19890) is restarted; accounts are synthetic.
set -uo pipefail
cd "$(dirname "$0")/../../.."
E=apple/build-qa/real-server
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
S=http://127.0.0.1:19890
restore() { git checkout -q -- apple/AudiobookshelfNative.xcodeproj/project.pbxproj tvos/AudiobookshelfTV.xcodeproj/project.pbxproj 2>/dev/null; }
trap restore EXIT

# 1. Phone: the offline sequence again on an erased lease (the first run's probe skipped past the book's end;
# its logs are kept as phone-offline.* and phone-reconnect.*), then the podcast case alone.
udid="$(sim acquire iphone --fresh --no-boot --for 'audiobookshelf apple real-server probe' | tail -1)"
xcodegen generate --quiet --spec apple/project.yml
prun() { name=$1; shift
  xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination "id=$udid" \
    -derivedDataPath apple/build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    -collect-test-diagnostics never -resultBundlePath "$PWD/$E/phone-$name.xcresult" "$@" test > "$E/phone-$name.log" 2>&1
  echo "$name exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[|OFFLINE_" "$E/phone-$name.log"; }
P=NativeJourneyTests/RealServerProbe
prun download-rerun -only-testing:$P/test4aDownloadForOffline
docker stop abs-apple-qa >/dev/null && echo "server stopped $(date +%T)"
prun offline-rerun -only-testing:$P/test4bPlayOfflineWithServerStopped
docker start abs-apple-qa >/dev/null && echo "server started $(date +%T)"
for i in $(seq 1 60); do curl -sf http://127.0.0.1:19890/status >/dev/null && break; sleep 1; done
prun reconnect-rerun -only-testing:$P/test4cReconnectPublishesOfflineListening
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination "id=$udid" \
  -derivedDataPath apple/build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  -collect-test-diagnostics never -resultBundlePath "$PWD/$E/phone-podcast-rerun.xcresult" \
  -only-testing:NativeJourneyTests/RealServerProbe/test3PodcastEpisodeProgress test > "$E/phone-podcast-rerun.log" 2>&1
echo "podcast-rerun exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[" "$E/phone-podcast-rerun.log"

# 2. TV probe (leases its own TV).
ABS_TV_RESULT_BUNDLE="$PWD/$E/tv.xcresult" tvos/scripts/verify-ui.sh -only-testing:TVJourneyTests/RealServerProbe > "$E/tv.log" 2>&1
echo "tv exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[|TV_RESUME|TV_EPISODE" "$E/tv.log"

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
} > "$E/migration-setup.log" 2>&1
cat "$E/migration-setup.log"
TEST_RUNNER_ABS_RS_OPEN="$O" TEST_RUNNER_ABS_RS_RESTARTED="$R" xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme NativeTests \
  -destination "id=$udid" -derivedDataPath apple/build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  -collect-test-diagnostics never -resultBundlePath "$PWD/$E/migration.xcresult" \
  -only-testing:NativeTests/RealServerAdoptionProbe test > "$E/migration.log" 2>&1
echo "migration exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[|ADOPTION_REPORT|SYNC_|SERVER " "$E/migration.log"
sim release "$udid" >/dev/null 2>&1
