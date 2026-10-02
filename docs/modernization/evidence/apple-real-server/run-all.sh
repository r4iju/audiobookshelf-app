#!/bin/bash
# The whole real-server run from any checkout: a freshly seeded owned container, the phone journeys, offline across files,
# TV, an offline finish of an unfinished book, and the migration upload. Output goes to $ABS_RS_OUT
# (default apple/build-qa/real-server-repro, ignored). Leaves the container up for inspection; `server_down` removes it.
source "$(dirname "$0")/common.sh"
server_fresh || exit 1
resolve_ids || exit 1
cat "$OUT/ids.env"
install_probes
phone_lease
phone online test1SignInBrowseAndStreamAcrossFiles test2PDFPageSavedToServerAndRestored test3PodcastEpisodeProgress
phone download test4aDownloadForOffline
server_stop
phone offline test4bPlayOfflineWithServerStopped
server_start
phone reconnect test4cReconnectPublishesOfflineListening
server_progress "after offline reconnect" "$ABS_RS_LONG_TIDE"
tv all test1ResumeAnotherClientsPositionAndCrossFiles test2SearchAndPodcastEpisode
server_progress "after TV" "$ABS_RS_LONG_TIDE"
server_stop
phone finish-offline test4dFinishOfflineWithServerStopped
server_start
phone finish-reconnect test4eReconnectPublishesTheFinish
server_progress "after finish reconnect" "$ABS_RS_LONG_TIDE"
server_restart
server_progress "after a further restart" "$ABS_RS_LONG_TIDE"
server_log '"The Long Tide"|MediaProgress' > "$OUT/server-long-tide.txt"
migration migration
