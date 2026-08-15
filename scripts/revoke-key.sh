#!/usr/bin/env bash
# Revokes a LiteLLM Virtual Key. Destructive — requires typed confirmation.
#
# Usage: ./scripts/revoke-key.sh <token>
#   Get <token> from the last column of ./scripts/list-keys.sh output.
#
# Verified directly against the pinned LITELLM_IMAGE (v1.90.2):
# POST /key/delete with {"keys": ["<token>"]} works and returns
# {"deleted_keys": [...]}. The plaintext key also works if you still
# have it, but the token (hash) from list-keys.sh is what you'll
# normally have on hand later.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

[ $# -eq 1 ] || { echo "Usage: $0 <virtual-key-or-key-id>" >&2; exit 1; }
TARGET="$1"

load_env
require_env LITELLM_MASTER_KEY
require_cmd curl

confirm_destructive \
  "This permanently revokes access for the key/id: $(mask_secret "$TARGET"). Any client still using it will start getting 401s immediately." \
  "revoke"

LITELLM_PORT="${LITELLM_PORT:-4000}"

response="$(curl -sS -X POST "http://127.0.0.1:${LITELLM_PORT}/key/delete" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"keys\": [\"${TARGET}\"]}")"

printf '%s\n' "$response"
log_ok "Revoke request sent. Verify with ./scripts/list-keys.sh"
