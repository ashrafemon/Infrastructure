#!/usr/bin/env bash
# =============================================================================
# Restore Script for Docker Infrastructure
# =============================================================================
# Restores databases and volumes from backup files.
#
# Usage:
#   ./restore.sh                               # Interactive mode
#   ./restore.sh mysql /path/to/backup.sql.gz  # Restore specific service
#   ./restore.sh --list                        # List available backups
#   ./restore.sh --help                        # Show this help message
#
# WARNING: Restoring will overwrite existing data!
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/.env"
  set +a
fi

BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# //g; s/^#$//g' | head -n -1
  exit 0
}

list_backups() {
  echo "Available backups in $BACKUP_DIR:"
  echo ""
  for pattern in "mysql_*.sql.gz" "postgres_*.sql.gz" "mongo_*.tar.gz" "redis_*.rdb.gz" "minio_*.tar.gz" "jenkins_*.tar.gz" "grafana_*.tar.gz"; do
    find "$BACKUP_DIR" -maxdepth 1 -name "$pattern" -exec ls -lh {} \; 2>/dev/null
  done
  exit 0
}

if [ $# -eq 0 ]; then
  list_backups
fi

case "${1:-}" in
  --help) usage ;;
  --list) list_backups ;;
esac

SERVICE="${1:-}"
BACKUP_FILE="${2:-}"

if [ -z "$SERVICE" ] || [ -z "$BACKUP_FILE" ]; then
  log_err "Usage: $0 <service> <backup_file>"
  log_err "Run '$0 --list' to see available backups."
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  log_err "Backup file not found: $BACKUP_FILE"
  exit 1
fi

log_warn "You are about to restore $SERVICE from $BACKUP_FILE"
log_warn "This will OVERWRITE existing data!"
echo ""
read -rp "Are you sure you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  log_info "Restore cancelled."
  exit 0
fi

restore_mysql() {
  log_info "Restoring MySQL..."
  if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" | docker exec -i mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD:?}"
  else
    docker exec -i mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD:?}" < "$BACKUP_FILE"
  fi
  log_ok "MySQL restore completed."
}

restore_postgres() {
  log_info "Restoring PostgreSQL..."
  if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" | docker exec -i postgres psql -U "${POSTGRES_USER:-app_user}"
  else
    docker exec -i postgres psql -U "${POSTGRES_USER:-app_user}" < "$BACKUP_FILE"
  fi
  log_ok "PostgreSQL restore completed."
}

restore_mongo() {
  log_info "Restoring MongoDB..."
  local tmp_dir="/tmp/mongo_restore_$(date +%s)"
  mkdir -p "$tmp_dir"
  tar -xzf "$BACKUP_FILE" -C "$tmp_dir"
  local dump_dir
  dump_dir=$(find "$tmp_dir" -type d -name "dump" | head -1)
  if [ -z "$dump_dir" ]; then
    log_err "Could not find 'dump' directory in the backup archive."
    rm -rf "$tmp_dir"
    exit 1
  fi
  docker cp "$dump_dir" mongo:/tmp/dump_restore
  docker exec mongo mongorestore \
    --username "${MONGO_INITDB_ROOT_USERNAME:-root}" \
    --password "${MONGO_INITDB_ROOT_PASSWORD:?}" \
    --authenticationDatabase admin \
    /tmp/dump_restore
  docker exec mongo rm -rf /tmp/dump_restore
  rm -rf "$tmp_dir"
  log_ok "MongoDB restore completed."
}

restore_redis() {
  log_info "Restoring Redis..."
  local rdb_file=""
  if [[ "$BACKUP_FILE" == *.gz ]]; then
    rdb_file="${BACKUP_FILE%.gz}"
    gunzip -k "$BACKUP_FILE"
  else
    rdb_file="$BACKUP_FILE"
  fi
  docker cp "$rdb_file" redis:/data/dump.rdb
  docker exec redis redis-cli -a "${REDIS_PASSWORD:?}" --no-auth-warning SHUTDOWN SAVE
  docker start redis
  log_ok "Redis restore completed. Container restarted."
}

restore_volume() {
  local service="$1"
  local volume_name="$2"
  local container_name="$3"
  local container_path="$4"
  log_info "Restoring $service volume..."
  docker run --rm \
    -v "$volume_name:$container_path" \
    -v "$BACKUP_FILE:/backup/restore.tar.gz" \
    alpine:3.21 \
    sh -c "rm -rf ${container_path:?}/* && tar -xzf /backup/restore.tar.gz -C $container_path --strip-components=1"
  log_ok "$service volume restore completed."
}

case "$SERVICE" in
  mysql)
    restore_mysql
    ;;
  postgres)
    restore_postgres
    ;;
  mongo)
    restore_mongo
    ;;
  redis)
    restore_redis
    ;;
  minio)
    restore_volume "MinIO" "minio_data" "minio" "/data"
    ;;
  jenkins)
    restore_volume "Jenkins" "jenkins_home" "jenkins" "/var/jenkins_home"
    ;;
  grafana)
    restore_volume "Grafana" "grafana_data" "grafana" "/var/lib/grafana"
    ;;
  *)
    log_err "Unknown service: $SERVICE"
    log_err "Supported: mysql, postgres, mongo, redis, minio, jenkins, grafana"
    exit 1
    ;;
esac

log_ok "Restore completed successfully."
