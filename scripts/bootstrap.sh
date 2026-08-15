#!/usr/bin/env bash
# First-run orchestrator: .env check -> optional secret generation ->
# render config -> preflight -> docker compose pull/up -> wait for healthy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

cd "$REPO_ROOT"

if [ ! -f ".env" ]; then
  die ".env not found. Run: cp .env.example .env   (edit it, then re-run this script)"
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

needs_secret=false
for var in LITELLM_MASTER_KEY LITELLM_SALT_KEY POSTGRES_PASSWORD; do
  value="${!var:-}"
  case "$value" in
    ""|change-me|sk-change-me|sk-change-me-with-another-random-secret)
      needs_secret=true
      ;;
  esac
done

if $needs_secret; then
  log_warn "One or more secrets in .env still look like placeholders."
  printf 'Generate random values for LITELLM_MASTER_KEY / LITELLM_SALT_KEY / POSTGRES_PASSWORD now? [y/N] '
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    require_cmd openssl
    new_master="sk-$(openssl rand -hex 32)"
    new_salt="sk-$(openssl rand -hex 32)"
    new_db_pass="$(openssl rand -hex 32)"
    set_env_var LITELLM_MASTER_KEY "$new_master"
    set_env_var LITELLM_SALT_KEY "$new_salt"
    set_env_var POSTGRES_PASSWORD "$new_db_pass"
    log_ok "Generated new secrets in .env. Update DATABASE_URL's password to match if you changed POSTGRES_PASSWORD."
    log_warn "DATABASE_URL is not auto-updated — edit it manually to match the new POSTGRES_PASSWORD before continuing."
    printf 'Press enter once DATABASE_URL is updated to continue...'
    read -r _
  else
    log_info "Skipping auto-generation — edit .env manually, then re-run this script."
  fi
fi

"${SCRIPT_DIR}/preflight.sh"

log_info "Pulling images..."
docker compose pull

log_info "Starting stack..."
docker compose up -d

"${SCRIPT_DIR}/wait-for-stack.sh"

cat <<EOF

[OK] Stack is up. Next steps:

  1. Create a Virtual API Key for a client:
       ./scripts/create-api-key.sh machine-a-app

  2. Smoke test locally:
       ./scripts/smoke-test-local.sh

  3. Once Cloudflare Tunnel is configured (docs/cloudflare.md):
       ./scripts/smoke-test-public.sh

EOF
