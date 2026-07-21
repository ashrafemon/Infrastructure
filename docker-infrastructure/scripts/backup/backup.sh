#!/usr/bin/env bash
# =============================================================================
# Backup Script for Docker Infrastructure
# =============================================================================
# Creates timestamped, gzip-compressed backups of all databases and volumes.
# Supports MySQL, PostgreSQL, MongoDB, Redis, MinIO, Jenkins, and Grafana.
#
# Usage:
#   ./backup.sh                         # Backup all services
#   ./backup.sh mysql                   # Backup only MySQL
#   ./backup.sh mysql postgres          # Backup multiple specific services
#   ./backup.sh --dry-run               # Show what would be backed up
#   ./backup.sh --help                  # Show this help message
#
# Configuration via environment variables (from .env):
#   BACKUP_DIR         - Backup destination directory (default: ./backups)
#   BACKUP_RETENTION_DAYS - Days to keep backups (default: 7)
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
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_STR=$(date +%Y-%m-%d)
LOG_FILE="$BACKUP_DIR/backup_$TIMESTAMP.log"

# Container names
MYSQL_CONTAINER="mysql"
POSTGRES_CONTAINER="postgres"
MONGO_CONTAINER="mongo"
REDIS_CONTAINER="redis"
MINIO_CONTAINER="minio"
JENKINS_CONTAINER="jenkins"
GRAFANA_CONTAINER="grafana"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

dry_run=false

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# //g; s/^#$//g' | head -n -1
  exit 0
}

# Parse arguments
if [ $# -eq 0 ]; then
  services_to_backup=("mysql" "postgres" "mongo" "redis" "minio" "jenkins" "grafana")
else
  services_to_backup=()
  for arg in "$@"; do
    case "$arg" in
      --help) usage ;;
      --dry-run) dry_run=true ;;
      --) shift; break ;;
      *) services_to_backup+=("$arg") ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
