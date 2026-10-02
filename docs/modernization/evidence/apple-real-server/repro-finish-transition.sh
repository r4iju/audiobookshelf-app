#!/bin/bash
# Direct server check of the unfinished-to-finished transition, with curl only and no app: as qa on "The Long Tide",
# a streamed session from a second device syncs an unfinished position, then a `local-all` session that ends at the
# book's end and is newer than it. Reads the progress after each step, then again after a restart.
source "$(dirname "$0")/common.sh"
resolve_ids || exit 1
I=$ABS_RS_LONG_TIDE
user=$(python3 -c 'import json; print(json.load(open("'"$ROOT"'/web/qa/.runtime/state.json"))["users"]["user"])')
T=$(token qa qa-pass); D=$(curl -s "$S/api/items/$I?expanded=1" -H "Authorization: Bearer $T" | python3 -c 'import json,sys; print(json.load(sys.stdin)["media"]["duration"])')
server_progress before "$I"
P=$(curl -sf -X POST "$S/api/items/$I/play" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d '{"deviceInfo":{"clientName":"Repro TV","deviceId":"repro-tv"},"mediaPlayer":"AVPlayer","forceDirectPlay":true}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
curl -s -X POST "$S/api/session/$P/sync" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d "{\"currentTime\":34,\"timeListened\":4,\"duration\":$D}" -o /dev/null -w "stream sync %{http_code}\n"
curl -s -X POST "$S/api/session/$P/close" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d "{\"currentTime\":34,\"timeListened\":0,\"duration\":$D}" -o /dev/null -w "stream close %{http_code}\n"
server_progress "after the second device" "$I"
sleep 2
now=$(python3 -c 'import time; print(int(time.time()*1000))'); sid=$(python3 -c 'import uuid; print(uuid.uuid4())')
body=$(python3 -c "import json; print(json.dumps({'sessions':[{'id':'$sid','userId':'$user','libraryItemId':'$I','episodeId':None,'mediaType':'book','displayTitle':'The Long Tide','duration':$D,'playMethod':3,'mediaPlayer':'AVPlayer','startedAt':$now-30000,'updatedAt':$now,'timeListening':20,'currentTime':$D,'date':'2026-10-02','dayOfWeek':'Friday'}]}))")
curl -s -X POST "$S/api/session/local-all" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$body"; echo
server_progress "after the finish, same token" "$I"; sleep 3; server_progress "3 s later" "$I"
T2=$(token qa qa-pass); printf 'fresh login /api/me: '; curl -s "$S/api/me" -H "Authorization: Bearer $T2" | python3 -c 'import json,sys,os; r=[p for p in json.load(sys.stdin)["mediaProgress"] if p["libraryItemId"]==os.environ["ABS_RS_LONG_TIDE"]]; print([(p["currentTime"], p["isFinished"]) for p in r])'
server_restart
server_progress "after a restart" "$I"
server_log "\\($sid\\)|$P|Repro TV"
