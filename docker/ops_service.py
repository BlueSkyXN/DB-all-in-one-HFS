#!/usr/bin/env python3
"""Read-only operations service for DB-all-in-one-HFS container."""

from __future__ import annotations

import hmac
import json
import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, quote, urlparse

STARTED_AT = time.time()
LOG_DIR = Path(os.environ.get("DATA_DIR", "/data")) / "logs"
OPS_PORT = int(os.environ.get("OPS_PORT", "8081"))
OPS_TOKEN = os.environ.get("OPS_TOKEN", "")
SENSITIVE_ENV_KEYS = (
    "MYSQL_ROOT_PASSWORD",
    "MYSQL_PASSWORD",
    "NC_AUTH_JWT_SECRET",
    "OPS_TOKEN",
)

SERVICE_LOGS = {
    "supervisord": "supervisord.log",
    "mysql": "mysql.log",
    "mysql.err": "mysql.err",
    "mysql.error": "mysql-error.log",
    "mysql.slow": "mysql-slow.log",
    "redis": "redis.log",
    "nocodb": "nocodb.log",
    "nocodb.err": "nocodb.err",
    "nginx": "nginx.log",
}


def check_auth(handler: "OpsHandler") -> bool:
    """Validate OPS_TOKEN from header or query."""
    if not OPS_TOKEN:
        return False
    token = handler.headers.get("X-Ops-Token", "")
    if not token:
        qs = parse_qs(urlparse(handler.path).query)
        token = qs.get("token", [""])[0]
    return hmac.compare_digest(token, OPS_TOKEN)


def get_uptime() -> float:
    return time.time() - STARTED_AT


def check_mysql() -> dict[str, Any]:
    """Check MySQL connectivity."""
    try:
        result = subprocess.run(
            ["mysqladmin", "ping", "--socket=/data/run/mysqld/mysqld.sock"],
            capture_output=True, text=True, timeout=5
        )
        return {"status": "ok" if result.returncode == 0 else "error", "output": result.stdout.strip()}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def check_redis() -> dict[str, Any]:
    """Check Redis connectivity."""
    try:
        result = subprocess.run(
            ["redis-cli", "-p", os.environ.get("REDIS_PORT", "6379"), "ping"],
            capture_output=True, text=True, timeout=5
        )
        ok = result.stdout.strip() == "PONG"
        return {"status": "ok" if ok else "error", "output": result.stdout.strip()}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def check_nocodb() -> dict[str, Any]:
    """Check NocoDB health endpoint."""
    import urllib.request
    try:
        port = os.environ.get("PORT") or os.environ.get("NC_PORT", "8080")
        req = urllib.request.urlopen(f"http://127.0.0.1:{port}/api/v1/health", timeout=5)
        return {"status": "ok", "http_code": req.getcode()}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def get_health() -> dict[str, Any]:
    checks = {
        "mysql": check_mysql(),
        "redis": check_redis(),
        "nocodb": check_nocodb(),
    }
    return {
        "status": "ok" if all(c.get("status") == "ok" for c in checks.values()) else "error",
        "uptime_seconds": round(get_uptime(), 1),
        "checks": checks,
    }


def get_status() -> dict[str, Any]:
    """Get supervisor process status."""
    try:
        result = subprocess.run(
            ["supervisorctl", "-c", "/etc/supervisor/conf.d/supervisord.conf", "status"],
            capture_output=True, text=True, timeout=10
        )
        lines = [l.strip() for l in result.stdout.strip().split("\n") if l.strip()]
        processes = []
        for line in lines:
            parts = line.split()
            if len(parts) >= 2:
                processes.append({"name": parts[0], "state": parts[1], "detail": " ".join(parts[2:])})
        return {"processes": processes}
    except Exception as e:
        return {"error": str(e)}


def parse_line_limit(raw: str) -> int:
    """Parse and clamp requested log lines."""
    try:
        lines = int(raw)
    except ValueError as exc:
        raise ValueError("lines must be an integer") from exc
    if lines < 1:
        raise ValueError("lines must be greater than 0")
    return min(lines, 1000)


def redact_sensitive(text: str) -> str:
    """Best-effort redaction for secrets that could appear in service logs."""
    sensitive_values: set[str] = set()
    for key in SENSITIVE_ENV_KEYS:
        value = os.environ.get(key, "")
        if len(value) >= 4:
            sensitive_values.add(value)
            sensitive_values.add(quote(value, safe=""))

    for value in sorted(sensitive_values, key=len, reverse=True):
        text = text.replace(value, "[REDACTED]")
    return text


def get_logs(service: str, lines: int = 100) -> str:
    """Get last N lines of a service log."""
    if service not in SERVICE_LOGS:
        return f"Unknown service: {service}. Available: {', '.join(SERVICE_LOGS.keys())}"
    log_file = LOG_DIR / SERVICE_LOGS[service]
    if not log_file.exists():
        return f"Log file not found: {log_file}"
    try:
        result = subprocess.run(
            ["tail", f"-{lines}", str(log_file)],
            capture_output=True, text=True, timeout=5
        )
        return redact_sensitive(result.stdout)
    except Exception as e:
        return f"Error reading log: {e}"


class OpsHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging

    def send_json(self, data: Any, status: int = 200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text: str, status: int = 200):
        body = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        qs = parse_qs(parsed.query)

        # /healthz is unauthenticated
        if path == "/healthz":
            health = get_health()
            self.send_json(health, 200 if health["status"] == "ok" else 503)
            return

        # All other endpoints require auth
        if not OPS_TOKEN:
            self.send_json({"error": "ops token is not configured"}, 503)
            return
        if not check_auth(self):
            self.send_json({"error": "unauthorized"}, 401)
            return

        if path == "/" or path == "/health":
            health = get_health()
            self.send_json(health, 200 if health["status"] == "ok" else 503)
        elif path == "/status":
            self.send_json(get_status())
        elif path == "/logs":
            service = qs.get("service", ["nocodb"])[0]
            try:
                lines = parse_line_limit(qs.get("lines", ["100"])[0])
            except ValueError as exc:
                self.send_json({"error": str(exc)}, 400)
                return
            self.send_text(get_logs(service, lines))
        elif path == "/config":
            safe_keys = [
                "MYSQL_DATABASE", "MYSQL_USER", "PORT", "NC_DISABLE_TELE",
                "OPS_PORT", "REDIS_PORT", "DATA_DIR", "MYSQL_VERSION",
                "MYSQL_SERVER_PACKAGE", "MYSQL_CLIENT_PACKAGE",
                "UBUNTU_VERSION", "NOCODB_IMAGE_REF", "NC_SITE_URL",
                "NC_DEFAULT_LOCALE",
            ]
            config = {k: os.environ.get(k, "") for k in safe_keys}
            self.send_json(config)
        else:
            self.send_json({"error": "not found"}, 404)


def main():
    server = ThreadingHTTPServer(("127.0.0.1", OPS_PORT), OpsHandler)
    print(f"[ops-service] Listening on 127.0.0.1:{OPS_PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
