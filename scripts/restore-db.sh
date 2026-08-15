#!/usr/bin/env bash
# Restores a Postgres dump produced by backup-db.sh. DESTRUCTIVE — wipes
# and replaces the current database contents. Requires typed confirmation.
#
# Usage: ./scripts/restore-db.sh backups/litellm-20260101-120000.dump
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

[ $# -eq 1 ] || { echo "Usage: $0 <path-to-dump-file>" >&2; exit 1; }
DUMP_FILE="$1"
[ -f "$DUMP_FILE" ] || die "file not found: $DUMP_FILE"

load_env
require_env POSTGRES_USER
require_env POSTGRES_DB

confirm_destructive \
  "This will DROP and REPLACE all data in the '${POSTGRES_DB}' database (all Virtual Keys, usage history) with the contents of ${DUMP_FILE}. This cannot be undone." \
  "restore"

cd "$REPO_ROOT"

log_info "Restoring ${DUMP_FILE} into ${POSTGRES_DB} ..."
docker compose exec -T postgres \
  pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --clean --if-exists \
  < "${DUMP_FILE}"

log_ok "Restore complete. Run ./scripts/list-keys.sh to verify, and re-issue any keys clients don't have saved."
