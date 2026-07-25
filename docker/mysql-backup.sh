#!/usr/bin/env bash
set -euo pipefail

# Periodic logical MySQL backups onto the /data volume.
#
# HF Spaces bucket volumes are FUSE-backed object storage: safe operations
# are create/read/delete of plain files, while rename and unix sockets are
# not supported. Backups are therefore written as new timestamped files
# (never tmp+rename), integrity-checked with gzip -t, and pruned by age.
# entrypoint.sh restores the newest readable dump on every boot.

log() {
  printf '[db-aio-mysql-backup] %s\n' "$*"
}

SOCKET_PATH="${RUN_DIR:-/home/user/run}/mysqld/mysqld.sock"
BACKUP_DIR="${DATA_DIR:-/data}/backups"
BACKUP_INTERVAL="${MYSQL_BACKUP_INTERVAL:-300}"
BACKUP_KEEP="${MYSQL_BACKUP_KEEP:-6}"
MYSQL_DATABASE="${MYSQL_DATABASE:-nocodb}"
MYSQL_USER="${MYSQL_USER:-nocodb}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

dump_once() {
  if [ ! -S "${SOCKET_PATH}" ]; then
    log "MySQL socket not present yet; skipping backup."
    return 0
  fi
  local ts target
  ts="$(date -u +%Y%m%d-%H%M%S)"
  target="${BACKUP_DIR}/nocodb-${ts}.sql.gz"
  if ! mysqldump --socket="${SOCKET_PATH}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
      --single-transaction --quick --databases "${MYSQL_DATABASE}" \
    | gzip -1 > "${target}"; then
    log "WARN: mysqldump failed; removing ${target}."
    rm -f "${target}"
    return 0
  fi
  if ! gzip -t "${target}" 2>/dev/null; then
    log "WARN: ${target} failed gzip integrity check; removing."
    rm -f "${target}"
    return 0
  fi
  log "Backup written: ${target}"
  find "${BACKUP_DIR}" -maxdepth 1 -name 'nocodb-*.sql.gz' -print \
    | sort -r \
    | tail -n +"$((BACKUP_KEEP + 1))" \
    | while read -r old; do
        log "Pruning old backup: ${old}"
        rm -f "${old}"
      done
}

running=true
trap 'running=false' TERM INT

mkdir -p "${BACKUP_DIR}"
log "Starting backup loop: interval=${BACKUP_INTERVAL}s keep=${BACKUP_KEEP} dir=${BACKUP_DIR}"

while [ "${running}" = true ]; do
  sleep "${BACKUP_INTERVAL}" &
  wait $! 2>/dev/null || true
  if [ "${running}" = true ]; then
    dump_once
  fi
done

# Final backup on graceful shutdown (supervisord stops this program before MySQL).
dump_once
log "Stopped."
