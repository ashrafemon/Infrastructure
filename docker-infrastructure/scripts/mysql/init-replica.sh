#!/bin/bash
# =============================================================================
# Automatic MySQL Replica Initialization
# =============================================================================
# Runs inside mysql-replica container on first start.
# Connects to master and starts replication.
# =============================================================================

set -euo pipefail

# Only run if replication is not already configured
if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -q "Source_Host"; then
  exit 0
fi

echo "Setting up MySQL replication from master..."

for i in $(seq 1 30); do
  if mysql -h mysql -u"${REPLICATION_USER:-replicator}" -p"${REPLICATION_PASSWORD:?err}" -e "SELECT 1" &>/dev/null; then
    echo "Master reachable"
    break
  fi
  echo "Waiting for master... ($i/30)"
  sleep 2
done

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='mysql',
    SOURCE_PORT=3306,
    SOURCE_USER='${REPLICATION_USER:-replicator}',
    SOURCE_PASSWORD='${REPLICATION_PASSWORD:?err}',
    SOURCE_AUTO_POSITION=1,
    SOURCE_SSL=0;
  START REPLICA;
EOSQL

echo "MySQL replication started."
