#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[db-aio-hfs] %s\n' "$*"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Environment defaults
# ═══════════════════════════════════════════════════════════════════════════════

: "${DATA_DIR:=/data}"
: "${MYSQL_ROOT_PASSWORD:=}"
: "${MYSQL_DATABASE:=nocodb}"
: "${MYSQL_USER:=nocodb}"
: "${MYSQL_PASSWORD:=}"
: "${NC_AUTH_JWT_SECRET:=}"
: "${NC_PORT:=8080}"
: "${NC_DISABLE_TELE:=true}"
: "${NC_PUBLIC_URL:=}"
: "${OPS_PORT:=8081}"
: "${OPS_TOKEN:=}"
: "${REDIS_PORT:=6379}"

export DATA_DIR MYSQL_DATABASE MYSQL_USER NC_PORT NC_DISABLE_TELE OPS_PORT OPS_TOKEN REDIS_PORT

MYSQL_DATA_DIR="${DATA_DIR}/mysql"
NOCODB_DATA_DIR="${DATA_DIR}/nocodb"

# ═══════════════════════════════════════════════════════════════════════════════
# Secret generation (persist to /data/config/generated.env)
# ═══════════════════════════════════════════════════════════════════════════════

generate_secrets() {
  mkdir -p "${DATA_DIR}/config"

  if [ -f "${DATA_DIR}/config/generated.env" ]; then
    # shellcheck disable=SC1091
    . "${DATA_DIR}/config/generated.env"
  fi

  # Use provided env or previously generated, else create new
  MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-${_GEN_MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 24)}}"
  MYSQL_PASSWORD="${MYSQL_PASSWORD:-${_GEN_MYSQL_PASSWORD:-$(openssl rand -base64 24)}}"
  NC_AUTH_JWT_SECRET="${NC_AUTH_JWT_SECRET:-${_GEN_NC_AUTH_JWT_SECRET:-$(openssl rand -base64 42)}}"
  OPS_TOKEN="${OPS_TOKEN:-${_GEN_OPS_TOKEN:-$(openssl rand -hex 16)}}"

  cat > "${DATA_DIR}/config/generated.env" <<EOF
_GEN_MYSQL_ROOT_PASSWORD='${MYSQL_ROOT_PASSWORD}'
_GEN_MYSQL_PASSWORD='${MYSQL_PASSWORD}'
_GEN_NC_AUTH_JWT_SECRET='${NC_AUTH_JWT_SECRET}'
_GEN_OPS_TOKEN='${OPS_TOKEN}'
EOF
  chmod 600 "${DATA_DIR}/config/generated.env"

  export MYSQL_ROOT_PASSWORD MYSQL_PASSWORD NC_AUTH_JWT_SECRET OPS_TOKEN
}

# ═══════════════════════════════════════════════════════════════════════════════
# MySQL initialization
# ═══════════════════════════════════════════════════════════════════════════════

init_mysql() {
  if [ ! -d "${MYSQL_DATA_DIR}/mysql" ]; then
    log "Initializing MySQL data directory..."
    mysqld --initialize-insecure --user=mysql --datadir="${MYSQL_DATA_DIR}"
  fi
  chown -R mysql:mysql "${MYSQL_DATA_DIR}" /data/run/mysqld 2>/dev/null || true
}

wait_for_mysql() {
  log "Waiting for MySQL to be ready..."
  local i
  for i in $(seq 1 60); do
    if mysqladmin ping --socket=/data/run/mysqld/mysqld.sock --silent 2>/dev/null; then
      log "MySQL is ready."
      return 0
    fi
    sleep 1
  done
  log "ERROR: MySQL failed to start within 60 seconds."
  return 1
}

setup_mysql_users() {
  log "Configuring MySQL database and user..."
  mysql --socket=/data/run/mysqld/mysqld.sock -u root <<-EOSQL
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
    CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';
    GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'localhost';
    GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'127.0.0.1';
    FLUSH PRIVILEGES;
EOSQL
  log "Database '${MYSQL_DATABASE}' and user '${MYSQL_USER}' ready."
}

