#!/bin/bash
# The phone streaming case alone against the candidate server, freshly seeded: the owned diagnostic container
# abs-apple-diag (127.0.0.1:19900) with models/User.js replaced by RS_CANDIDATE. Output goes to $ABS_RS_OUT.
source "$(dirname "$0")/common-diag.sh"
: > "$OUT/results.txt"
server_fresh || exit 1
docker cp "${RS_CANDIDATE:?}" "$ABS_QA_CONTAINER:/app/server/models/User.js" && server_restart || exit 1
resolve_ids || exit 1
install_probes
phone_lease
step phone online-test1 test1SignInBrowseAndStreamAcrossFiles
step server_log '"The Long Tide"' > "$OUT/server-long-tide.txt"
finish
