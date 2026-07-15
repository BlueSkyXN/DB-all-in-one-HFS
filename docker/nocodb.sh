#!/usr/bin/env bash
set -euo pipefail

NOCODB_ROOTFS=/opt/nocodb-runtime

export LD_LIBRARY_PATH="${NOCODB_ROOTFS}/lib:${NOCODB_ROOTFS}/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

cd /usr/src/app
exec "${NOCODB_ROOTFS}/usr/local/bin/node" /usr/src/app/docker/index.js
