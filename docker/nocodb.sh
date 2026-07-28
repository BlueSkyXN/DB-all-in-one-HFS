#!/usr/bin/env bash
set -euo pipefail

NOCODB_RUNTIME_DIR="${NOCODB_RUNTIME_DIR:-/home/user/run/nocodb-runtime}"
NOCODB_ROOTFS="${NOCODB_RUNTIME_DIR}/rootfs"

if [ ! -f "${NOCODB_ROOTFS}/usr/local/bin/node" ] || \
   [ ! -x "${NOCODB_ROOTFS}/usr/local/bin/node" ] || \
   [ ! -f "${NOCODB_ROOTFS}/usr/src/app/docker/index.js" ] || \
   [ ! -r "${NOCODB_ROOTFS}/usr/src/app/docker/index.js" ]; then
  printf '[db-aio-hfs] ERROR: verified NocoDB runtime is unavailable.\n' >&2
  exit 1
fi

if ! python3 - "${NOCODB_RUNTIME_DIR}/provenance.json" <<'PY'
import json
import os
import re
import sys

try:
    provenance = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, UnicodeDecodeError, json.JSONDecodeError):
    raise SystemExit(1)

artifact = provenance.get("artifact") if isinstance(provenance, dict) else None
if (
    provenance.get("schema_version") != 1
    or provenance.get("project") != "db-all-in-one-hfs"
    or provenance.get("source_ref") != os.environ.get("NOCODB_SOURCE_REF")
    or provenance.get("wrapper_source_ref") != os.environ.get("NOCODB_WRAPPER_SOURCE_REF")
    or not isinstance(artifact, dict)
    or not re.fullmatch(r"[0-9a-f]{64}", str(artifact.get("sha256", "")))
):
    raise SystemExit(1)
PY
then
  printf '[db-aio-hfs] ERROR: verified NocoDB provenance is unavailable or inconsistent.\n' >&2
  exit 1
fi

export LD_LIBRARY_PATH="${NOCODB_ROOTFS}/lib:${NOCODB_ROOTFS}/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

cd "${NOCODB_ROOTFS}/usr/src/app"
exec "${NOCODB_ROOTFS}/usr/local/bin/node" docker/index.js
