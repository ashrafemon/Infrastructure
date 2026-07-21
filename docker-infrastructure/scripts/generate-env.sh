#!/usr/bin/env bash
# =============================================================================
# .env Generator
# =============================================================================
# First run:  generates ALL passwords and creates .env from .env.example
# Later runs: regenerate a single password by name
#
# Usage:
#   ./scripts/generate-env.sh              # First run: generate everything
#   ./scripts/generate-env.sh mysql         # Regenerate only MYSQL_ROOT_PASSWORD
#   ./scripts/generate-env.sh redis grafana # Regenerate specific ones
#
# Secret names: mysql, postgres, mongo, redis, rabbitmq, minio, grafana,
#               pgadmin, crowdsec, postfix
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
ENV_EXAMPLE="$SCRIPT_DIR/../.env.example"

gen() { openssl rand -base64 32 | tr -d '\n'; }

update() {
  local key="$1" pass
  pass=$(gen)
  python3 - "$key" "$pass" "$ENV_FILE" <<'PYEOF'
import sys, re
key, val, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'r') as f:
    content = f.read()
content = re.sub(r'^' + re.escape(key) + r'=.*', key + '=' + val, content, flags=re.MULTILINE)
with open(path, 'w') as f:
    f.write(content)
PYEOF
  echo "  Updated $key"
}

if [ ! -f "$ENV_FILE" ]; then
  [ -f "$ENV_EXAMPLE" ] || { echo "ERROR: .env.example not found"; exit 1; }
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  echo "Created $ENV_FILE from .env.example"
fi

if [ $# -eq 0 ]; then
  echo "Generating all passwords..."
  for k in MYSQL_ROOT_PASSWORD POSTGRES_PASSWORD MONGO_INITDB_ROOT_PASSWORD \
           REDIS_PASSWORD RABBITMQ_PASSWORD MINIO_ROOT_PASSWORD \
           GF_SECURITY_ADMIN_PASSWORD PGADMIN_DEFAULT_PASSWORD \
           CROWDSEC_AGENT_PASSWORD POSTFIX_SMTP_PASSWORD \
           ARCANE_JWT_SECRET ARCANE_ENCRYPTION_KEY; do
    update "$k"
  done
  chmod 0600 "$ENV_FILE" 2>/dev/null || true
  echo "Done. All passwords saved to .env"
  echo "Backend projects that use these passwords must be updated."
  exit 0
fi

for name in "$@"; do
  case "$name" in
    mysql)    update MYSQL_ROOT_PASSWORD ;;
    postgres) update POSTGRES_PASSWORD ;;
    mongo)    update MONGO_INITDB_ROOT_PASSWORD ;;
    redis)    update REDIS_PASSWORD ;;
    rabbitmq) update RABBITMQ_PASSWORD ;;
    minio)    update MINIO_ROOT_PASSWORD ;;
    grafana)  update GF_SECURITY_ADMIN_PASSWORD ;;
    pgadmin)  update PGADMIN_DEFAULT_PASSWORD ;;
    crowdsec) update CROWDSEC_AGENT_PASSWORD ;;
     postfix)  update POSTFIX_SMTP_PASSWORD ;;
     arcane)   update ARCANE_JWT_SECRET; update ARCANE_ENCRYPTION_KEY ;;
    *) echo "  Unknown: $name (valid: mysql, postgres, mongo, redis, rabbitmq, minio, grafana, pgadmin, crowdsec, postfix, arcane)" ;;
  esac
done
