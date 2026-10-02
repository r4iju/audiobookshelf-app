#!/bin/bash
# Runs RealServerJourney against an unmodified Audiobookshelf 2.30.0 container (the pinned local image, never
# pulled) with the web lane's synthetic library and synthetic accounts. The container and its volumes are this
# lane's own (abs-android-qa, ports 28870 and 28874-28876); `scripts/verify-real-server.sh down` removes them.
# The emulator reaches it as 10.0.2.2, so turning the emulator's network off really cuts it off.
set -euo pipefail
android_root="$(cd "$(dirname "$0")/.." && pwd)"
export ABS_QA_CONTAINER=abs-android-qa ABS_QA_PORT=28870 ABS_QA_OIDC_PORT=28874 ABS_QA_FEED_PORT=28875 ABS_QA_MAIL_PORT=28876
if [[ "${1:-}" == "down" ]]; then exec node "$android_root/../web/qa/server.mjs" down; fi
source "$android_root/scripts/require-local-image.sh"
require_local_image "$android_root/../web/qa/server.mjs"
# Fresh every run: progress left by an earlier run would let playback start past what a journey checks.
node "$android_root/../web/qa/server.mjs" up --fresh
ABS_REAL_SERVER="http://10.0.2.2:$ABS_QA_PORT" exec "$android_root/scripts/verify-journeys.sh" RealServerJourney
