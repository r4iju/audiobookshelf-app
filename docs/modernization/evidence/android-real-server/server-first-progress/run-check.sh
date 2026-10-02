#!/bin/bash
# Runs first-progress-check.mjs against this lane's own throwaway 2.30.0 container (abs-android-qa, 127.0.0.1:28870),
# freshly seeded with the synthetic library and accounts by the web lane's unmodified web/qa/server.mjs.
#   run-check.sh baseline   the pinned image as it is
#   run-check.sh candidate  the same, with first-progress-candidate.patch applied to models/User.js and a restart
#   run-check.sh down       remove the container and its volumes
# Nothing else is touched: no owner server, no other lane's container, no image pull.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../../.." && pwd)"
export ABS_QA_CONTAINER=abs-android-qa ABS_QA_PORT=28870 ABS_QA_OIDC_PORT=28874 ABS_QA_FEED_PORT=28875 ABS_QA_MAIL_PORT=28876
mode="${1:?baseline, candidate or down}"
if [[ "$mode" == down ]]; then exec node "$repo/web/qa/server.mjs" down; fi
node "$repo/web/qa/server.mjs" up --fresh > /dev/null
if [[ "$mode" == candidate ]]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/server/models"
  docker cp "$ABS_QA_CONTAINER:/app/server/models/User.js" "$work/server/models/User.js"
  (cd "$work" && patch -s -p1 < "$here/first-progress-candidate.patch")
  docker cp "$work/server/models/User.js" "$ABS_QA_CONTAINER:/app/server/models/User.js"
  docker restart "$ABS_QA_CONTAINER" > /dev/null
  for _ in $(seq 60); do curl -sf "http://127.0.0.1:$ABS_QA_PORT/ping" > /dev/null && break; sleep 1; done
fi
docker exec "$ABS_QA_CONTAINER" sha256sum /app/server/models/User.js
node "$here/first-progress-check.mjs" "http://127.0.0.1:$ABS_QA_PORT"
