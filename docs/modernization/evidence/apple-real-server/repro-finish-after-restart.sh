#!/bin/bash
# The first offline run's finished session (90.2 s, logged "Updating progress") left progress at 37.4 s.
# Same sequence by hand as qa on Catalog Volume 02: a saved position, a container restart, then a local session that finishes.
set -uo pipefail
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
S=http://127.0.0.1:19890; I=636e9611-c7a6-490a-8cfa-d2a27766f8ca
tok() { curl -sf -X POST $S/login -H 'Content-Type: application/json' -H 'x-return-tokens: true' -d '{"username":"qa","password":"qa-pass"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["accessToken"])'; }
get() { curl -s $S/api/me/progress/$I -H "Authorization: Bearer $T" | python3 -c 'import json,sys; p=json.load(sys.stdin); print("progress", p["currentTime"], p["isFinished"], p["lastUpdate"])'; }
T=$(tok); D=$(curl -s "$S/api/items/$I?expanded=1" -H "Authorization: Bearer $T" | python3 -c 'import json,sys; print(json.load(sys.stdin)["media"]["duration"])')
curl -s -X PATCH $S/api/me/progress/$I -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "{\"currentTime\":1,\"duration\":$D,\"progress\":0.25}" -o /dev/null -w "patch %{http_code}\n"; get
docker restart abs-apple-qa >/dev/null; echo "restarted $(date +%T)"
for i in $(seq 1 60); do curl -sf $S/status >/dev/null && break; sleep 1; done
T=$(tok); now=$(python3 -c 'import time; print(int(time.time()*1000))'); sid=$(python3 -c 'import uuid; print(uuid.uuid4())')
body=$(python3 -c "import json; print(json.dumps({'sessions':[{'id':'$sid','userId':'a8cc33de-2e45-4519-9062-1b30f36cb67f','libraryItemId':'$I','episodeId':None,'mediaType':'book','displayTitle':'Catalog Volume 02','duration':$D,'playMethod':3,'mediaPlayer':'AVPlayer','startedAt':$now-30000,'updatedAt':$now,'timeListening':3,'currentTime':$D,'date':'2026-10-02','dayOfWeek':'Friday'}]}))")
curl -s -X POST $S/api/session/local-all -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$body"; echo
get; sleep 3; get
docker logs abs-apple-qa 2>&1 | grep -A3 "($sid)" | cut -c1-230
