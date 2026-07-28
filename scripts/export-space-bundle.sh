#!/usr/bin/env bash
set -euo pipefail

# Export the Pattern A deployment wrapper only. This does not publish anything.
# The output directory is safe to pass to an explicit, reviewed Space uploader.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output_dir=${1:-}
manifest_file=${HFS_MANIFEST:-hfs-dev.toml}

if [ -z "${output_dir}" ]; then
  printf 'usage: %s <empty-output-directory>\n' "$0" >&2
  exit 2
fi
case "${manifest_file}" in
  hfs-dev.toml|hfs-dev.candidate.toml) ;;
  *) printf 'HFS_MANIFEST must be hfs-dev.toml or hfs-dev.candidate.toml.\n' >&2; exit 2 ;;
esac

if [ -n "$(git -C "${repo_root}" status --porcelain)" ]; then
  printf 'refusing to export from a dirty Git working tree (tracked, staged, or untracked changes); commit the reviewed source first.\n' >&2
  exit 1
fi

source_ref=$(git -C "${repo_root}" rev-parse --verify HEAD)
if [[ ! "${source_ref}" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'unable to determine a full immutable Git source ref.\n' >&2
  exit 1
fi

if [ -e "${output_dir}" ] && [ -n "$(find "${output_dir}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  printf 'output directory must be empty: %s\n' "${output_dir}" >&2
  exit 1
fi
mkdir -p "${output_dir}/docker"

for file in Dockerfile README.md .dockerignore; do
  cp "${repo_root}/${file}" "${output_dir}/${file}"
done
cp "${repo_root}/${manifest_file}" "${output_dir}/hfs-dev.toml"
for file in \
  my.cnf supervisord.conf nginx.conf entrypoint.sh healthcheck.sh nocodb.sh \
  nocodb_bootstrap.py mysql-backup.sh ops_service.py
do
  cp "${repo_root}/docker/${file}" "${output_dir}/docker/${file}"
done

SOURCE_REF="${source_ref}" OUTPUT_DIR="${output_dir}" python3 - <<'PY'
import json
import os
from pathlib import Path

output = Path(os.environ["OUTPUT_DIR"])
source_ref = os.environ["SOURCE_REF"]
dockerfile = output / "Dockerfile"
content = dockerfile.read_text(encoding="utf-8")
marker = "ARG WRAPPER_SOURCE_REF=unknown"
if content.count(marker) != 1:
    raise SystemExit("Dockerfile must contain exactly one wrapper source-ref build marker")
dockerfile.write_text(content.replace(marker, f"ARG WRAPPER_SOURCE_REF={source_ref}"), encoding="utf-8")

(output / "BUILD_SOURCE.json").write_text(
    json.dumps(
        {
            "schema_version": 1,
            "project": "db-all-in-one-hfs",
            "wrapper_source_ref": source_ref,
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    + "\n",
    encoding="utf-8",
)
PY

# Keep the exported Space root a deployment wrapper, never a source or data dump.
for forbidden in '.env' '.env.*' 'local' '.cache' '__pycache__' 'data' 'backups'; do
  if find "${output_dir}" -name "${forbidden}" -print -quit | grep -q .; then
    printf 'export contains forbidden path matching %s\n' "${forbidden}" >&2
    exit 1
  fi
done
if grep -Eq '^[[:space:]]*(COPY|ADD)[[:space:]]+\.[[:space:]]' "${output_dir}/Dockerfile"; then
  printf 'exported Dockerfile must not use COPY . or ADD .\n' >&2
  exit 1
fi

printf 'Exported immutable wrapper %s to %s\n' "${source_ref}" "${output_dir}"
