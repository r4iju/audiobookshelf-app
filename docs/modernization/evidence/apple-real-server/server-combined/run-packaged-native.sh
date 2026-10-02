#!/bin/bash
# The same five affected cases as run-combined-native.sh, on the unchanged packaged session-scoped image.
# Only synthetic data mounts are allowed. No source replacement, docker cp or network pull.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export ABS_RS_OUT="${ABS_RS_OUT:-$(git -C "$here" rev-parse --show-toplevel)/apple/build-qa/packaged-native}"
source "$here/../server-usercache/common-diag.sh"
export ABS_QA_CONTAINER=abs-apple-session-qa
export ABS_QA_IMAGE=sha256:cd703e87399f76f4e887282ca219013f99eeb7b7f24cc028990b07b71b39eba4
# An owned cache avoids changing any saved acceptance build.
export ABS_RS_DERIVED="${ABS_RS_DERIVED:-$ROOT/apple/build-packaged-native}"
RS_HERE="$here/../server-usercache"
cleanup() {
  remove_probes
  server_down
}
trap cleanup EXIT
inspect() {
  docker inspect "$ABS_QA_CONTAINER" --format '{{.Image}} {{json .Mounts}}' > "$OUT/container-image-mounts.txt"
  python3 - "$OUT/container-image-mounts.txt" "$ABS_QA_IMAGE" <<'CHECK'
import json, sys
image, mounts = open(sys.argv[1]).read().strip().split(' ', 1)
assert image == sys.argv[2], image
assert {m['Destination'] for m in json.loads(mounts)} == {'/library', '/podcasts', '/config', '/metadata'}, mounts
CHECK
  docker exec "$ABS_QA_CONTAINER" sha256sum /app/server/models/User.js /app/server/managers/PlaybackSessionManager.js > "$OUT/server-file-hashes.txt"
  python3 - "$OUT/server-file-hashes.txt" <<'CHECK'
import sys
assert [line.split()[0] for line in open(sys.argv[1])] == [
    'd36db80057337ae071a436a7753cb3aa024e97373e8d4cc9e805d1c048486097',
    'a140b5679a81e8b48b3485f6bd7e2bee0c20fb6bd79819a61279e465c8f685ae']
CHECK
}
xcode_phone() {
  local name=$1 scheme=$2 rc=0; shift 2
  xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme "$scheme" -destination "id=$RS_PHONE" \
    -derivedDataPath "$ABS_RS_DERIVED" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    -collect-test-diagnostics never -resultBundlePath "$OUT/$name.xcresult" "$@" test > "$OUT/$name.log" 2>&1 || rc=$?
  record "$name" "$rc" "$OUT/$name.log" "OFFLINE_|FINISH_|ADOPTION_REPORT|SYNC_|SERVER "
}
docker image inspect "$ABS_QA_IMAGE" > "$OUT/image-inspect.json"
git rev-parse HEAD > "$OUT/client-source.txt"
shasum -a 256 "$here"/run-packaged-native.sh "$here/../server-usercache/common-diag.sh" "$here/../"*Probe*.swift "$ROOT/web/qa/server.mjs" > "$OUT/source-hashes.txt"
: > "$OUT/results.txt"
server_fresh
inspect
resolve_ids
install_probes
trap cleanup EXIT
phone_lease
step phone stream test1SignInBrowseAndStreamAcrossFiles
step server_progress "after streaming" "$ABS_RS_LONG_TIDE"
step phone download test4aDownloadForOffline
step server_stop
step phone finish-offline test4dFinishOfflineWithServerStopped
step server_start
step phone finish-reconnect test4eReconnectPublishesTheFinish
step server_progress "after finish reconnect" "$ABS_RS_LONG_TIDE"
step server_restart
step server_progress "after a further restart" "$ABS_RS_LONG_TIDE"
step server_log '"The Long Tide"|MediaProgress' > "$OUT/server-long-tide.txt"
step migration migration
inspect
finish
