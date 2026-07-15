#!/usr/bin/env bash
set -euo pipefail
IMAGE_TAG=${1:-db-all-in-one-hfs:latest}

build_args=()
for name in \
  UBUNTU_VERSION \
  MYSQL_VERSION \
  MYSQL_SERVER_PACKAGE \
  MYSQL_CLIENT_PACKAGE \
  NOCODB_IMAGE_REF
do
  value="${!name:-}"
  if [ -n "$value" ]; then
    build_args+=(--build-arg "${name}=${value}")
  fi
done

docker build "${build_args[@]}" -t "$IMAGE_TAG" .
