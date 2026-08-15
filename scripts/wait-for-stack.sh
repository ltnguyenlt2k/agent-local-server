#!/usr/bin/env bash
# Polls `docker compose ps` until postgres/litellm/cloudflared all report
# healthy, or a timeout is hit. Intended to run right after
# `docker compose up -d`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-120}"
INTERVAL_SECONDS=5
SERVICES=(postgres litellm cloudflared)

cd "$REPO_ROOT"

service_status() {
  local service="$1"
  docker compose ps --format '{{.Service}} {{.Health}} {{.State}}' 2>/dev/null \
    | awk -v s="$service" '$1 == s { print $2, $3 }'
}

elapsed=0
while [ "$elapsed" -lt "$TIMEOUT_SECONDS" ]; do
  all_ready=true
  for service in "${SERVICES[@]}"; do
    read -r health state <<<"$(service_status "$service")"
    if [ "$health" = "healthy" ]; then
      continue
    fi
    # Services without a healthcheck report empty health; accept "running".
    if [ -z "$health" ] && [ "$state" = "running" ]; then
      continue
    fi
    all_ready=false
  done
  if $all_ready; then
    log_ok "postgres, litellm, cloudflared are all up"
    exit 0
  fi
  sleep "$INTERVAL_SECONDS"
  elapsed=$((elapsed + INTERVAL_SECONDS))
done

log_fail "timed out after ${TIMEOUT_SECONDS}s waiting for the stack to become healthy"
for service in "${SERVICES[@]}"; do
  read -r health state <<<"$(service_status "$service")"
  printf '  %-12s health=%-10s state=%s\n' "$service" "${health:-none}" "${state:-unknown}"
done
log_info "Check logs: docker compose logs -f <service>"
exit 1
