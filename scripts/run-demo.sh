#!/usr/bin/env bash
set -euo pipefail
IMAGE_TAG=${1:-db-all-in-one-hfs:latest}
CONTAINER_NAME="db-aio-hfs-demo"

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run --rm -it \
  --name "$CONTAINER_NAME" \
  -p 7860:7860 \
  -v db-hfs-persist:/data \
  "$IMAGE_TAG"
