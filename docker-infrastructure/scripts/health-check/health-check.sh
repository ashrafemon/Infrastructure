#!/usr/bin/env bash
# =============================================================================
# Health Check Script for Docker Infrastructure
# =============================================================================
# Verifies all services are running and healthy.
#
# Usage:
#   ./health-check.sh                        # Check all services
#   ./health-check.sh mysql rabbitmq         # Check specific services
#   ./health-check.sh --json                 # JSON output
#   ./health-check.sh --help                 # Show this help message
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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

output_json=false

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# //g; s/^#$//g' | head -n -1
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) usage ;;
    --json) output_json=true; shift ;;
    *) services+=("$1"); shift ;;
  esac
done

# All infrastructure services (in dependency order)
ALL_SERVICES=(
  mysql postgres mongo redis
  phpmyadmin pgadmin redisinsight
  rabbitmq
  minio
  mailpit
  prometheus grafana loki promtail
  nginx-proxy-manager
  crowdsec uptime-kuma
  jenkins
  arcane watchtower
)

CONTAINER_NAMES=(
  mysql postgres mongo redis
  phpmyadmin pgadmin redisinsight
  rabbitmq
  minio
  mailpit
  prometheus grafana loki promtail
  nginx-proxy-manager
  crowdsec uptime-kuma
  jenkins
  arcane watchtower
)

if [ ${#services[@]} -eq 0 ]; then
  services=("${ALL_SERVICES[@]}")
fi

check_service() {
  local service="$1"
  local container="$1"

  if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
    echo "{\"service\":\"$service\",\"status\":\"stopped\",\"healthy\":false}"
    return 1
  fi

  local state
  state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")

  if [ "$state" != "running" ]; then
    echo "{\"service\":\"$service\",\"status\":\"$state\",\"healthy\":false}"
    return 1
  fi

  local health
  health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "none")

  if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
    echo "{\"service\":\"$service\",\"status\":\"$state\",\"healthy\":true}"
    return 0
  else
    echo "{\"service\":\"$service\",\"status\":\"$state\",\"healthy\":false}"
    return 1
  fi
}

print_plain() {
  printf "%-25s %-12s %s\n" "Service" "Status" "Health"
  printf "%-25s %-12s %s\n" "-------" "------" "------"
  while IFS= read -r line; do
    local name status healthy
    name=$(echo "$line" | jq -r '.service')
    status=$(echo "$line" | jq -r '.status')
    healthy=$(echo "$line" | jq -r '.healthy')

    if [ "$healthy" = "true" ]; then
      printf "%-25s %-12s %s%s%s\n" "$name" "$status" "${GREEN}" "Healthy" "${NC}"
    else
      printf "%-25s %-12s %s%s%s\n" "$name" "$status" "${RED}" "Unhealthy" "${NC}"
    fi
  done < <(printf "%s\n" "$@")
}

print_json() {
  local results=()
  while IFS= read -r line; do
    results+=("$line")
  done < <(printf "%s\n" "$@")
  jq -n '{timestamp: now, services: [$results | .[]] | fromjson}'
}

results=()
failed=0

for svc in "${services[@]}"; do
  result=$(check_service "$svc")
  results+=("$result")
  if ! echo "$result" | jq -e '.healthy' > /dev/null 2>&1; then
    ((failed++))
  fi
done

if [ "$output_json" = true ]; then
  print_json "${results[@]}"
else
  echo "Infrastructure Health Check - $(date)"
  echo "========================================"
  print_plain "${results[@]}"
  echo ""
  local total=${#services[@]}
  if [ "$failed" -eq 0 ]; then
    echo -e "${GREEN}All $total services are healthy.${NC}"
  else
    echo -e "${RED}$failed/$total services have issues.${NC}"
  fi
fi

exit "$failed"
