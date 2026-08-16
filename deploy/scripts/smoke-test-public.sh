#!/usr/bin/env bash
# Smoke tests against the PUBLIC Cloudflare-tunneled endpoint. Run this
# from a different network than machine B when possible (e.g. a laptop
# on mobile data), not just from machine B itself — see spec §25.
#
# Usage: AI_KEY=<virtual-key> ./scripts/smoke-test-public.sh
#        ./scripts/smoke-test-public.sh --key <virtual-key>
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
[ -n "$AI_KEY" ] || die "Pass a Virtual Key via AI_KEY env var or --key"

if [ -z "${PUBLIC_AI_BASE_URL:-}" ] || [ "${PUBLIC_AI_BASE_URL}" = "https://ai.example.com" ]; then
  die "PUBLIC_AI_BASE_URL in .env is still the placeholder — set it to your real Cloudflare hostname first"
fi

BASE_URL="${PUBLIC_AI_BASE_URL%/}"
fail_count=0

check() {
  local name="$1" expected="$2"; shift 2
  local status
  status="$(curl -sS -o /tmp/smoke-public-body.$$ -w '%{http_code}' --max-time 30 "$@" || true)"
  if [ "$status" = "$expected" ]; then
    log_ok "$name (HTTP $status)"
  else
    log_fail "$name — expected HTTP $expected, got $status. Body:"
    cat /tmp/smoke-public-body.$$ >&2
    fail_count=$((fail_count + 1))
  fi
  rm -f /tmp/smoke-public-body.$$
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

response="$(curl -sS --max-time 60 -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${AI_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"'"${LITELLM_MODEL_ALIAS}"'","messages":[{"role":"user","content":"Reply exactly with: PUBLIC_AI_OK"}]}')"

if printf '%s' "$response" | grep -q "PUBLIC_AI_OK"; then
  log_ok "valid key -> model inference succeeded over the public endpoint (found PUBLIC_AI_OK)"
else
  log_fail "valid key request did not return PUBLIC_AI_OK. Response:"
  printf '%s\n' "$response" >&2
  fail_count=$((fail_count + 1))
fi

if [ "$fail_count" -gt 0 ]; then
  log_fail "${fail_count} check(s) failed"
  exit 1
fi
log_ok "All public smoke tests passed. Run this again from a different network to confirm, not just from machine B."
