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
: "${PORT:=${NC_PORT}}"
: "${NC_DISABLE_TELE:=true}"
: "${NC_PUBLIC_URL:=}"
: "${NC_SITE_URL:=${NC_PUBLIC_URL}}"
: "${OPS_PORT:=8081}"
: "${OPS_TOKEN:=}"
: "${REDIS_PORT:=6379}"

export DATA_DIR MYSQL_DATABASE MYSQL_USER NC_PORT PORT NC_DISABLE_TELE OPS_PORT OPS_TOKEN REDIS_PORT

MYSQL_DATA_DIR="${DATA_DIR}/mysql"
NOCODB_DATA_DIR="${DATA_DIR}/nocodb"
MYSQL_ROOT_AUTH="unknown"

write_shell_env() {
  local name="$1"
  local value="$2"
  printf '%s=%q\n' "$name" "$value"
}

validate_mysql_name() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[A-Za-z0-9_]+$ ]]; then
    log "ERROR: ${name} must contain only letters, numbers, and underscores."
    return 1
  fi
}

validate_fixed_port() {
  local name="$1"
  local value="$2"
  local expected="$3"
  if [ "${value}" != "${expected}" ]; then
    log "ERROR: ${name} must stay ${expected}; nginx.conf uses fixed internal routing."
    return 1
  fi
}

sql_quote() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\'/\'\'}
  printf "'%s'" "$value"
}

urlencode() {
  printf '%s' "$1" | python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))'
}

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
  MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-${_GEN_MYSQL_ROOT_PASSWORD:-$(openssl rand -hex 24)}}"
  MYSQL_PASSWORD="${MYSQL_PASSWORD:-${_GEN_MYSQL_PASSWORD:-$(openssl rand -hex 24)}}"
  NC_AUTH_JWT_SECRET="${NC_AUTH_JWT_SECRET:-${_GEN_NC_AUTH_JWT_SECRET:-$(openssl rand -base64 42)}}"
  OPS_TOKEN="${OPS_TOKEN:-${_GEN_OPS_TOKEN:-$(openssl rand -hex 16)}}"

  {
    write_shell_env "_GEN_MYSQL_ROOT_PASSWORD" "${MYSQL_ROOT_PASSWORD}"
    write_shell_env "_GEN_MYSQL_PASSWORD" "${MYSQL_PASSWORD}"
    write_shell_env "_GEN_NC_AUTH_JWT_SECRET" "${NC_AUTH_JWT_SECRET}"
    write_shell_env "_GEN_OPS_TOKEN" "${OPS_TOKEN}"
  } > "${DATA_DIR}/config/generated.env"
  chmod 600 "${DATA_DIR}/config/generated.env"

  export MYSQL_ROOT_PASSWORD MYSQL_PASSWORD NC_AUTH_JWT_SECRET OPS_TOKEN
}

# ═══════════════════════════════════════════════════════════════════════════════
# MySQL initialization
# ═══════════════════════════════════════════════════════════════════════════════

init_mysql() {
  if [ ! -d "${MYSQL_DATA_DIR}/mysql" ]; then
    log "Initializing MySQL data directory..."
    if [ -n "$(find "${MYSQL_DATA_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      log "Removing incomplete MySQL data directory contents..."
      find "${MYSQL_DATA_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
    if ! mysqld --initialize-insecure --datadir="${MYSQL_DATA_DIR}" \
           --log-error="${DATA_DIR}/logs/mysql-error.log"; then
      log "ERROR: MySQL initialization failed. Last MySQL error log:"
      tail -200 "${DATA_DIR}/logs/mysql-error.log" 2>/dev/null || true
      return 1
    fi
  fi
  chmod -R u+rwX "${MYSQL_DATA_DIR}" "${DATA_DIR}/run/mysqld" 2>/dev/null || true
}

wait_for_mysql() {
  log "Waiting for MySQL to be ready..."
  local _
  for _ in $(seq 1 60); do
    if mysqladmin ping --socket=/data/run/mysqld/mysqld.sock --silent 2>/dev/null; then
      log "MySQL is ready."
      return 0
    fi
    sleep 1
  done
  log "ERROR: MySQL failed to start within 60 seconds."
  log "Last MySQL error log:"
  tail -200 "${DATA_DIR}/logs/mysql-error.log" 2>/dev/null || true
  return 1
}

detect_mysql_root_auth() {
  if mysql --socket=/data/run/mysqld/mysqld.sock -u root -p"${MYSQL_ROOT_PASSWORD}" \
      --connect-expired-password -e "SELECT 1" >/dev/null 2>&1; then
    MYSQL_ROOT_AUTH="password"
    return 0
  fi

  if mysql --socket=/data/run/mysqld/mysqld.sock -u root \
      --connect-expired-password -e "SELECT 1" >/dev/null 2>&1; then
    MYSQL_ROOT_AUTH="none"
    return 0
  fi

  log "ERROR: Unable to authenticate as MySQL root. If /data is reused, keep MYSQL_ROOT_PASSWORD consistent."
  return 1
}

run_mysql_root() {
  case "${MYSQL_ROOT_AUTH}" in
    password)
      mysql --socket=/data/run/mysqld/mysqld.sock -u root -p"${MYSQL_ROOT_PASSWORD}"
      ;;
    none)
      mysql --socket=/data/run/mysqld/mysqld.sock -u root
      ;;
    *)
      log "ERROR: MySQL root auth mode was not detected."
      return 1
      ;;
  esac
}

