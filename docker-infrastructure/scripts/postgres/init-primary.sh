#!/bin/bash
# =============================================================================
# PostgreSQL Primary Initialization
# =============================================================================
# Creates replication user and slot for standby.
# Runs automatically on first primary startup.
# =============================================================================

set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
  CREATE USER ${REPLICATION_USER:-replicator} WITH REPLICATION PASSWORD '${REPLICATION_PASSWORD:?err}';
  SELECT pg_create_physical_replication_slot('replica_slot');
EOSQL

echo "Replication user '${REPLICATION_USER:-replicator}' and slot 'replica_slot' created."
