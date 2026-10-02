#!/bin/bash
# Curl only, no app. Right after a server restart the user cache is empty. Two requests for the same user then each load
# their own copy of the user on a cache miss (`User.getUserById` / `getUserByIdOrOldId`) and each store it, last one
# wins. Here a `local-all` session that finishes "The Long Tide" races a plain GET /api/me. If the GET's copy, read
# before the finish was written, is stored last, the server keeps returning the earlier progress until it restarts.
# Each try first sets an unfinished position, restarts, fires both requests at once, then reads the progress twice
# and once more after a further restart. TRIES tries (default 5), all of them run. Against the owned diagnostic
# container abs-apple-diag, whose models/User.js is instrumented with instrumentation-*.patch; the DIAG lines show
# which user object each request used.
# Its exit status is not the result: the recorded runs are judged from the per-try rows (STALE lines and the
# reads), as kept with the outputs. Request errors are not counted either.
source "$(dirname "$0")/common-diag.sh"
resolve_ids || exit 1
I=$ABS_RS_LONG_TIDE
user=$(python3 -c 'import json; print(json.load(open("'"$ROOT"'/web/qa/.runtime/state.json"))["users"]["user"])')
T=$(token qa qa-pass); D=$(curl -s "$S/api/items/$I?expanded=1" -H "Authorization: Bearer $T" | python3 -c 'import json,sys; print(json.load(sys.stdin)["media"]["duration"])')
stale=0
for try in $(seq 1 "${TRIES:-5}"); do
  T=$(token qa qa-pass)
  curl -s -X PATCH "$S/api/me/progress/$I" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
    -d "{\"currentTime\":34,\"duration\":$D,\"progress\":0.38,\"isFinished\":false}" -o /dev/null -w "try $try: unfinished %{http_code}; "
  server_restart >/dev/null
  sleep 1
  since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  now=$(python3 -c 'import time; print(int(time.time()*1000))'); sid=$(python3 -c 'import uuid; print(uuid.uuid4())')
  body=$(python3 -c "import json; print(json.dumps({'sessions':[{'id':'$sid','userId':'$user','libraryItemId':'$I','episodeId':None,'mediaType':'book','displayTitle':'The Long Tide','duration':$D,'playMethod':3,'mediaPlayer':'AVPlayer','startedAt':$now-30000,'updatedAt':$now,'timeListening':20,'currentTime':$D,'date':'2026-10-02','dayOfWeek':'Friday'}]}))")
  curl -s "$S/api/me" -H "Authorization: Bearer $T" -o /dev/null &
  curl -s -X POST "$S/api/session/local-all" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$body" -o /dev/null -w "finish %{http_code}\n" &
  wait
  server_progress "  read" "$I"; sleep 3; out=$(server_progress "  3 s later" "$I"); echo "$out"
  [[ "$out" == *"isFinished False"* ]] && { stale=1; echo "STALE on try $try"; }
  server_restart >/dev/null; server_progress "  after a restart" "$I"
  echo "  DIAG lines for this try:"; docker logs --since "$since" "$ABS_QA_CONTAINER" 2>&1 | grep -E "DIAG|Syncing|Updating|Socket" | sed "s/^/    /" | cut -c1-230
done
echo "stale=$stale"
