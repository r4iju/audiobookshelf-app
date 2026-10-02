#!/bin/bash
# Attempt 1 on the phone: the online cases, then download, offline across files with the server stopped, and reconnect.
source "$(dirname "$0")/common.sh"
# Needs the owned server up (run-all.sh, or `source common.sh; server_fresh`). Runs the final probe sources in this
# folder, so it repeats the steps of that attempt, not the probe faults recorded for it in APPLE-REAL-SERVER-QA.md.
resolve_ids || exit 1
install_probes
phone_lease
step phone online test1SignInBrowseAndStreamAcrossFiles test2PDFPageSavedToServerAndRestored test3PodcastEpisodeProgress
step phone download test4aDownloadForOffline
step server_stop
step phone offline test4bPlayOfflineWithServerStopped
step server_start
step phone reconnect test4cReconnectPublishesOfflineListening
finish
