#!/bin/bash
# =============================================================================
# Automatic PostgreSQL Standby Initialization
# =============================================================================
# Runs inside postgres-replica container on first start.
# Clones primary data via pg_basebackup and starts as hot standby.
# =============================================================================

set -euo pipefail

PG_DATA="/var/lib/postgresql/data"
export PGPASSWORD="${REPLICATION_PASSWORD:?err}"

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

rm -rf "$PG_DATA"/* 2>/dev/null || true
pg_basebackup -h postgres -D "$PG_DATA" -U "${REPLICATION_USER:-replicator}" \
  -v -P --wal-method=stream --slot=replica_slot 2>&1

# Create standby signal file
touch "$PG_DATA/standby.signal"

# Add connection info to postgresql.conf
cat >> "$PG_DATA/postgresql.conf" <<-EOCONF
  primary_conninfo = 'host=postgres port=5432 user=${REPLICATION_USER:-replicator} password=${REPLICATION_PASSWORD:?err} application_name=postgres-replica'
  primary_slot_name = 'replica_slot'
  hot_standby = on
EOCONF

echo "PostgreSQL standby initialized. Data cloned from primary."
