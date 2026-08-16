#!/usr/bin/env bash
# Regenerates deploy/ from the canonical files at the repo root. deploy/
# is meant to be copied to a second machine and used standalone — see
# deploy/README.md. Run this after changing docker-compose.yml, any
# .template file, or any scripts/*.sh, so deploy/ never silently drifts
# from what's actually been tested at the repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

cd "$REPO_ROOT"

mkdir -p deploy/litellm deploy/cloudflared deploy/scripts deploy/backups deploy/logs

cp docker-compose.yml deploy/docker-compose.yml
cp .env.example deploy/.env.example
cp litellm/config.yaml.template deploy/litellm/config.yaml.template
cp cloudflared/config.yml.template deploy/cloudflared/config.yml.template
for f in scripts/*.sh; do
  # Don't copy this script itself — it's a repo-maintenance tool for
  # regenerating deploy/, not something a deployed copy needs to run.
  [ "$(basename "$f")" = "sync-deploy.sh" ] && continue
  cp "$f" deploy/scripts/
done
chmod +x deploy/scripts/*.sh
touch deploy/backups/.gitkeep deploy/logs/.gitkeep

log_ok "Synced deploy/ from repo-root canonical files."
log_info "deploy/README.md and deploy/docs/*.md are hand-written, not touched by this script."
