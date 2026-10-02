#!/bin/bash
# The browser track's checks of the 2.30.0 server candidates, on this track's own synthetic server only
# (container abs-server-browser-qa, 127.0.0.1:19890, fixtures 19894-19896; production client on 127.0.0.1:3191).
#   run-matrix.sh progress stock|candidate|session...  per image: fresh seed and swap, then the PATCH, streamed and
#                                                      Android first-progress checks
#   run-matrix.sh seams                                Apple's three user-cache seam checks inside each image
#   run-matrix.sh race                                 run-combined.sh's cold-cache race against the running server
#   run-matrix.sh browser stock|candidate|session [playwright args]
#                                                      fresh seed and swap, then the production journeys
# Results go to $OUT (default web/qa/.runtime/server-matrix). Each check's exit is recorded; the script exits nonzero
# when any did. Cached local images only; no owner server, no other lane's container, no pull.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
evidence="$repo/docs/modernization/evidence"
out="${OUT:-$repo/web/qa/.runtime/server-matrix}"
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
export ABS_QA_CONTAINER=abs-server-browser-qa ABS_QA_PORT=19890 ABS_QA_OIDC_PORT=19894 ABS_QA_FEED_PORT=19895 \
  ABS_QA_MAIL_PORT=19896
S="http://127.0.0.1:$ABS_QA_PORT"
images=(
  "stock ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03"
  "candidate abs-server-candidate:2.30.0-usercache-firstprogress"
  "session abs-server-candidate:2.30.0-usercache-firstprogress-session"
)
failed=0
record() { # name output-file command...
  local name="$1" file="$2"; shift 2
  "$@" > "$file" 2>&1; local rc=$?
  echo "exit=$rc" >> "$file"
  echo "$name: $(grep -c '^PASS' "$file") pass, $(grep -c '^FAIL' "$file") fail, exit=$rc"
  [[ $rc == 0 ]] || failed=1
}
swap() { # mode dir
  mkdir -p "$2"
  node "$here/swap-to-candidate.mjs" "$repo/web" "$2" "$1" > "$2/swap.log" 2>&1 || { tail -5 "$2/swap.log"; exit 2; }
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["runningImageId"], r["runningFiles"])' \
    "$2/actual-server-$1.json"
}

mode="${1:?progress, seams, race or browser}"; shift
mkdir -p "$out"
case "$mode" in
  progress)
    for side in "$@"; do
      dir="$out/progress-$side"
      echo "== $side"; swap "$side" "$dir"
      record "$side PATCH" "$dir/patch-check.txt" node "$here/patch-first-progress-check.mjs" "$S"
      record "$side streamed" "$dir/streamed-check.txt" node "$here/streamed-first-progress-check.mjs" "$S"
      record "$side local-all" "$dir/first-progress-check.txt" \
        node "$evidence/android-real-server/server-first-progress/first-progress-check.mjs" "$S"
    done ;;
  seams)
    for entry in "${images[@]}"; do
      read -r side ref <<< "$entry"
      for check in concurrent-load-check.js invalidation-during-load-check.js delayed-write-check.js; do
        record "$side $check" "$out/seams-$side-$check.txt" docker run --rm --pull=never --network none \
          --entrypoint node -w /app -v "$evidence/apple-real-server/server-usercache/$check:/check.js:ro" "$ref" /check.js
      done
    done ;;
  race)
    docker inspect "$ABS_QA_CONTAINER" --format 'running {{.Image}}'
    # run-combined.sh's functions, unchanged (its fixed version, 37f191de).
    functions="$(mktemp)"
    sed -n '/^restart() {/,/^}/p; /^token() {/p; /^progress() {/,/^}/p; /^race() {/,/^}/p' \
      "$evidence/android-real-server/server-combined/run-combined.sh" > "$functions"
    # shellcheck source=/dev/null
    source "$functions"; rm -f "$functions"
    race > "$out/race.txt" 2>&1; rc=$?; echo "exit=$rc" >> "$out/race.txt"
    grep -E '^stale tries' "$out/race.txt"; echo "race exit=$rc"; [[ $rc == 0 ]] || failed=1 ;;
  browser)
    side="${1:?stock, candidate or session}"; shift
    dir="$out/browser-$side"; swap "$side" "$dir"
    (cd "$repo/web" && ABS_WEB_URL=http://127.0.0.1:3191 npx playwright test --output "$dir/results" "$@") \
      > "$dir/playwright.txt" 2>&1; rc=$?
    echo "exit=$rc" >> "$dir/playwright.txt"
    grep -E '✘|passed|failed|flaky|skipped|exit=' "$dir/playwright.txt"
    docker inspect "$ABS_QA_CONTAINER" --format 'after the run: {{.Image}}'
    [[ $rc == 0 ]] || failed=1 ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
exit "$failed"
