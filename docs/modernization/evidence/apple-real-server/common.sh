#!/bin/bash
# Shared by the real-server runners in this folder. Source it; it needs bash.
#
# Everything runs from the repository root found through git, so the runners work from any checkout.
# The server is the web real-server harness (`web/qa/server.mjs`) under its own name and ports: an isolated,
# unmodified 2.30.0 container `abs-apple-qa` on 127.0.0.1:19890, with fixtures on 19894 to 19896, its own named
# volumes, and the synthetic library that `web/qa/make-library.sh` generates inside this checkout. Only that
# container is started, stopped, restarted or removed. Accounts are the harness's synthetic ones.
set -uo pipefail
RS_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$RS_HERE" rev-parse --show-toplevel)"
cd "$ROOT"
OUT="${ABS_RS_OUT:-$ROOT/apple/build-qa/real-server-repro}"
mkdir -p "$OUT"
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
export ABS_QA_CONTAINER=abs-apple-qa ABS_QA_PORT=19890 ABS_QA_OIDC_PORT=19894 ABS_QA_FEED_PORT=19895 ABS_QA_MAIL_PORT=19896
S=http://127.0.0.1:19890

# Recreates the owned container and its volumes, regenerates the synthetic library and seeds the accounts.
server_fresh() { (cd "$ROOT/web" && node qa/server.mjs up --fresh) > "$OUT/server-up.log" 2>&1 || { cat "$OUT/server-up.log"; return 1; }; }
server_down() { (cd "$ROOT/web" && node qa/server.mjs down) >> "$OUT/server-down.log" 2>&1; }
server_wait() { for _ in $(seq 1 90); do curl -sf "$S/status" >/dev/null && return 0; sleep 1; done; echo "server did not answer"; return 1; }
server_stop() { docker stop "$ABS_QA_CONTAINER" >/dev/null && echo "server stopped $(date +%T)"; }
server_start() { docker start "$ABS_QA_CONTAINER" >/dev/null && echo "server started $(date +%T)"; server_wait; }
server_restart() { docker restart "$ABS_QA_CONTAINER" >/dev/null && echo "server restarted $(date +%T)"; server_wait; }

token() { # user password
  curl -sf -X POST "$S/login" -H 'Content-Type: application/json' -H 'x-return-tokens: true' \
    -d "{\"username\":\"$1\",\"password\":\"$2\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["accessToken"])'
}

# Seeded ids differ per server, so they are read from the harness state and looked up by title, then handed to the
# probes as TEST_RUNNER_ABS_RS_* (xcodebuild passes them to the tests without the prefix).
resolve_ids() {
  local state="$ROOT/web/qa/.runtime/state.json" t
  t="$(token qa qa-pass)" || return 1
  eval "$(python3 - "$state" "$S" "$t" <<'PY'
import json, sys, urllib.request
state, server, token = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
def items(library):
    request = urllib.request.Request(f"{server}/api/libraries/{library}/items?limit=500", headers={"Authorization": "Bearer " + token})
    return {i["media"]["metadata"]["title"]: i["id"] for i in json.load(urllib.request.urlopen(request))["results"]}
books, podcasts = items(state["libraries"]["books"]), items(state["libraries"]["podcasts"])
ids = {"SERVER": server, "BOOKS": state["libraries"]["books"], "PODCASTS": state["libraries"]["podcasts"], "OTHER_USER": state["users"]["other"],
       "LONG_TIDE": books["The Long Tide"], "FIELD_GUIDE": books["Field Guide to Quiet"], "SALT": books["Salt and Signal"],
       "LONG_STORY": books["A Very Long Story Title"], "VOLUME1": books["Catalog Volume 01"], "VOLUME2": books["Catalog Volume 02"],
       "VOLUME3": books["Catalog Volume 03"], "EVENING_STORIES": podcasts["Evening Stories"]}
for key, value in ids.items(): print(f"export ABS_RS_{key}={value} TEST_RUNNER_ABS_RS_{key}={value}")
PY
)" || return 1
  env | grep '^ABS_RS_' | sort > "$OUT/ids.env"
}

# The probes live here, outside the test targets; they are copied in for a run and removed afterwards.
install_probes() {
  cp "$RS_HERE/RealServerProbe-iPhone.swift" apple/UITests/RealServerProbe.swift
  cp "$RS_HERE/RealServerProbe-TV.swift" tvos/UITests/RealServerProbe.swift
  cp "$RS_HERE/RealServerAdoptionProbe.swift" apple/NativeTests/RealServerAdoptionProbe.swift
  trap remove_probes EXIT
}
remove_probes() {
  rm -f apple/UITests/RealServerProbe.swift tvos/UITests/RealServerProbe.swift apple/NativeTests/RealServerAdoptionProbe.swift
  git checkout -q -- apple/AudiobookshelfNative.xcodeproj/project.pbxproj tvos/AudiobookshelfTV.xcodeproj/project.pbxproj 2>/dev/null
  [[ -n "${RS_PHONE:-}" ]] && sim release "$RS_PHONE" >/dev/null 2>&1
  return 0
}

