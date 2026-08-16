#!/usr/bin/env bash
# Shared helpers sourced by every script in this directory.
# Not meant to be executed directly.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- output -----------------------------------------------------------

log_ok()   { printf '[OK]   %s\n' "$*"; }
log_fail() { printf '[FAIL] %s\n' "$*" >&2; }
log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }

die() {
  log_fail "$*"
  exit 1
}

# ---- secrets ------------------------------------------------------------

# Never print a secret in full. Prints first 6 chars + "***".
mask_secret() {
  local value="$1"
  if [ -z "$value" ]; then
    printf '(empty)'
    return
  fi
  printf '%s***' "${value:0:6}"
}

# ---- env loading --------------------------------------------------------

# Loads $REPO_ROOT/.env into the environment. Fails loudly if missing —
# never silently creates or guesses one.
load_env() {
  local env_file="${REPO_ROOT}/.env"
  if [ ! -f "$env_file" ]; then
    die "$env_file not found. Run: cp .env.example .env   (then edit it)"
  fi
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

# set_env_var <key> <value>
# Updates KEY=value in .env if the key already exists, otherwise
# appends it. Safer than a bare `sed -i` replace, which silently does
# nothing if a .env predates a key added later to .env.example.
set_env_var() {
  local key="$1" value="$2"
  local env_file="${REPO_ROOT}/.env"
  [ -f "$env_file" ] || die "$env_file not found."
  if grep -q "^${key}=" "$env_file"; then
    sed -i.bak -e "s#^${key}=.*#${key}=${value}#" "$env_file"
    rm -f "${env_file}.bak"
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

# ---- checks ---------------------------------------------------------------

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
}

# require_env VAR_NAME [placeholder_to_reject ...]
# Fails if the variable is unset/empty, or equals one of the known
# placeholder values still left over from .env.example.
require_env() {
  local var_name="$1"
  shift
  local value="${!var_name:-}"
  if [ -z "$value" ]; then
    die "required env var not set: ${var_name} (check your .env)"
  fi
  local placeholder
  for placeholder in "$@" "change-me" "sk-change-me" "sk-change-me-with-another-random-secret" "<your-model-name>"; do
    if [ "$value" = "$placeholder" ]; then
      die "env var ${var_name} still has its placeholder value — set a real value in .env"
    fi
  done
}

# ---- confirmation for destructive actions --------------------------------

# confirm_destructive "message" "expected-typed-value"
confirm_destructive() {
  local message="$1"
  local expected="$2"
  log_warn "$message"
  printf 'Type "%s" to confirm: ' "$expected"
  local typed
  read -r typed
  if [ "$typed" != "$expected" ]; then
    die "confirmation did not match — aborted, nothing changed."
  fi
}
