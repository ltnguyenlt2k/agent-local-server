#!/usr/bin/env bash
# Dumps the LiteLLM Postgres database to backups/ (gitignored).
# Store the resulting file somewhere OFF machine B too (external drive,
# separate storage) — see docs/disaster-recovery.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_env
require_env POSTGRES_USER
require_env POSTGRES_DB

cd "$REPO_ROOT"
mkdir -p backups

OUT="backups/litellm-$(date +%Y%m%d-%H%M%S).dump"

log_info "Dumping database ${POSTGRES_DB} to ${OUT} ..."
docker compose exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc \
  > "${OUT}"

log_ok "Backup written: ${OUT} ($(du -h "${OUT}" | cut -f1))"