# Runners wrap each case in `step`: every case runs even after a failure, so all logs and result bundles exist, and
# `finish` exits non-zero when any case or server step failed (results.txt lists each one).
failed=0
step() { "$@" || { failed=1; echo "FAILED: $*" | tee -a "$OUT/results.txt"; }; }
finish() { echo "overall exit=$failed"; exit "$failed"; }

# Prints a case's outcome and appends it to results.txt; returns the test command's own exit status.
record() { # name status log extra-pattern
  local name=$1 rc=$2 log=$3
  echo "$name exit=$rc"
  grep -E "Test Case .*(passed|failed)|error: -\[|$4" "$log"
  echo "$name $rc" >> "$OUT/results.txt"
  return "$rc"
}

# A pooled iPhone, leased once per runner and erased first.
phone_lease() {
  RS_PHONE="$(sim acquire iphone --fresh --no-boot --for 'audiobookshelf apple real-server probe' | tail -1)"
  echo "phone lease=$RS_PHONE"
  xcodegen generate --quiet --spec apple/project.yml
}
xcode_phone() { # result-name scheme xcodebuild-args...
  local name=$1 scheme=$2; shift 2
  xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme "$scheme" -destination "id=$RS_PHONE" \
    -derivedDataPath apple/build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    -collect-test-diagnostics never -resultBundlePath "$OUT/$name.xcresult" "$@" test > "$OUT/$name.log" 2>&1
  record "$name" $? "$OUT/$name.log" "OFFLINE_|FINISH_|ADOPTION_REPORT|SYNC_|SERVER "
}
phone() { # result-name test-method...
  local name=$1 args=() t; shift
  for t in "$@"; do args+=("-only-testing:NativeJourneyTests/RealServerProbe/$t"); done
  xcode_phone "phone-$name" AudiobookshelfNative "${args[@]}"
}
# The TV runner leases its own erased Apple TV.
tv() { # result-name test-method...
  local name=$1 args=() t; shift
  for t in "$@"; do args+=("-only-testing:TVJourneyTests/RealServerProbe/$t"); done
  ABS_TV_RESULT_BUNDLE="$OUT/tv-$name.xcresult" "${RS_TV_RUNNER:-tvos/scripts/verify-ui.sh}" "${args[@]}" > "$OUT/tv-$name.log" 2>&1
  record "tv-$name" $? "$OUT/tv-$name.log" "TV_RESUME|TV_EPISODE"
}

# The legacy app's server side as qa-other, then the adoption probe. A streamed session syncs 5 s and is closed by a
# restart; a second stays open after syncing 10 s; Catalog Volume 03 gets a newer server position.
migration() { # result-name
  local name=$1 T R O
  play() { curl -sf -X POST "$S/api/items/$1/play" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
    -d '{"deviceInfo":{"clientName":"Legacy QA","deviceId":"legacy-qa"},"mediaPlayer":"AVPlayer","forceDirectPlay":true}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }
  report() { curl -sf -X POST "$S/api/session/$1/sync" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$2" -o /dev/null -w "sync $1 %{http_code}\n"; }
  {
    T=$(token qa-other qa-other-pass)
    R=$(play "$ABS_RS_LONG_STORY"); report "$R" '{"currentTime":5,"timeListened":5,"duration":20}'
    server_restart
    T=$(token qa-other qa-other-pass)
    O=$(play "$ABS_RS_SALT"); report "$O" '{"currentTime":10,"timeListened":10,"duration":60}'
    curl -sf -X PATCH "$S/api/me/progress/$ABS_RS_VOLUME3" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
      -d '{"currentTime":3,"duration":4,"progress":0.75}' -o /dev/null -w "volume3 %{http_code}\n"
    echo "open=$O restarted=$R"
  } > "$OUT/$name-setup.txt" 2>&1
  cat "$OUT/$name-setup.txt"
  TEST_RUNNER_ABS_RS_OPEN="$O" TEST_RUNNER_ABS_RS_RESTARTED="$R" xcode_phone "$name" NativeTests -only-testing:NativeTests/RealServerAdoptionProbe
}

# The server's own view of one item for qa, and its log lines for that title.
server_progress() { # label item-id
  local T; T=$(token qa qa-pass)
  printf '%s ' "$1"; curl -s "$S/api/me/progress/$2" -H "Authorization: Bearer $T" | python3 -c 'import json,sys; p=json.load(sys.stdin); print("currentTime", p["currentTime"], "isFinished", p["isFinished"], "lastUpdate", p["lastUpdate"])'
}
server_log() { docker logs -t "$ABS_QA_CONTAINER" 2>&1 | grep -E "$1" | grep -v LocalAuth; }
