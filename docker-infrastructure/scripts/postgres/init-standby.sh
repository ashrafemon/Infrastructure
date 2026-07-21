#!/bin/bash
# =============================================================================
# Automatic PostgreSQL Standby Initialization
# =============================================================================
# Runs inside postgres-replica container on first start.
# Clones primary data via pg_basebackup and starts as hot standby.
# =============================================================================

set -euo pipefail

export PGPASSWORD="${REPLICATION_PASSWORD:?err}"

# Find the PostgreSQL data directory
# Postgres 18+ uses major-version-specific dirs under /var/lib/postgresql
PG_BASE="/var/lib/postgresql"
PG_DATA=$(ls -d "$PG_BASE"/*/main 2>/dev/null || echo "$PG_BASE/18/main")

# Only run if data directory is empty (first start)
if [ -f "$PG_DATA/PG_VERSION" ]; then
  exit 0
fi

echo "Setting up PostgreSQL streaming replication from primary..."

for i in $(seq 1 60); do
  if pg_isready -h postgres -U "${POSTGRES_USER:-postgres}" &>/dev/null; then
    echo "Primary reachable"
    break
  fi
  echo "Waiting for primary... ($i/60)"
  sleep 2
done

rm -rf "$PG_BASE"/* 2>/dev/null || true
mkdir -p "$PG_DATA"

pg_basebackup -h postgres -D "$PG_DATA" -U "${REPLICATION_USER:-replicator}" \
  -v -P --wal-method=stream --slot=replica_slot 2>&1

touch "$PG_DATA/standby.signal"

echo "PostgreSQL standby initialized."