setup() {
  mkdir -p "$BACKUP_DIR"
  log_info "Backup directory: $BACKUP_DIR"
  log_info "Retention period: $RETENTION_DAYS days"
  log_info "Timestamp: $TIMESTAMP"
  echo "" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Backup handlers
# ---------------------------------------------------------------------------
backup_mysql() {
  log_info "Starting MySQL backup..."
  local backup_file="$BACKUP_DIR/mysql_$TIMESTAMP.sql.gz"
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would backup MySQL to: $backup_file"
    return 0
  fi
  if docker exec "$MYSQL_CONTAINER" mysqladmin ping -u root -p"${MYSQL_ROOT_PASSWORD:?}" --silent 2>/dev/null; then
    docker exec "$MYSQL_CONTAINER" mysqldump \
      --all-databases \
      --single-transaction \
      --routines \
      --triggers \
      --events \
      -u root -p"${MYSQL_ROOT_PASSWORD:?}" 2>/dev/null | gzip > "$backup_file"
    log_ok "MySQL backup completed: $(du -h "$backup_file" | cut -f1)"
  else
    log_warn "MySQL container is not running. Skipping."
  fi
}

backup_postgres() {
  log_info "Starting PostgreSQL backup..."
  local backup_file="$BACKUP_DIR/postgres_$TIMESTAMP.sql.gz"
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would backup PostgreSQL to: $backup_file"
    return 0
  fi
  if docker exec "$POSTGRES_CONTAINER" pg_isready -U "${POSTGRES_USER:-app_user}" &>/dev/null; then
    docker exec "$POSTGRES_CONTAINER" pg_dumpall \
      -U "${POSTGRES_USER:-app_user}" 2>/dev/null | gzip > "$backup_file"
    log_ok "PostgreSQL backup completed: $(du -h "$backup_file" | cut -f1)"
  else
    log_warn "PostgreSQL container is not running. Skipping."
  fi
}

backup_mongo() {
  log_info "Starting MongoDB backup..."
  local backup_dir="$BACKUP_DIR/mongo_$TIMESTAMP"
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would backup MongoDB to: $backup_dir.tar.gz"
    return 0
  fi
  if docker exec "$MONGO_CONTAINER" mongosh --quiet --eval "db.adminCommand('ping')" \
    --username "${MONGO_INITDB_ROOT_USERNAME:-root}" \
    --password "${MONGO_INITDB_ROOT_PASSWORD:?}" \
    --authenticationDatabase admin &>/dev/null; then
    mkdir -p "$backup_dir"
    docker exec "$MONGO_CONTAINER" mongodump \
      --username "${MONGO_INITDB_ROOT_USERNAME:-root}" \
      --password "${MONGO_INITDB_ROOT_PASSWORD:?}" \
      --authenticationDatabase admin \
      --out /tmp/backup 2>&1
    docker cp "$MONGO_CONTAINER:/tmp/backup" "$backup_dir/dump"
    docker exec "$MONGO_CONTAINER" rm -rf /tmp/backup
    tar -czf "${backup_dir}.tar.gz" -C "$BACKUP_DIR" "mongo_$TIMESTAMP" 2>/dev/null
    rm -rf "$backup_dir"
    log_ok "MongoDB backup completed: $(du -h "${backup_dir}.tar.gz" | cut -f1)"
  else
    log_warn "MongoDB container is not running. Skipping."
  fi
}

backup_redis() {
  log_info "Starting Redis backup..."
  local backup_file="$BACKUP_DIR/redis_$TIMESTAMP.rdb"
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would backup Redis to: $backup_file"
    return 0
  fi
  if docker exec "$REDIS_CONTAINER" redis-cli ping &>/dev/null; then
    docker exec "$REDIS_CONTAINER" redis-cli \
      -a "${REDIS_PASSWORD:?}" --no-auth-warning \
      SAVE 2>/dev/null
    docker cp "$REDIS_CONTAINER:/data/dump.rdb" "$backup_file"
    gzip -f "$backup_file"
    log_ok "Redis backup completed: $(du -h "${backup_file}.gz" | cut -f1)"
  else
    log_warn "Redis container is not running. Skipping."
  fi
}

backup_minio() {
  log_info "Starting MinIO backup..."
  local backup_file="$BACKUP_DIR/minio_$TIMESTAMP.tar.gz"
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would backup MinIO data to: $backup_file"
    return 0
  fi
  if docker ps --format '{{.Names}}' | grep -q "^${MINIO_CONTAINER}$"; then
    docker run --rm \
      --volumes-from "$MINIO_CONTAINER" \
      -v "$BACKUP_DIR:/backup" \
      alpine:3.21 \
      tar -czf "/backup/minio_$TIMESTAMP.tar.gz" /data 2>/dev/null
    log_ok "MinIO backup completed: $(du -h "$backup_file" | cut -f1)"
  else
    log_warn "MinIO container is not running. Skipping."
  fi
}

backup_jenkins() {
  log_info "Starting Jenkins backup..."
  local backup_file="$BACKUP_DIR/jenkins_$TIMESTAMP.tar.gz"
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would backup Jenkins to: $backup_file"
    return 0
  fi
  if docker ps --format '{{.Names}}' | grep -q "^${JENKINS_CONTAINER}$"; then
    docker run --rm \
      --volumes-from "$JENKINS_CONTAINER" \
      -v "$BACKUP_DIR:/backup" \
      alpine:3.21 \
      tar -czf "/backup/jenkins_$TIMESTAMP.tar.gz" /var/jenkins_home 2>/dev/null
    log_ok "Jenkins backup completed: $(du -h "$backup_file" | cut -f1)"
  else
    log_warn "Jenkins container is not running. Skipping."
  fi
}

backup_grafana() {
  log_info "Starting Grafana backup..."
  local backup_file="$BACKUP_DIR/grafana_$TIMESTAMP.tar.gz"
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would backup Grafana to: $backup_file"
    return 0
  fi
  if docker ps --format '{{.Names}}' | grep -q "^${GRAFANA_CONTAINER}$"; then
    docker run --rm \
      --volumes-from "$GRAFANA_CONTAINER" \
      -v "$BACKUP_DIR:/backup" \
      alpine:3.21 \
      tar -czf "/backup/grafana_$TIMESTAMP.tar.gz" /var/lib/grafana 2>/dev/null
    log_ok "Grafana backup completed: $(du -h "$backup_file" | cut -f1)"
  else
    log_warn "Grafana container is not running. Skipping."
  fi
}

# ---------------------------------------------------------------------------
# Cleanup old backups
# ---------------------------------------------------------------------------
cleanup() {
  log_info "Cleaning up backups older than $RETENTION_DAYS days..."
  if [ "$dry_run" = true ]; then
    log_info "[DRY-RUN] Would remove backups older than $RETENTION_DAYS days"
    return 0
  fi
  find "$BACKUP_DIR" -name "*.gz" -o -name "*.tar.gz" | while read -r f; do
    if [ -f "$f" ] && [ "$(find "$f" -mtime +"$RETENTION_DAYS" -print)" ]; then
      rm -f "$f"
      log_info "Removed old backup: $f"
    fi
  done
  log_ok "Cleanup completed."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo "==========================================" | tee "$LOG_FILE"
  echo "  Infrastructure Backup - $(date)" | tee -a "$LOG_FILE"
  echo "==========================================" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"

  setup

  for service in "${services_to_backup[@]}"; do
    case "$service" in
      mysql)    backup_mysql ;;
      postgres) backup_postgres ;;
      mongo)    backup_mongo ;;
      redis)    backup_redis ;;
      minio)    backup_minio ;;
      jenkins)  backup_jenkins ;;
      grafana)  backup_grafana ;;
      *)        log_warn "Unknown service: $service. Skipping." ;;
    esac
  done

  echo "" | tee -a "$LOG_FILE"
  cleanup
  echo "" | tee -a "$LOG_FILE"
  log_ok "Backup process completed. Log: $LOG_FILE"
}

main
