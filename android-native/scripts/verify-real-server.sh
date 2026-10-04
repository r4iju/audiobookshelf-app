#!/bin/bash
# Runs the unchanged native server journeys against the one-image replacement and synthetic data.
set -euo pipefail
android_root="$(cd "$(dirname "$0")/.." && pwd)"
export ABS_QA_CONTAINER=leafwake-android-qa ABS_QA_PORT=28870 ABS_QA_OIDC_PORT=28874 ABS_QA_FEED_PORT=28875 ABS_QA_MAIL_PORT=28876
if [[ "${1:-}" == "down" ]]; then exec node "$android_root/../web/qa/server.mjs" down; fi
source "$android_root/scripts/require-local-image.sh"
require_local_image "$android_root/../web/qa/server.mjs"
# Fresh synthetic volumes isolate progress left by an earlier run.
node "$android_root/../web/qa/server.mjs" up --fresh
ABS_REAL_SERVER="http://10.0.2.2:$ABS_QA_PORT" exec "$android_root/scripts/verify-journeys.sh" RealServerJourney
