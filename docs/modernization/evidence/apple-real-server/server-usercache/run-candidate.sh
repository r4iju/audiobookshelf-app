#!/bin/bash
# run-all.sh against the candidate server: the same cases in the same order, in the owned diagnostic container
# abs-apple-diag (127.0.0.1:19900), with models/User.js replaced by RS_CANDIDATE (the pinned 2.30.0 file with
# usercache-candidate.patch applied) after seeding. Output goes to $ABS_RS_OUT (default apple/build-qa/cache-diag).
source "$(dirname "$0")/common-diag.sh"
: > "$OUT/results.txt"
server_fresh || exit 1
# Candidate: the clean patched User.js in the owned diagnostic container, then a restart to load it.
docker cp "${RS_CANDIDATE:?}" "$ABS_QA_CONTAINER:/app/server/models/User.js" && server_restart || exit 1
resolve_ids || exit 1
cat "$OUT/ids.env"
install_probes
phone_lease
step phone online test1SignInBrowseAndStreamAcrossFiles test2PDFPageSavedToServerAndRestored test3PodcastEpisodeProgress
step phone download test4aDownloadForOffline
step server_stop
step phone offline test4bPlayOfflineWithServerStopped
step server_start
step phone reconnect test4cReconnectPublishesOfflineListening
step server_progress "after offline reconnect" "$ABS_RS_LONG_TIDE"
step tv all test1ResumeAnotherClientsPositionAndCrossFiles test2SearchAndPodcastEpisode
step server_progress "after TV" "$ABS_RS_LONG_TIDE"
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
