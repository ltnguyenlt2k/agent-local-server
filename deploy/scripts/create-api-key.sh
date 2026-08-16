#!/usr/bin/env bash
# Creates a LiteLLM Virtual API Key for one external client ("App A").
#
# Usage:
#   ./scripts/create-api-key.sh <purpose> [--models m1,m2] [--budget N] [--duration 30d]
#
# Prints the key ONCE. It is never written to disk or logged — copy it
# somewhere safe (password manager / vault) immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat >&2 <<EOF
Usage: $0 <purpose> [--models m1,m2] [--budget N] [--duration 30d]

  <purpose>    Required. Short identifier stored in key metadata, e.g.
               machine-a-app, vscode-agent, ci-client. Use a distinct
               purpose per client so a leaked key can be revoked alone.
  --models     Comma-separated model aliases this key may use.
               Defaults to LITELLM_MODEL_ALIAS from .env.
  --budget     Optional max_budget (USD). 0 is reasonable for a
               local-only model with no real cost.
  --duration   Optional key expiration, e.g. 30d, 12h.
EOF
  exit 1
}

[ $# -ge 1 ] || usage
PURPOSE="$1"; shift

MODELS=""
BUDGET=""
DURATION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --models) MODELS="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    *) usage ;;
  esac
done

load_env
require_env LITELLM_MASTER_KEY
require_env LITELLM_MODEL_ALIAS
require_cmd curl

MODELS="${MODELS:-$LITELLM_MODEL_ALIAS}"
# Build a JSON array like ["local-agent","other-alias"] from a CSV list.
models_json="$(printf '%s' "$MODELS" | awk -F',' '{
  printf "["
  for (i = 1; i <= NF; i++) { printf "%s\"%s\"", (i>1?",":""), $i }
  printf "]"
}')"

payload="$(cat <<JSON
{
  "models": ${models_json},
  "metadata": {"purpose": "${PURPOSE}"}
JSON
)"
[ -n "$BUDGET" ] && payload="${payload},\n  \"max_budget\": ${BUDGET}"
[ -n "$DURATION" ] && payload="${payload},\n  \"duration\": \"${DURATION}\""
payload="$(printf '%b\n}' "$payload")"

LITELLM_PORT="${LITELLM_PORT:-4000}"
log_info "Requesting a Virtual Key for purpose='${PURPOSE}' (models=${MODELS})..."

response="$(curl -sS -X POST "http://127.0.0.1:${LITELLM_PORT}/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "$payload")"

# Extract the key without dumping the full raw response (which may echo
# back other metadata we don't need to show).
key="$(printf '%s' "$response" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("key", ""))
except Exception:
    pass' 2>/dev/null || true)"

if [ -z "$key" ]; then
  log_fail "Could not extract a key from the response — printing raw response for debugging:"
  printf '%s\n' "$response" >&2
  exit 1
fi

BASE_URL_DISPLAY="${PUBLIC_AI_BASE_URL:-<not set — run cloudflare-setup.sh first>}"
[ "$BASE_URL_DISPLAY" = "https://ai.example.com" ] && BASE_URL_DISPLAY="<placeholder — run cloudflare-setup.sh first>"

cat <<EOF

============================================================
  VIRTUAL API KEY — shown once, save it now.
============================================================
  Purpose:    ${PURPOSE}
  Models:     ${MODELS}
  Base URL:   ${BASE_URL_DISPLAY%/}/v1
  API Key:    ${key}
============================================================

This key is NOT stored in this repo and will not be shown again by
this script. If lost, revoke it (./scripts/revoke-key.sh) and issue a
new one — do not try to recover the plaintext value.
EOF
