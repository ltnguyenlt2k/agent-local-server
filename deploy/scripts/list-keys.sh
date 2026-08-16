#!/usr/bin/env bash
# Lists LiteLLM Virtual Keys (metadata only — never prints full plaintext
# keys; the API itself only returns those once, at creation time).
#
# Verified directly against the pinned LITELLM_IMAGE (ghcr.io/berriai/
# litellm-database:v1.90.2): the bare `/key/list` response only returns
# {"keys": ["<hashed-token>", ...], "total_count": ..., ...} — no
# metadata. `?return_full_object=true` is required to get per-key
# purpose/models/status objects; without it this script would silently
# have nothing useful to show.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_env
require_env LITELLM_MASTER_KEY
require_cmd curl

LITELLM_PORT="${LITELLM_PORT:-4000}"

response="$(curl -sS "http://127.0.0.1:${LITELLM_PORT}/key/list?return_full_object=true" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}")"

python3 - "$response" <<'PY' 2>/dev/null || printf '%s\n' "$response"
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print(sys.argv[1])
    sys.exit(0)

keys = data.get("keys", data if isinstance(data, list) else [])
if not keys:
    print("(no keys found)")
    sys.exit(0)

print(f"{'purpose':<24} {'models':<24} {'status':<10} {'key_name':<16} token (pass this to revoke-key.sh)")
print("-" * 110)
for k in keys:
    if not isinstance(k, dict):
        # Shouldn't happen with ?return_full_object=true, but don't crash
        # on a bare token string if a future release changes the default.
        print(f"{'-':<24} {'-':<24} {'-':<10} {'-':<16} {k}")
        continue
    meta = k.get("metadata", {}) or {}
    purpose = meta.get("purpose", "-")
    models = ",".join(k.get("models", []) or []) or "-"
    status = "revoked" if k.get("blocked") else "active"
    key_name = k.get("key_name", "-")
    token = k.get("token", "-")
    print(f"{purpose:<24} {models:<24} {status:<10} {key_name:<16} {token}")
PY
