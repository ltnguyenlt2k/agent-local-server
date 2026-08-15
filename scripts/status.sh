#!/usr/bin/env bash
# One-shot health summary: docker services, Ollama reachability, model
# presence, local API, public API. Never prints secrets. If
# ALERT_WEBHOOK_URL is set, POSTs a short summary there on any failure
# (e.g. run this from cron for lightweight monitoring — see docs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_env
cd "$REPO_ROOT"

failures=()

echo "Docker"
for service in postgres litellm cloudflared; do
  line="$(docker compose ps --format '{{.Service}} {{.Health}} {{.State}}' 2>/dev/null | awk -v s="$service" '$1==s')"
  health="$(awk '{print $2}' <<<"$line")"
  state="$(awk '{print $3}' <<<"$line")"
  if [ "$health" = "healthy" ] || { [ -z "$health" ] && [ "$state" = "running" ]; }; then
    printf '  %-12s OK (%s)\n' "$service" "${health:-running}"
  else
    printf '  %-12s FAIL (health=%s state=%s)\n' "$service" "${health:-none}" "${state:-unknown}"
    failures+=("docker:${service}")
  fi
done

echo
echo "Ollama"
OLLAMA_TEST_URL="${OLLAMA_HOST_TEST_URL:-${OLLAMA_BASE_URL:-}}"
if [ -n "$OLLAMA_TEST_URL" ] && curl -fsS --max-time 5 "${OLLAMA_TEST_URL%/}/api/tags" -o /tmp/status-ollama.$$ 2>/dev/null; then
  echo "  reachable    yes"
  if [ -n "${OLLAMA_MODEL:-}" ] && grep -q "\"${OLLAMA_MODEL}" /tmp/status-ollama.$$ 2>/dev/null; then
    echo "  model        ${OLLAMA_MODEL} (found)"
  else
    echo "  model        ${OLLAMA_MODEL:-unset} (NOT found in /api/tags)"
    failures+=("ollama:model-missing")
  fi
else
  echo "  reachable    no"
  failures+=("ollama:unreachable")
fi
rm -f /tmp/status-ollama.$$

echo
echo "Local API"
LITELLM_PORT="${LITELLM_PORT:-4000}"
if curl -fsS --max-time 5 "http://127.0.0.1:${LITELLM_PORT}/health/readiness" >/dev/null 2>&1; then
  echo "  http://127.0.0.1:${LITELLM_PORT}   OK"
else
  echo "  http://127.0.0.1:${LITELLM_PORT}   FAIL"
  failures+=("local-api")
fi

echo
echo "Public API"
if [ -n "${PUBLIC_AI_BASE_URL:-}" ] && [ "${PUBLIC_AI_BASE_URL}" != "https://ai.example.com" ]; then
  if curl -fsS --max-time 10 -o /dev/null "${PUBLIC_AI_BASE_URL%/}/health/readiness" 2>/dev/null; then
    echo "  ${PUBLIC_AI_BASE_URL}   OK"
  else
    echo "  ${PUBLIC_AI_BASE_URL}   FAIL"
    failures+=("public-api")
  fi
else
  echo "  (PUBLIC_AI_BASE_URL not configured yet — skipped)"
fi

echo

if [ "${#failures[@]}" -gt 0 ]; then
  log_fail "Failing checks: ${failures[*]}"
  if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
    payload="$(printf '{"text":"local-ai-gateway status FAIL: %s"}' "${failures[*]}")"
    if curl -fsS -X POST -H "Content-Type: application/json" -d "$payload" "$ALERT_WEBHOOK_URL" >/dev/null 2>&1; then
      log_info "Alert sent to ALERT_WEBHOOK_URL"
    else
      log_warn "Failed to send alert to ALERT_WEBHOOK_URL"
    fi
  fi
  exit 1
fi

log_ok "All checks passed."
