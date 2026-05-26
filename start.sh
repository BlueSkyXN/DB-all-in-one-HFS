#!/usr/bin/env bash
set -Eeuo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# DB-all-in-one-HFS  —  MySQL 9.7 LTS + NocoDB start script
# ═══════════════════════════════════════════════════════════════════════════════

: "${MYSQL_ROOT_PASSWORD:=nocodb_root_pwd}"
: "${MYSQL_DATABASE:=nocodb}"
: "${MYSQL_USER:=nocodb}"
: "${MYSQL_PASSWORD:=nocodb_pwd}"
: "${NC_AUTH_JWT_SECRET:=change_me_to_a_random_string}"
: "${NC_PORT:=7860}"
: "${NC_DISABLE_TELE:=true}"

DATA_DIR="${DATA_DIR:-/data}"
MYSQL_DATA_DIR="${DATA_DIR}/mysql"
NOCODB_DATA_DIR="${DATA_DIR}/nocodb"

export NC_PORT
export NC_DISABLE_TELE
export NC_AUTH_JWT_SECRET

echo "=========================================="
echo "  DB-all-in-one-HFS starting"
echo "=========================================="
echo "  MySQL version : $(mysqld --version 2>&1 | head -1)"
echo "  NocoDB version: $(nocodb --version 2>/dev/null || echo 'latest')"
echo "  Data dir      : ${DATA_DIR}"
echo "  NocoDB port   : ${NC_PORT}"
echo "  Database      : ${MYSQL_DATABASE}"
echo "=========================================="

# ─── Initialize MySQL data directory if empty ─────────────────────────────────
if [ ! -d "${MYSQL_DATA_DIR}/mysql" ]; then
    echo "[MySQL] Initializing data directory..."
    mysqld --initialize-insecure --user=mysql --datadir="${MYSQL_DATA_DIR}"
fi

mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld "${MYSQL_DATA_DIR}"

# ─── Start MySQL ──────────────────────────────────────────────────────────────
echo "[MySQL] Starting server..."
mysqld \
    --user=mysql \
    --datadir="${MYSQL_DATA_DIR}" \
    --socket=/var/run/mysqld/mysqld.sock \
    --port=3306 \
    --bind-address=127.0.0.1 \
    --skip-name-resolve \
    &
MYSQL_PID=$!

# Wait for MySQL to be ready
echo "[MySQL] Waiting for server to be ready..."
for i in $(seq 1 60); do
    if mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent 2>/dev/null; then
        echo "[MySQL] Server is ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "[MySQL] ERROR: Server failed to start within 60 seconds." >&2
        exit 1
    fi
    sleep 1
done

# ─── Setup database and user ─────────────────────────────────────────────────
echo "[MySQL] Configuring database and user..."
mysql --socket=/var/run/mysqld/mysqld.sock -u root <<-EOSQL
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
    CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'localhost';
    GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'127.0.0.1';
    FLUSH PRIVILEGES;
EOSQL
echo "[MySQL] Database '${MYSQL_DATABASE}' and user '${MYSQL_USER}' configured."

# ─── Start NocoDB ─────────────────────────────────────────────────────────────
echo "[NocoDB] Starting on port ${NC_PORT}..."
mkdir -p "${NOCODB_DATA_DIR}"

export NC_DB="mysql2://127.0.0.1:3306?u=${MYSQL_USER}&p=${MYSQL_PASSWORD}&d=${MYSQL_DATABASE}"
export NC_DATA_DIR="${NOCODB_DATA_DIR}"

if [ -n "${NC_PUBLIC_URL:-}" ]; then
    export NC_PUBLIC_URL
fi

nocodb &
NOCODB_PID=$!

# ─── Wait for NocoDB to be ready ─────────────────────────────────────────────
echo "[NocoDB] Waiting for service to be ready..."
for i in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${NC_PORT}/api/v1/health" >/dev/null 2>&1; then
        echo "[NocoDB] Service is ready at port ${NC_PORT}."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "[NocoDB] WARNING: Health check not passing after 60s, continuing anyway..."
    fi
    sleep 1
done

echo "=========================================="
echo "  All services running"
echo "  NocoDB UI: http://localhost:${NC_PORT}"
echo "=========================================="

# ─── Process supervision ──────────────────────────────────────────────────────
shutdown() {
    trap - INT TERM
    echo "[Supervisor] Shutting down..."
    kill "$NOCODB_PID" "$MYSQL_PID" 2>/dev/null || true
    wait "$NOCODB_PID" "$MYSQL_PID" 2>/dev/null || true
}

trap shutdown INT TERM

status=0
while true; do
    if ! kill -0 "$MYSQL_PID" 2>/dev/null; then
        echo "[Supervisor] MySQL exited unexpectedly." >&2
        status=1
        break
    fi
    if ! kill -0 "$NOCODB_PID" 2>/dev/null; then
        echo "[Supervisor] NocoDB exited unexpectedly." >&2
        status=1
        break
    fi
    sleep 2
done

shutdown
exit "$status"
