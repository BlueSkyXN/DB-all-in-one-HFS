#!/usr/bin/env bash
set -euo pipefail
curl -fsS http://127.0.0.1:8080/api/v1/health >/dev/null
curl -fsS http://127.0.0.1:8081/healthz >/dev/null
curl -fsS http://127.0.0.1:7860/nginx-health >/dev/null
