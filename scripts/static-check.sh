#!/usr/bin/env bash
set -euo pipefail

echo "=== Shell syntax check ==="
shell_files=(
  docker/entrypoint.sh
  docker/healthcheck.sh
  docker/nocodb.sh
  scripts/build.sh
  scripts/run-demo.sh
  scripts/smoke.sh
  scripts/static-check.sh
)
bash -n "${shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
  echo "=== ShellCheck ==="
  shellcheck "${shell_files[@]}"
else
  echo "=== ShellCheck ==="
  echo "  shellcheck not found; skipping optional shell lint."
fi

echo "=== Python syntax check ==="
python3 -m py_compile docker/ops_service.py

echo "=== MySQL container config check ==="
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
    "container_aware": {"1", "on", "true", "yes"},
    "innodb_numa_interleave": {"0", "off", "false", "no"},
}
for option, accepted_values in expected.items():
    value = config["mysqld"].get(option)
    if value is None or value.strip().lower() not in accepted_values:
        expected_text = "/".join(sorted(accepted_values))
        raise SystemExit(
            f"{path}: {option} must be configured as {expected_text}"
        )
    print(f"  {option}={value.strip()}")
PY

echo "=== Whitespace check ==="
if git diff --check && git diff --cached --check; then
  echo "  No whitespace issues."
else
  echo "  Whitespace check failed."
  exit 1
fi

echo "All static checks passed."
