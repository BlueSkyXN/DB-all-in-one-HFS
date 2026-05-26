#!/usr/bin/env bash
set -euo pipefail

echo "=== Shell syntax check ==="
bash -n docker/entrypoint.sh docker/healthcheck.sh scripts/build.sh scripts/run-demo.sh scripts/smoke.sh

echo "=== Python syntax check ==="
python3 -m py_compile docker/ops_service.py

echo "=== Whitespace check ==="
if git diff --cached --check 2>/dev/null; then
  echo "  No whitespace issues."
else
  echo "  (skipped: no staged changes or not in git)"
fi

echo "All static checks passed."
