#!/bin/bash
# Checks the combined 2.30.0 server candidate: the Apple user-cache patch, then the Android first-progress patch, on
# the pinned image's models/User.js. Every server is this lane's own throwaway container (abs-android-qa,
# 127.0.0.1:28870), freshly seeded with the synthetic library and accounts by the unmodified web/qa/server.mjs.
#   run-combined.sh assemble                 build and verify both User.js files (no container)
#   run-combined.sh seams    pristine|combined  Apple's three user-cache seam checks, in the image without network
#   run-combined.sh progress pristine|combined  first-progress-check.mjs (eight cases)
#   run-combined.sh race     pristine|combined  cold-cache race: TRIES tries (default 10) of a finish racing GET /api/me
#   run-combined.sh native   pristine|combined  Android RealServerJourney a-d on emulator-5584
#   run-combined.sh down                     remove the container and its volumes
# Apple's files are read, never changed, from APPLE_USERCACHE_DIR (default: this checkout's
# docs/modernization/evidence/apple-real-server/server-usercache). No owner server, no other lane's container, no pull.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../../.." && pwd)"
apple="${APPLE_USERCACHE_DIR:-$repo/docs/modernization/evidence/apple-real-server/server-usercache}"
out="${ABS_COMBINED_OUT:-$repo/android-native/build/combined-server}"
export ABS_QA_CONTAINER=abs-android-qa ABS_QA_PORT=28870 ABS_QA_OIDC_PORT=28874 ABS_QA_FEED_PORT=28875 ABS_QA_MAIL_PORT=28876
S="http://127.0.0.1:$ABS_QA_PORT"
mode="${1:?assemble, seams, progress, race, native or down}"
if [[ "$mode" == down ]]; then exec node "$repo/web/qa/server.mjs" down; fi
source "$repo/android-native/scripts/require-local-image.sh"
require_local_image "$repo/web/qa/server.mjs"

# Each input is pinned; a different file stops the run.
apple_patch="$apple/usercache-candidate-3ef58609.patch"
apple_instrumentation="$apple/instrumentation-candidate-3ef58609.patch"
pristine_instrumentation="$apple/instrumentation-pristine.patch"
android_patch="$here/../server-first-progress/first-progress-candidate.patch"
pinned() { # file sha256
  [[ "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$2" ]] || { echo "$1 is not the reviewed file ($2)" >&2; exit 1; }
}
pinned "$apple_patch" b59ea8c83dceaece79b33abc72159abf9d6d4537b24b519f243c8fae74f50a94
pinned "$android_patch" 6313948fcce74d83ad7b320da1db0b587bb81557892cabdaad1207237cdf7367

assemble() {
  mkdir -p "$out/work/server/models"
  docker run --rm --network none --entrypoint cat "$pinned_image" /app/server/models/User.js > "$out/User.pristine.js"
  pinned "$out/User.pristine.js" 2174eec7b50b43ed3e0da55c4e54edaa90f9f98c30cefb9b4819430b744f6a1d
  build() { # result patches...
    local result="$1"; shift
    cp "$out/User.pristine.js" "$out/work/server/models/User.js"
    for patch in "$@"; do (cd "$out/work" && patch -s -p1 < "$patch"); done
    node --check "$out/work/server/models/User.js"
    cp "$out/work/server/models/User.js" "$out/$result"
  }
  build User.combined.js "$apple_patch" "$android_patch"
  pinned "$out/User.combined.js" 15ee2c33d88fab0e6e8e43d9ffe3c7eddb272ea6ba3f11906cabeb455c0ffac4
  # The race's DIAG lines: Apple's instrumentation, on each side.
  build User.combined-instrumented.js "$apple_patch" "$android_patch" "$apple_instrumentation"
  build User.pristine-instrumented.js "$pristine_instrumentation"
  shasum -a 256 "$apple_patch" "$android_patch" "$apple_instrumentation" "$pristine_instrumentation" "$out"/User.*.js
}

serve() { # User.js to run
  node "$repo/web/qa/server.mjs" up --fresh > "$out/server-up.log"
  docker cp "$1" "$ABS_QA_CONTAINER:/app/server/models/User.js"
  restart
  docker exec "$ABS_QA_CONTAINER" sha256sum /app/server/models/User.js
}
restart() {
  docker restart "$ABS_QA_CONTAINER" > /dev/null
  for _ in $(seq 90); do curl -sf "$S/ping" > /dev/null && return 0; sleep 1; done
  echo "server did not come back" >&2; exit 1
}
token() { curl -sf -X POST "$S/login" -H 'Content-Type: application/json' -H 'x-return-tokens: true' -d '{"username":"qa","password":"qa-pass"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["accessToken"])'; }
progress() { # label item
  printf '%s ' "$1"; curl -s "$S/api/me/progress/$2" -H "Authorization: Bearer $(token)" | python3 -c 'import json,sys; p=json.load(sys.stdin); print("currentTime", p["currentTime"], "isFinished", p["isFinished"], "lastUpdate", p["lastUpdate"])'
}

