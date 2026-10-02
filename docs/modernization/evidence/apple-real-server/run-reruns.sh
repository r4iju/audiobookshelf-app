#!/bin/bash
# Attempts 3 and 4 of the phone podcast case and attempts 2 and 3 of the TV resume case, one at a time.
source "$(dirname "$0")/common.sh"
# Needs the owned server up (run-all.sh, or `source common.sh; server_fresh`). Runs the final probe sources in this
# folder, so it repeats the steps of that attempt, not the probe faults recorded for it in APPLE-REAL-SERVER-QA.md.
resolve_ids || exit 1
install_probes
phone_lease
step phone podcast-rerun2 test3PodcastEpisodeProgress
step tv resume-rerun test1ResumeAnotherClientsPositionAndCrossFiles
finish
