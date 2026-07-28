#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '=== Shell syntax check ==='
shell_files=(
  docker/entrypoint.sh
  docker/healthcheck.sh
  docker/mysql-backup.sh
  docker/nocodb.sh
  scripts/build.sh
  scripts/run-demo.sh
  scripts/smoke.sh
  scripts/static-check.sh
  scripts/export-space-bundle.sh
  scripts/check-hfs-artifact-contract.sh
)
bash -n "${shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
  printf '%s\n' '=== ShellCheck ==='
  shellcheck "${shell_files[@]}"
else
  printf '%s\n' '=== ShellCheck ==='
  printf '%s\n' '  shellcheck not found; skipping optional shell lint.'
fi

printf '%s\n' '=== Python syntax check ==='
pycache_dir=$(mktemp -d)
trap 'rm -rf "${pycache_dir}"' EXIT
PYTHONPYCACHEPREFIX="${pycache_dir}" python3 -m py_compile \
  docker/ops_service.py \
  docker/nocodb_bootstrap.py \
  scripts/test_nocodb_bootstrap.py \
  scripts/test_space_export.py

printf '%s\n' '=== MySQL container config check ==='
python3 - <<'PY'
from configparser import ConfigParser
from pathlib import Path

path = Path("docker/my.cnf")
config = ConfigParser(allow_no_value=True, interpolation=None)
with path.open(encoding="utf-8") as config_file:
    config.read_file(config_file)

if "mysqld" not in config:
    raise SystemExit(f"{path}: missing [mysqld] section")

expected = {
    "container_aware": "on",
    "innodb_numa_interleave": "off",
}
for option, expected_value in expected.items():
    value = config["mysqld"].get(option)
    if value is None or value.strip().lower() != expected_value:
        raise SystemExit(f"{path}: {option} must be configured as {expected_value}")
    print(f"  {option}={value.strip()}")
PY

printf '%s\n' '=== Supervisor NocoDB wrapper check ==='
python3 - <<'PY'
from configparser import ConfigParser
from pathlib import Path

path = Path("docker/supervisord.conf")
config = ConfigParser(interpolation=None)
with path.open(encoding="utf-8") as config_file:
    config.read_file(config_file)

program = config["program:nocodb"]
if program.get("command") != "/usr/local/bin/db-aio-nocodb":
    raise SystemExit(f"{path}: NocoDB must start through the verified runtime wrapper")
if program.get("directory") != "/home/user":
    raise SystemExit(f"{path}: Supervisor must not chdir into the artifact rootfs before the wrapper starts")
print("  NocoDB Supervisor working directory is wrapper-owned and always present")
PY

printf '%s\n' '=== HFS artifact contract check ==='
scripts/check-hfs-artifact-contract.sh

printf '%s\n' '=== Space exporter dynamic check ==='
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_space_export.py

printf '%s\n' '=== Whitespace check ==='
if git diff --check && git diff --cached --check; then
  printf '%s\n' '  No whitespace issues.'
else
  printf '%s\n' '  Whitespace check failed.'
  exit 1
fi

printf '%s\n' 'All static checks passed.'
