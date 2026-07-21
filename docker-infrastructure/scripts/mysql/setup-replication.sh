#!/bin/bash
# =============================================================================
# MySQL Replication Setup
# =============================================================================
# Runs on master container to create replication user.
# Replica must connect and start replication manually:
#   CHANGE REPLICATION SOURCE TO
#     SOURCE_HOST='mysql',
#     SOURCE_USER='replicator',
#     SOURCE_PASSWORD='<password>',
#     SOURCE_AUTO_POSITION=1;
#   START REPLICA;
# =============================================================================

set -euo pipefail

if [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
  echo "ERROR: MYSQL_ROOT_PASSWORD not set"
  exit 1
fi

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
  CREATE USER IF NOT EXISTS '${REPLICATION_USER:-replicator}'@'%'
    IDENTIFIED BY '${REPLICATION_PASSWORD:?err}';
  GRANT REPLICATION SLAVE ON *.* TO '${REPLICATION_USER:-replicator}'@'%';
  FLUSH PRIVILEGES;
EOSQL

echo "Replication user '${REPLICATION_USER:-replicator}' created."
