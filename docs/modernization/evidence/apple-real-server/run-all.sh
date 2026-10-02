#!/bin/bash
# The whole real-server run from any checkout: a freshly seeded owned container, the phone journeys, offline across files,
# TV, an offline finish of an unfinished book, and the migration upload. Output goes to $ABS_RS_OUT
# (default apple/build-qa/real-server-repro, ignored). Leaves the container up for inspection; `server_down` removes it.
source "$(dirname "$0")/common.sh"
: > "$OUT/results.txt"
server_fresh || exit 1
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
