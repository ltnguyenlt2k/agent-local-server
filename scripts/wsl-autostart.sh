#!/usr/bin/env bash
# Idempotent entrypoint meant to be triggered by a Windows Task Scheduler
# action ("At log on" / "At startup") via:
#
#   wsl.exe -d <YourDistro> -- bash -lc "/path/to/repo/scripts/wsl-autostart.sh"
#
# Does NOT touch Windows registry/policy/Task Scheduler itself — only
# provides this script; you configure Task Scheduler manually following
# docs/troubleshooting.md / README "Auto-start on boot".
#
# Warns (does not fail) if Ollama isn't reachable yet, since machine B
# may still be finishing boot when this runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

cd "$REPO_ROOT"
mkdir -p logs
LOG_FILE="logs/wsl-autostart.log"

log() { printf '%s %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG_FILE"; }

if [ ! -f ".env" ]; then
  log "[FAIL] .env not found — cannot start stack"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

OLLAMA_TEST_URL="${OLLAMA_HOST_TEST_URL:-${OLLAMA_BASE_URL:-}}"
if [ -n "$OLLAMA_TEST_URL" ] && curl -fsS --max-time 5 "${OLLAMA_TEST_URL%/}/api/tags" >/dev/null 2>&1; then
  log "[OK] Ollama reachable"
else
  log "[WARN] Ollama not reachable yet — continuing anyway, docker compose will retry the LiteLLM->Ollama connection at request time, not at startup"
fi

log "Running: docker compose up -d"
if docker compose up -d >>"$LOG_FILE" 2>&1; then
  log "[OK] docker compose up -d succeeded"
else
  log "[FAIL] docker compose up -d failed — see ${LOG_FILE}"
  exit 1
fi
