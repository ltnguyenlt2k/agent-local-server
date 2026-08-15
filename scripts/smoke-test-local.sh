#!/usr/bin/env bash
# Smoke tests against the LOCAL LiteLLM endpoint (127.0.0.1). Run this
# before setting up Cloudflare — it isolates gateway/Ollama problems
# from tunnel/DNS problems (see docs/troubleshooting.md).
#
# Usage: AI_KEY=<virtual-key> ./scripts/smoke-test-local.sh
#        ./scripts/smoke-test-local.sh --key <virtual-key>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

AI_KEY="${AI_KEY:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --key) AI_KEY="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

load_env
require_env LITELLM_MODEL_ALIAS
require_cmd curl
[ -n "$AI_KEY" ] || die "Pass a Virtual Key via AI_KEY env var or --key (get one with ./scripts/create-api-key.sh)"

LITELLM_PORT="${LITELLM_PORT:-4000}"
BASE_URL="http://127.0.0.1:${LITELLM_PORT}"

fail_count=0

check() { # check <name> <expected-status> <curl-args...>
  local name="$1" expected="$2"; shift 2
  local status
  status="$(curl -sS -o /tmp/smoke-local-body.$$ -w '%{http_code}' "$@" || true)"
  if [ "$status" = "$expected" ]; then
    log_ok "$name (HTTP $status)"
  else
    log_fail "$name — expected HTTP $expected, got $status. Body:"
    cat /tmp/smoke-local-body.$$ >&2
    fail_count=$((fail_count + 1))
  fi
  rm -f /tmp/smoke-local-body.$$
}

log_info "Target: ${BASE_URL}"

check "unauthorized request rejected" "401" \
  -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"'"${LITELLM_MODEL_ALIAS}"'","messages":[{"role":"user","content":"hi"}]}'

check "invalid key rejected" "401" \
  -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer sk-invalid-not-a-real-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"'"${LITELLM_MODEL_ALIAS}"'","messages":[{"role":"user","content":"hi"}]}'

response="$(curl -sS -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${AI_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"'"${LITELLM_MODEL_ALIAS}"'","messages":[{"role":"user","content":"Reply exactly with: LOCAL_AI_OK"}]}')"

if printf '%s' "$response" | grep -q "LOCAL_AI_OK"; then
  log_ok "valid key -> model inference succeeded (found LOCAL_AI_OK)"
else
  log_fail "valid key request did not return LOCAL_AI_OK. Response:"
  printf '%s\n' "$response" >&2
  fail_count=$((fail_count + 1))
fi

if [ "$fail_count" -gt 0 ]; then
  log_fail "${fail_count} check(s) failed"
  exit 1
fi
log_ok "All local smoke tests passed."
