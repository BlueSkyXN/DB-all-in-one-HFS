#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${1:-http://localhost:7860}
PASS=0
FAIL=0

check() {
  local desc="$1" url="$2" expected_code="${3:-200}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  if [ "$code" = "$expected_code" ]; then
    printf "  ✓ %s (HTTP %s)\n" "$desc" "$code"
    ((PASS++))
  else
    printf "  ✗ %s (expected %s, got %s)\n" "$desc" "$expected_code" "$code"
    ((FAIL++))
  fi
}

echo "Smoke testing: ${BASE_URL}"
echo "───────────────────────────────────"

check "nginx-health" "${BASE_URL}/nginx-health"
check "healthz" "${BASE_URL}/healthz"
check "NocoDB root" "${BASE_URL}/"

if [ -n "${OPS_TOKEN:-}" ]; then
  check "ops health (token)" "${BASE_URL}/_ops/health" "200"
fi

echo "───────────────────────────────────"
echo "Results: ${PASS} passed, ${FAIL} failed"

[ "$FAIL" -eq 0 ] || exit 1
