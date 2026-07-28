#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${repo_root}"

IMAGE_TAG=${1:-db-all-in-one-hfs:latest}

# The image must record the exact clean wrapper source that its artifact
# manifest will later accept. A dirty tree has no immutable commit identity.
if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
  printf '%s\n' 'refusing to build an artifact wrapper from an uncommitted worktree.' >&2
  exit 1
fi
WRAPPER_SOURCE_REF=$(git rev-parse --verify HEAD)
if [[ ! "${WRAPPER_SOURCE_REF}" =~ ^[0-9a-f]{40}$ ]]; then
  printf '%s\n' 'unable to determine a full immutable wrapper source ref.' >&2
  exit 1
fi

build_args=(--build-arg "WRAPPER_SOURCE_REF=${WRAPPER_SOURCE_REF}")
for name in \
  UBUNTU_VERSION \
  MYSQL_VERSION \
  MYSQL_SERVER_PACKAGE \
  MYSQL_CLIENT_PACKAGE
do
  value="${!name:-}"
  if [ -n "${value}" ]; then
    build_args+=(--build-arg "${name}=${value}")
  fi
done

# NOCODB_IMAGE_REF remains a compatibility input for local callers. The
# artifact lane names the immutable upstream identity NOCODB_SOURCE_REF.
if [ -z "${NOCODB_SOURCE_REF:-}" ] && [ -n "${NOCODB_IMAGE_REF:-}" ]; then
  printf '%s\n' 'NOCODB_IMAGE_REF is deprecated; use NOCODB_SOURCE_REF.' >&2
  NOCODB_SOURCE_REF="${NOCODB_IMAGE_REF}"
fi
if [ -n "${NOCODB_SOURCE_REF:-}" ]; then
  build_args+=(--build-arg "NOCODB_SOURCE_REF=${NOCODB_SOURCE_REF}")
fi

docker build "${build_args[@]}" -t "${IMAGE_TAG}" .
