#!/usr/bin/env bash
# Renders litellm/config.yaml from litellm/config.yaml.template by
# substituting exactly the three vars we don't rely on LiteLLM's own
# os.environ/ interpolation for. See litellm/config.yaml.template for why.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

load_env

require_env LITELLM_MODEL_ALIAS
require_env OLLAMA_MODEL
require_env OLLAMA_BASE_URL

TEMPLATE="${REPO_ROOT}/litellm/config.yaml.template"
OUTPUT="${REPO_ROOT}/litellm/config.yaml"

[ -f "$TEMPLATE" ] || die "template not found: $TEMPLATE"

# Restrict envsubst to just these vars so unrelated $ / ${...} in the
# template (there are none today, but future edits might add some)
# never get silently mangled. Single-quoted on purpose: this is the
# variable-name allowlist envsubst itself parses, not shell expansion.
# shellcheck disable=SC2016
envsubst '${LITELLM_MODEL_ALIAS} ${OLLAMA_MODEL} ${OLLAMA_BASE_URL}' \
  < "$TEMPLATE" > "$OUTPUT"

# Best-effort YAML sanity check — skip quietly if pyyaml isn't available,
# this should never block bootstrap over a missing lint dependency.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 -c "import yaml, sys; yaml.safe_load(open('${OUTPUT}'))" \
      || die "rendered ${OUTPUT} is not valid YAML"
  fi
fi

log_ok "rendered litellm/config.yaml (alias=${LITELLM_MODEL_ALIAS}, model=ollama_chat/${OLLAMA_MODEL})"
