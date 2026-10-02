#!/bin/bash
# Direct server check by hand, kept as recorded: a saved position, a container restart, then a `local-all` session that
# ends at the book's end, as qa on Catalog Volume 02. It does not test the unfinished-to-finished transition the app
# made: in the recorded run the row was already finished from the attempt before (repro-finish-after-restart.txt).
source "$(dirname "$0")/common.sh"
resolve_ids || exit 1
I=$ABS_RS_VOLUME2
user=$(python3 -c 'import json; print(json.load(open("'"$ROOT"'/web/qa/.runtime/state.json"))["users"]["user"])')
T=$(token qa qa-pass); D=$(curl -s "$S/api/items/$I?expanded=1" -H "Authorization: Bearer $T" | python3 -c 'import json,sys; print(json.load(sys.stdin)["media"]["duration"])')
curl -s -X PATCH "$S/api/me/progress/$I" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "{\"currentTime\":1,\"duration\":$D,\"progress\":0.25}" -o /dev/null -w "patch %{http_code}\n"
server_progress progress "$I"
server_restart
T=$(token qa qa-pass); now=$(python3 -c 'import time; print(int(time.time()*1000))'); sid=$(python3 -c 'import uuid; print(uuid.uuid4())')
body=$(python3 -c "import json; print(json.dumps({'sessions':[{'id':'$sid','userId':'$user','libraryItemId':'$I','episodeId':None,'mediaType':'book','displayTitle':'Catalog Volume 02','duration':$D,'playMethod':3,'mediaPlayer':'AVPlayer','startedAt':$now-30000,'updatedAt':$now,'timeListening':3,'currentTime':$D,'date':'2026-10-02','dayOfWeek':'Friday'}]}))")
curl -s -X POST "$S/api/session/local-all" -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$body"; echo
server_progress progress "$I"; sleep 3; server_progress progress "$I"
server_log "\\($sid\\)"
