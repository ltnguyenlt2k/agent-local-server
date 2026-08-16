#!/usr/bin/env bash
# Fail-fast checks before `docker compose up`. Never prints secret values.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

log_info "Running preflight checks..."

require_cmd docker
docker compose version >/dev/null 2>&1 || die "docker compose plugin not available"
log_ok "docker + docker compose"

load_env
log_ok ".env loaded"

require_env LITELLM_MASTER_KEY
[[ "${LITELLM_MASTER_KEY}" == sk-* ]] || die "LITELLM_MASTER_KEY must start with 'sk-'"
log_ok "LITELLM_MASTER_KEY set ($(mask_secret "${LITELLM_MASTER_KEY}"))"

require_env LITELLM_SALT_KEY
[ "${LITELLM_SALT_KEY}" != "${LITELLM_MASTER_KEY}" ] || die "LITELLM_SALT_KEY must differ from LITELLM_MASTER_KEY"
log_ok "LITELLM_SALT_KEY set ($(mask_secret "${LITELLM_SALT_KEY}"))"

require_env POSTGRES_PASSWORD
log_ok "POSTGRES_PASSWORD set ($(mask_secret "${POSTGRES_PASSWORD}"))"

require_env DATABASE_URL
log_ok "DATABASE_URL set"

require_env OLLAMA_BASE_URL
require_env OLLAMA_MODEL
require_env LITELLM_MODEL_ALIAS
log_ok "Ollama/model routing vars set (alias=${LITELLM_MODEL_ALIAS}, model=${OLLAMA_MODEL})"

if [ -n "${CLOUDFLARE_TUNNEL_ID:-}" ]; then
  [ -f "${REPO_ROOT}/cloudflared/config.yml" ] || die "CLOUDFLARE_TUNNEL_ID is set but cloudflared/config.yml is missing — re-run ./scripts/cloudflare-setup.sh"
  [ -f "${REPO_ROOT}/cloudflared/tunnel-credentials.json" ] || die "CLOUDFLARE_TUNNEL_ID is set but cloudflared/tunnel-credentials.json is missing — re-run ./scripts/cloudflare-setup.sh"
  log_ok "Locally-managed tunnel configured (CLOUDFLARE_TUNNEL_ID=${CLOUDFLARE_TUNNEL_ID})"
elif [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  log_ok "Legacy --token tunnel mode: CLOUDFLARE_TUNNEL_TOKEN set ($(mask_secret "${CLOUDFLARE_TUNNEL_TOKEN}"))"
else
  die "Neither CLOUDFLARE_TUNNEL_ID nor CLOUDFLARE_TUNNEL_TOKEN is set — run ./scripts/cloudflare-setup.sh <tunnel-name> <hostname> first"
fi

if [[ "${PUBLIC_AI_BASE_URL:-}" == "https://ai.example.com" ]] || [ -z "${PUBLIC_AI_BASE_URL:-}" ]; then
  log_warn "PUBLIC_AI_BASE_URL still looks like the placeholder — fine until Phase 4 (Cloudflare), fix before smoke-test-public.sh"
else
  log_ok "PUBLIC_AI_BASE_URL set to ${PUBLIC_AI_BASE_URL}"
fi

# Render config.yaml before validating anything downstream depends on it.
"${SCRIPT_DIR}/render-config.sh"

# Port availability on host.
LITELLM_PORT="${LITELLM_PORT:-4000}"
if command -v ss >/dev/null 2>&1; then
  if ss -ltn "( sport = :${LITELLM_PORT} )" 2>/dev/null | grep -q ":${LITELLM_PORT}"; then
    log_warn "port ${LITELLM_PORT} already appears to be in use on the host (may just be a previous run of this stack)"
  else
    log_ok "port ${LITELLM_PORT} available"
  fi
else
  log_warn "'ss' not found — skipping port availability check"
fi

# Docker -> native Ollama connectivity test (§38): run FROM a throwaway
# container on the docker network, not a bare curl from the WSL shell —
# host.docker.internal resolution can differ between the two (§16/§37).
OLLAMA_TEST_URL="${OLLAMA_HOST_TEST_URL:-${OLLAMA_BASE_URL}}"
log_info "Testing Docker -> Ollama connectivity at ${OLLAMA_TEST_URL} ..."
if docker run --rm \
    --add-host=host.docker.internal:host-gateway \
    curlimages/curl:latest \
    -fsS --max-time 5 "${OLLAMA_TEST_URL%/}/api/tags" >/dev/null 2>&1; then
  log_ok "Ollama reachable from a Docker container at ${OLLAMA_TEST_URL}"
else
  log_fail "Ollama NOT reachable from Docker at ${OLLAMA_TEST_URL}"
  cat >&2 <<'EOF'
Possible causes, check in this order (see docs/troubleshooting.md):
  1. Is the Ollama service actually running on machine B?
  2. What address is Ollama bound to? (loopback-only won't be reachable
     from Docker unless OLLAMA_HOST is set — see docs/ollama-windows.md)
  3. Is Windows Firewall blocking the Docker/WSL network from :11434?
  4. Does host.docker.internal actually resolve inside containers in
     your Docker mode (Docker Desktop vs. native Docker Engine in WSL)?
  5. WSL networking mode (mirrored vs NAT) can also affect this — see
     docs/troubleshooting.md.
Do NOT proceed to edit litellm/config.yaml or docker-compose.yml until
this specific check passes; fix the network layer first.
EOF
  exit 1
fi

log_ok "All preflight checks passed."
