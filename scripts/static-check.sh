#!/usr/bin/env bash
set -euo pipefail

echo "=== Shell syntax check ==="
shell_files=(
  docker/entrypoint.sh
  docker/healthcheck.sh
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

echo "=== Whitespace check ==="
if git diff --check && git diff --cached --check; then
  echo "  No whitespace issues."
else
  echo "  Whitespace check failed."
  exit 1
fi

echo "All static checks passed."
