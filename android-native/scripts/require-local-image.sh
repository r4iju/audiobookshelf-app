# Sourced before web/qa/server.mjs starts a container. Its `docker run` pulls an image that is missing locally, so
# this stops first unless the exact pinned 2.30.0 image is already cached and server.mjs still runs that image.
pinned_image="ghcr.io/advplyr/audiobookshelf@sha256:6fbd7dc95d53c6e168ce69e760b87c334e3b9ba88bf7b8531ed5a116d5d6da03"
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
require_local_image() {
  local server_mjs="$1"
  grep -qF "\"$pinned_image\"" "$server_mjs" || { echo "$server_mjs no longer runs $pinned_image; not starting it" >&2; return 1; }
  docker image inspect "$pinned_image" > /dev/null 2>&1 || { echo "$pinned_image is not cached locally; not starting a server that would pull it" >&2; return 1; }
}