# The same steps as Apple's diag-race.sh, on this lane's container. Right after a restart the user cache is empty; a
# local-all session that finishes "The Long Tide" races GET /api/me, and a stale copy cached last keeps answering
# unfinished. Judged from the per-try rows: STALE when the read 3 s later is still unfinished.
race() {
  local book duration stale=0
  book=$(curl -s "$S/api/libraries" -H "Authorization: Bearer $(token)" | python3 -c 'import json,sys; print([l["id"] for l in json.load(sys.stdin)["libraries"] if l["mediaType"]=="book"][0])')
  book=$(curl -s "$S/api/libraries/$book/items?limit=200" -H "Authorization: Bearer $(token)" | python3 -c 'import json,sys; print([i["id"] for i in json.load(sys.stdin)["results"] if i["media"]["metadata"]["title"]=="The Long Tide"][0])')
  duration=$(curl -s "$S/api/items/$book?expanded=1" -H "Authorization: Bearer $(token)" | python3 -c 'import json,sys; print(json.load(sys.stdin)["media"]["duration"])')
  for try in $(seq 1 "${TRIES:-10}"); do
    local t since now body out
    t=$(token)
    curl -s -X PATCH "$S/api/me/progress/$book" -H "Authorization: Bearer $t" -H 'Content-Type: application/json' \
      -d "{\"currentTime\":34,\"duration\":$duration,\"progress\":0.38,\"isFinished\":false}" -o /dev/null -w "try $try: unfinished %{http_code}; "
    restart; sleep 1
    since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    now=$(python3 -c 'import time; print(int(time.time()*1000))')
    body=$(python3 -c "import json,uuid; print(json.dumps({'sessions':[{'id':str(uuid.uuid4()),'libraryItemId':'$book','episodeId':None,'mediaType':'book','displayTitle':'The Long Tide','duration':$duration,'playMethod':3,'mediaPlayer':'exo-player','startedAt':$now-30000,'updatedAt':$now,'timeListening':20,'currentTime':$duration}]}))")
    curl -s "$S/api/me" -H "Authorization: Bearer $t" -o /dev/null &
    curl -s -X POST "$S/api/session/local-all" -H "Authorization: Bearer $t" -H 'Content-Type: application/json' -d "$body" -o /dev/null -w "finish %{http_code}\n" &
    wait
    progress "  read" "$book"; sleep 3; out=$(progress "  3 s later" "$book"); echo "$out"
    [[ "$out" == *"isFinished False"* ]] && { stale=$((stale + 1)); echo "STALE on try $try"; }
    restart; progress "  after a restart" "$book"
    echo "  DIAG lines:"; docker logs --since "$since" "$ABS_QA_CONTAINER" 2>&1 | grep -E "DIAG|Syncing|Updating" | sed 's/^/    /' | cut -c1-230
  done
  echo "stale tries: $stale of ${TRIES:-10}"
}

side="${2:-combined}"
[[ "$mode" == assemble || "$side" == pristine || "$side" == combined ]] || { echo "pristine or combined" >&2; exit 1; }
mkdir -p "$out"
assemble > "$out/hashes.txt" 2>&1 || { cat "$out/hashes.txt"; exit 1; }
case "$mode" in
  assemble) cat "$out/hashes.txt" ;;
  seams)
    for check in concurrent-load-check.js invalidation-during-load-check.js delayed-write-check.js; do
      echo "== $check, User.$side.js"
      docker run --rm --network none --entrypoint node -w /app \
        -v "$out/User.$side.js:/app/server/models/User.js:ro" -v "$apple/$check:/check.js:ro" "$pinned_image" /check.js && echo "exit=0" || echo "exit=$?"
    done ;;
  progress) serve "$out/User.$side.js"; node "$here/../server-first-progress/first-progress-check.mjs" "$S" ;;
  race) serve "$out/User.$side-instrumented.js"; race ;;
  native)
    serve "$out/User.$side.js"
    ABS_REAL_SERVER="http://10.0.2.2:$ABS_QA_PORT" "$repo/android-native/scripts/verify-journeys.sh" RealServerJourney ;;
  *) echo "unknown mode $mode" >&2; exit 1 ;;
esac
