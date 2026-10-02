#!/bin/bash
# Attempt 1 on the phone: the online cases, then download, offline across files with the server stopped, and reconnect.
source "$(dirname "$0")/common.sh"
# Needs the owned server up (run-all.sh, or `source common.sh; server_fresh`). Runs the final probe sources in this
# folder, so it repeats the steps of that attempt, not the probe faults recorded for it in APPLE-REAL-SERVER-QA.md.
resolve_ids || exit 1
install_probes
phone_lease
phone online test1SignInBrowseAndStreamAcrossFiles test2PDFPageSavedToServerAndRestored test3PodcastEpisodeProgress
phone download test4aDownloadForOffline
server_stop
phone offline test4bPlayOfflineWithServerStopped
server_start
phone reconnect test4cReconnectPublishesOfflineListening
