#!/bin/bash
# Attempt 2: the offline sequence again on an erased lease, the podcast case alone, both TV cases, then the migration upload.
source "$(dirname "$0")/common.sh"
# Needs the owned server up (run-all.sh, or `source common.sh; server_fresh`). Runs the final probe sources in this
# folder, so it repeats the steps of that attempt, not the probe faults recorded for it in APPLE-REAL-SERVER-QA.md.
resolve_ids || exit 1
install_probes
phone_lease
step phone download-rerun test4aDownloadForOffline
step server_stop
step phone offline-rerun test4bPlayOfflineWithServerStopped
step server_start
step phone reconnect-rerun test4cReconnectPublishesOfflineListening
step phone podcast-rerun test3PodcastEpisodeProgress
step tv all test1ResumeAnotherClientsPositionAndCrossFiles test2SearchAndPodcastEpisode
step migration migration
finish
