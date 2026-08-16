#!/usr/bin/env bash
# Rotates a Virtual Key for a given purpose: creates a NEW key, then
# separately (not in the same run) offers to revoke the old one — so a
# client that hasn't picked up the new key yet isn't cut off immediately.
#
# Usage: ./scripts/rotate-key.sh <purpose> [--models m1,m2]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

[ $# -ge 1 ] || { echo "Usage: $0 <purpose> [--models m1,m2]" >&2; exit 1; }

log_info "Step 1/2: creating a new key for the same purpose."
"${SCRIPT_DIR}/create-api-key.sh" "$@"

cat <<'EOF'

Step 2/2: revoke the OLD key.

Do this only after the client has been updated to use the new key
above and you've confirmed it works (./scripts/smoke-test-public.sh
or a real request from the client). This script does NOT revoke the
old key automatically.

When ready:
  ./scripts/list-keys.sh              # find the old key's id/alias
  ./scripts/revoke-key.sh <old-key-id-or-name>
EOF