# ═══════════════════════════════════════════════════════════════════════════════
# Redis configuration
# ═══════════════════════════════════════════════════════════════════════════════

write_redis_conf() {
  cat > "${DATA_DIR}/run/redis.conf" <<EOF
bind 127.0.0.1
port ${REDIS_PORT}
dir ${DATA_DIR}/redis
dbfilename dump.rdb
save 900 1
save 300 10
save 60 10000
maxmemory 64mb
maxmemory-policy allkeys-lru
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# NocoDB environment
# ═══════════════════════════════════════════════════════════════════════════════

export_nocodb_env() {
  export NC_DB="mysql2://127.0.0.1:3306?u=${MYSQL_USER}&p=${MYSQL_PASSWORD}&d=${MYSQL_DATABASE}"
  export NC_DATA_DIR="${NOCODB_DATA_DIR}"
  export NC_AUTH_JWT_SECRET
  export NC_PORT
  export NC_DISABLE_TELE
  export NC_REDIS_URL="redis://127.0.0.1:${REDIS_PORT}"
  if [ -n "${NC_PUBLIC_URL}" ]; then
    export NC_PUBLIC_URL
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  log "=========================================="
  log "  DB-all-in-one-HFS starting"
  log "=========================================="

  # Ensure directories exist
  mkdir -p "${MYSQL_DATA_DIR}" "${NOCODB_DATA_DIR}" "${DATA_DIR}/redis" \
           "${DATA_DIR}/config" "${DATA_DIR}/logs" "${DATA_DIR}/run/mysqld" \
           "${DATA_DIR}/run/nginx/client_body" "${DATA_DIR}/run/nginx/proxy" \
           "${DATA_DIR}/run/nginx/fastcgi" "${DATA_DIR}/run/nginx/uwsgi" \
           "${DATA_DIR}/run/nginx/scgi"

  generate_secrets

  log "  MySQL database : ${MYSQL_DATABASE}"
  log "  MySQL user     : ${MYSQL_USER}"
  log "  NocoDB port    : ${NC_PORT}"
  log "  OPS port       : ${OPS_PORT}"
  log "  Data dir       : ${DATA_DIR}"
  log "=========================================="

  # Initialize MySQL (needs to run before supervisor starts it)
  init_mysql

  # Start MySQL temporarily to bootstrap users
  log "Starting MySQL for bootstrap..."
  mysqld --user=mysql --datadir="${MYSQL_DATA_DIR}" \
         --socket=/data/run/mysqld/mysqld.sock \
         --port=3306 --bind-address=127.0.0.1 --skip-name-resolve &
  local bootstrap_pid=$!

  wait_for_mysql
  setup_mysql_users

  # Stop bootstrap MySQL (supervisor will manage it)
  kill "$bootstrap_pid" 2>/dev/null || true
  wait "$bootstrap_pid" 2>/dev/null || true
  log "MySQL bootstrap complete."

  # Write Redis config
  write_redis_conf

  # Export NocoDB environment
  export_nocodb_env

  # Write environment for supervisor child processes
  cat > "${DATA_DIR}/config/supervisor.env" <<EOF
NC_DB=${NC_DB}
NC_DATA_DIR=${NC_DATA_DIR}
NC_AUTH_JWT_SECRET=${NC_AUTH_JWT_SECRET}
NC_PORT=${NC_PORT}
NC_DISABLE_TELE=${NC_DISABLE_TELE}
NC_REDIS_URL=${NC_REDIS_URL}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
OPS_TOKEN=${OPS_TOKEN}
OPS_PORT=${OPS_PORT}
DATA_DIR=${DATA_DIR}
EOF
  [ -n "${NC_PUBLIC_URL}" ] && echo "NC_PUBLIC_URL=${NC_PUBLIC_URL}" >> "${DATA_DIR}/config/supervisor.env"
  chmod 600 "${DATA_DIR}/config/supervisor.env"

  log "Starting supervisord..."
  exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
}

main "$@"
