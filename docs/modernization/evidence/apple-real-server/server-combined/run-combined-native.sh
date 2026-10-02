#!/bin/bash
# The Apple cases the combined 2.30.0 server candidate affects, against a freshly seeded owned diagnostic container
# abs-apple-diag (127.0.0.1:19900). The combined models/User.js is the pinned file with Apple's user-cache patch, then
# Android's first-progress patch; every input and the result are checked against their reviewed hashes first.
#   test1: streaming creates the book's first progress through the local-session sync (Android's create branch)
#   test4a, then test4d with the server stopped: the downloaded book finished offline from test1's unfinished position
#   test4e after the server returns: that finish published to the existing row (Apple's user-cache race)
#   migration: pending legacy sessions, one of which creates first progress
# Output goes to $ABS_RS_OUT (default apple/build-qa/combined-native).
here="$(cd "$(dirname "$0")" && pwd)"
export ABS_RS_OUT="${ABS_RS_OUT:-$(git -C "$here" rev-parse --show-toplevel)/apple/build-qa/combined-native}"
source "$here/../server-usercache/common-diag.sh"
image=ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03
apple_patch="$here/../server-usercache/usercache-candidate-3ef58609.patch"
android_patch="$ROOT/docs/modernization/evidence/android-real-server/server-first-progress/first-progress-candidate.patch"
pinned() { # file sha256
  local actual; actual="$(shasum -a 256 "$1" | cut -d' ' -f1)"
  echo "$actual $1"
  [[ "$actual" == "$2" ]] || { echo "not the reviewed file ($2)"; exit 1; }
}
build="$OUT/combined"; rm -rf "$build"; mkdir -p "$build/server/models"
docker image inspect "$image" >/dev/null 2>&1 || { echo "the pinned image is not cached locally"; exit 1; }
docker run --rm --network none --entrypoint cat "$image" /app/server/models/User.js > "$build/server/models/User.js"
{
  pinned "$build/server/models/User.js" 2174eec7b50b43ed3e0da55c4e54edaa90f9f98c30cefb9b4819430b744f6a1d
  pinned "$apple_patch" b59ea8c83dceaece79b33abc72159abf9d6d4537b24b519f243c8fae74f50a94
  pinned "$android_patch" 6313948fcce74d83ad7b320da1db0b587bb81557892cabdaad1207237cdf7367
  (cd "$build" && patch -s -p1 --no-backup-if-mismatch < "$apple_patch" && patch -s -p1 --no-backup-if-mismatch < "$android_patch") || exit 1
  pinned "$build/server/models/User.js" 15ee2c33d88fab0e6e8e43d9ffe3c7eddb272ea6ba3f11906cabeb455c0ffac4
  docker run --rm --network none -v "$build/server/models/User.js:/check/User.js:ro" --entrypoint node "$image" --check /check/User.js || exit 1
} 2>&1 | tee "$OUT/combined-hashes.txt"
[[ "${PIPESTATUS[0]}" == 0 ]] || exit 1
: > "$OUT/results.txt"
server_fresh || exit 1
docker cp "$build/server/models/User.js" "$ABS_QA_CONTAINER:/app/server/models/User.js" && server_restart || exit 1
echo "models/User.js in $ABS_QA_CONTAINER: $(docker exec "$ABS_QA_CONTAINER" sha256sum /app/server/models/User.js)" | tee -a "$OUT/combined-hashes.txt"
resolve_ids || exit 1
install_probes
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
finish