setup_mysql_users() {
  validate_mysql_name "MYSQL_DATABASE" "${MYSQL_DATABASE}"
  validate_mysql_name "MYSQL_USER" "${MYSQL_USER}"

  local root_password_sql
  local mysql_password_sql
  root_password_sql="$(sql_quote "${MYSQL_ROOT_PASSWORD}")"
  mysql_password_sql="$(sql_quote "${MYSQL_PASSWORD}")"

  log "Configuring MySQL database and user..."
  run_mysql_root <<-EOSQL
    ALTER USER 'root'@'localhost' IDENTIFIED BY ${root_password_sql};
    CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY ${mysql_password_sql};
    CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY ${mysql_password_sql};
    ALTER USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY ${mysql_password_sql};
    ALTER USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY ${mysql_password_sql};
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
  local mysql_user_url
  local mysql_password_url
  local mysql_database_url
  mysql_user_url="$(urlencode "${MYSQL_USER}")"
  mysql_password_url="$(urlencode "${MYSQL_PASSWORD}")"
  mysql_database_url="$(urlencode "${MYSQL_DATABASE}")"

  export NC_DB="mysql2://127.0.0.1:3306?u=${mysql_user_url}&p=${mysql_password_url}&d=${mysql_database_url}"
  export NC_APP_DATA_DIR="${NOCODB_DATA_DIR}"
  export NC_AUTH_JWT_SECRET
  export PORT
  export NC_DISABLE_TELE
  export NC_CACHE_REDIS_URL="redis://127.0.0.1:${REDIS_PORT}"
  export NC_REDIS_URL="${NC_CACHE_REDIS_URL}"
  if [ -n "${NC_SITE_URL}" ]; then
    export NC_SITE_URL
    export NC_PUBLIC_URL="${NC_SITE_URL}"
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
  validate_fixed_port "PORT" "${PORT}" "8080"
  validate_fixed_port "OPS_PORT" "${OPS_PORT}" "8081"

  log "  MySQL database : ${MYSQL_DATABASE}"
  log "  MySQL user     : ${MYSQL_USER}"
  log "  NocoDB port    : ${PORT}"
  log "  OPS port       : ${OPS_PORT}"
  log "  Data dir       : ${DATA_DIR}"
  log "=========================================="

  # Initialize MySQL (needs to run before supervisor starts it)
  init_mysql

  # Start MySQL temporarily to bootstrap users
  log "Starting MySQL for bootstrap..."
  mysqld --datadir="${MYSQL_DATA_DIR}" \
         --socket=/data/run/mysqld/mysqld.sock \
         --pid-file=/data/run/mysqld/mysqld.pid \
         --port=3306 --bind-address=127.0.0.1 --skip-name-resolve \
         --mysqlx=0 \
         --log-error="${DATA_DIR}/logs/mysql-error.log" &
  local bootstrap_pid=$!
  trap 'kill "${bootstrap_pid:-}" 2>/dev/null || true; wait "${bootstrap_pid:-}" 2>/dev/null || true' EXIT

  wait_for_mysql
  detect_mysql_root_auth
  setup_mysql_users

  # Stop bootstrap MySQL (supervisor will manage it)
  trap - EXIT
  kill "$bootstrap_pid" 2>/dev/null || true
  wait "$bootstrap_pid" 2>/dev/null || true
  log "MySQL bootstrap complete."

  # Write Redis config
  write_redis_conf

  # Export NocoDB environment
  export_nocodb_env

  # This file is for diagnostics; supervisord inherits the exported environment.
  {
    write_shell_env "NC_DB" "${NC_DB}"
    write_shell_env "NC_APP_DATA_DIR" "${NC_APP_DATA_DIR}"
    write_shell_env "NC_AUTH_JWT_SECRET" "${NC_AUTH_JWT_SECRET}"
    write_shell_env "PORT" "${PORT}"
    write_shell_env "NC_DISABLE_TELE" "${NC_DISABLE_TELE}"
    write_shell_env "NC_CACHE_REDIS_URL" "${NC_CACHE_REDIS_URL}"
    write_shell_env "NC_REDIS_URL" "${NC_REDIS_URL}"
    write_shell_env "MYSQL_ROOT_PASSWORD" "${MYSQL_ROOT_PASSWORD}"
    write_shell_env "MYSQL_DATABASE" "${MYSQL_DATABASE}"
    write_shell_env "MYSQL_USER" "${MYSQL_USER}"
    write_shell_env "MYSQL_PASSWORD" "${MYSQL_PASSWORD}"
    write_shell_env "OPS_TOKEN" "${OPS_TOKEN}"
    write_shell_env "OPS_PORT" "${OPS_PORT}"
    write_shell_env "DATA_DIR" "${DATA_DIR}"
    [ -n "${NC_SITE_URL}" ] && write_shell_env "NC_SITE_URL" "${NC_SITE_URL}"
  } > "${DATA_DIR}/config/supervisor.env"
  chmod 600 "${DATA_DIR}/config/supervisor.env"

  log "Starting supervisord..."
  exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
}

main "$@"
