#!/usr/bin/env bash
set -euo pipefail
IMAGE_TAG=${1:-db-all-in-one-hfs:latest}
docker build -t "$IMAGE_TAG" .
