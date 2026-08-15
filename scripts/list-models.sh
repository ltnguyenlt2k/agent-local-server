#!/usr/bin/env bash
# Lists model aliases currently configured/reachable via this gateway.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_env
require_env LITELLM_MASTER_KEY
require_cmd curl

LITELLM_PORT="${LITELLM_PORT:-4000}"

curl -sS "http://127.0.0.1:${LITELLM_PORT}/v1/models" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  | python3 -m json.tool 2>/dev/null || true
