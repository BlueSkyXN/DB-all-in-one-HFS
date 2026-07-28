#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG=${1:-db-all-in-one-hfs:latest}
CONTAINER_NAME="db-aio-hfs-demo"
: "${NOCODB_ARTIFACT_MANIFEST_URL:?set NOCODB_ARTIFACT_MANIFEST_URL to a credential-free HTTPS manifest before starting the demo}"
: "${NOCODB_ARTIFACT_SLOT:?set NOCODB_ARTIFACT_SLOT to edge or release before starting the demo}"

case "${NOCODB_ARTIFACT_SLOT}" in
  edge|release) ;;
  *) printf 'NOCODB_ARTIFACT_SLOT must be edge or release.\n' >&2; exit 2 ;;
esac
if ! python3 - "${NOCODB_ARTIFACT_MANIFEST_URL}" <<'PY'
import sys
from urllib.parse import urlparse

parsed = urlparse(sys.argv[1])
if (
    parsed.scheme != "https"
    or not parsed.netloc
    or parsed.username
    or parsed.password
    or parsed.query
    or parsed.fragment
):
    raise SystemExit(1)
PY
then
  printf 'NOCODB_ARTIFACT_MANIFEST_URL must be a credential-free HTTPS URL without query or fragment.\n' >&2
  exit 2
fi

# Validate all required artifact inputs before replacing a running demo
# container. The named /data volume is intentionally preserved.
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

docker run --rm -it \
  --name "${CONTAINER_NAME}" \
  -p 7860:7860 \
  -v db-hfs-persist:/data \
  -e "NOCODB_ARTIFACT_MANIFEST_URL=${NOCODB_ARTIFACT_MANIFEST_URL}" \
  -e "NOCODB_ARTIFACT_SLOT=${NOCODB_ARTIFACT_SLOT}" \
  "${IMAGE_TAG}"
