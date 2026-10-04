# Refuse implicit pulls: native QA consumes an explicitly built Leafwake product image.
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
require_local_image() {
  export LEAFWAKE_QA_IMAGE="${LEAFWAKE_QA_IMAGE:-leafwake:qa}"
  local qa_image="$LEAFWAKE_QA_IMAGE"
  docker image inspect "$qa_image" >/dev/null 2>&1 || { echo "Build the Leafwake QA image first: docker build -t $qa_image web" >&2; return 1; }
}
