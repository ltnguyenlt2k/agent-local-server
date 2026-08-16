#!/usr/bin/env bash
# One-time interactive helper to create a Cloudflare Tunnel via the
# cloudflared CLI, route a hostname to it, and wire everything into
# .env + cloudflared/config.yml — no Cloudflare dashboard clicking
# required (see the "why locally-managed" note below for the one
# exception: dashboard-based Zero Trust activation, which this avoids).
#
# This is fully additive: it creates a NEW, separate tunnel + separate
# credentials file. It never touches any tunnel/config you already have
# running on this machine (e.g. an existing tunnel for your main site).
#
# Every subcommand used below (login/create/route dns/token) was run
# for real against cloudflared 2026.8.2 while building this script —
# not guessed from docs. Two corrections made after real-world testing,
# documented here so the next reader doesn't repeat the same mistakes:
#
# 1. `route dns` (and the whole cfargotunnel.com CNAME trick) ONLY
#    works if your hostname's domain is a zone in the SAME Cloudflare
#    account as the tunnel — confirmed via Cloudflare's own docs
#    ("the cfargotunnel.com subdomain only proxies traffic for DNS
#    records in the same Cloudflare account") and by testing: pointing
#    a CNAME at <tunnel-id>.cfargotunnel.com from a domain whose
#    nameservers are NOT Cloudflare's resolves to a non-routable
#    placeholder address (observed: fd10::/8), not a real Cloudflare
#    IP. If your domain isn't already on Cloudflare, you must add it
#    there first (Cloudflare dashboard -> Add a domain -> Connect a
#    domain -> update nameservers at your registrar) before this
#    script's automatic route will work. There is no free-tier way to
#    use only a subdomain without moving the domain's nameservers.
#
# 2. This script configures the tunnel's hostname->service mapping via
#    a LOCAL config file + credentials file (mounted into the
#    cloudflared container), not `--token` mode. Why: `--token` mode's
#    hostname mapping ("Public Hostname") can only be configured via
#    the Cloudflare Zero Trust dashboard, which requires "activating"
#    Zero Trust — a checkout flow that asks for a payment method on
#    file even though the tier itself is $0/month. The config-file
#    approach sets the same mapping in cloudflared/config.yml instead,
#    using credentials cloudflared already saves locally when a tunnel
#    is created. No dashboard visit, no payment method, ever. Verified
#    working end-to-end (HTTP 200 with real response body) against a
#    live tunnel before this became the default.
#
# Usage:
#   ./scripts/cloudflare-setup.sh <tunnel-name> <hostname>
#   ./scripts/cloudflare-setup.sh local-ai-gateway ai.example.com
#
# Requires: a domain whose zone is already in your Cloudflare account
# (see point 1 above), and a Cloudflare account you can log into
# interactively (step 2 opens a URL you must visit, unless you're
# already logged in from a previous run).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

[ $# -eq 2 ] || { echo "Usage: $0 <tunnel-name> <hostname>" >&2; echo "Example: $0 local-ai-gateway ai.example.com" >&2; exit 1; }
TUNNEL_NAME="$1"
HOSTNAME_TO_ROUTE="$2"

cd "$REPO_ROOT"
[ -f ".env" ] || die ".env not found. Run: cp .env.example .env   (then re-run this script)"

# --- Step 1: make sure cloudflared CLI is available -----------------------

CLOUDFLARED_BIN="cloudflared"
if ! command -v cloudflared >/dev/null 2>&1; then
  log_warn "cloudflared CLI not found on PATH."
  printf 'Download it to %s/.local/bin now? [y/N] ' "$HOME"
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    mkdir -p "$HOME/.local/bin"
    log_info "Downloading cloudflared-linux-amd64..."
    curl -fL --progress-bar \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
      -o "$HOME/.local/bin/cloudflared"
    chmod +x "$HOME/.local/bin/cloudflared"
    CLOUDFLARED_BIN="$HOME/.local/bin/cloudflared"
    log_ok "Installed to $HOME/.local/bin/cloudflared — add that to your PATH if not already."
  else
    die "cloudflared is required. Install it manually, then re-run this script."
  fi
fi
log_ok "Using: $("$CLOUDFLARED_BIN" --version)"

# --- Step 2: login (skipped if a cert already exists) ----------------------

CERT_PATH="$HOME/.cloudflared/cert.pem"
if [ -f "$CERT_PATH" ]; then
  log_ok "Found existing Cloudflare origin cert at ${CERT_PATH} — skipping login."
  log_warn "This cert only authorizes the zone(s) selected during ITS login."
  log_warn "If routing fails below with 'Authentication error' and the domain"
  log_warn "for ${HOSTNAME_TO_ROUTE} was added to Cloudflare/authorized AFTER"
  log_warn "this cert was created, delete ${CERT_PATH} and re-run this script"
  log_warn "to log in again and select the new domain."
else
  log_info "No origin cert found. Opening the Cloudflare login flow — a URL will be printed below."
  log_info "Visit it in any browser, and select the domain for ${HOSTNAME_TO_ROUTE} when prompted."
  "$CLOUDFLARED_BIN" tunnel login
  [ -f "$CERT_PATH" ] || die "Login did not produce ${CERT_PATH} — aborting."
  log_ok "Logged in."
fi

# --- Step 3: create the tunnel (idempotent-ish) -----------------------------

if "$CLOUDFLARED_BIN" tunnel list 2>/dev/null | awk '{print $2}' | grep -qx "$TUNNEL_NAME"; then
  log_ok "Tunnel '${TUNNEL_NAME}' already exists — reusing it."
else
  log_info "Creating tunnel '${TUNNEL_NAME}'..."
  "$CLOUDFLARED_BIN" tunnel create "$TUNNEL_NAME"
  log_ok "Tunnel created."
fi

TUNNEL_ID="$("$CLOUDFLARED_BIN" tunnel list -o json | python3 -c "
import json, sys
for t in json.load(sys.stdin):
    if t['name'] == '${TUNNEL_NAME}':
        print(t['id'])
        break
")"
[ -n "$TUNNEL_ID" ] || die "Could not find the tunnel ID for '${TUNNEL_NAME}' — check 'cloudflared tunnel list'."
log_ok "Tunnel ID: ${TUNNEL_ID}"

CREDENTIALS_SRC="$HOME/.cloudflared/${TUNNEL_ID}.json"
[ -f "$CREDENTIALS_SRC" ] || die "Expected credentials file not found: ${CREDENTIALS_SRC}"

# --- Step 4: route the hostname to it ---------------------------------------

# See point 1 in the file header: this only succeeds if the domain's
# zone is already in this Cloudflare account. If it fails with
# "Authentication error", the domain needs to be added to Cloudflare
# first (Add a domain -> Connect a domain -> update nameservers at
# your registrar) — there is no free-tier CNAME-only workaround.
log_info "Routing ${HOSTNAME_TO_ROUTE} -> ${TUNNEL_NAME} ..."
if ! "$CLOUDFLARED_BIN" tunnel route dns "$TUNNEL_NAME" "$HOSTNAME_TO_ROUTE" 2>/tmp/cf-route-dns-err.$$; then
  cat /tmp/cf-route-dns-err.$$ >&2
  rm -f /tmp/cf-route-dns-err.$$
  cat <<EOF

[FAILED] Could not create the DNS route. The most common cause: the
domain for ${HOSTNAME_TO_ROUTE} is not yet a zone in this Cloudflare
account (or this cert.pem wasn't authorized for it — see the Step 2
warning above). Add the domain to Cloudflare first:

  1. https://dash.cloudflare.com -> Add a domain -> Connect a domain
  2. Enter the domain, pick the Free plan
  3. Update your domain's nameservers at your registrar to the two
     Cloudflare-assigned ones shown
  4. Wait for Cloudflare to show the zone as Active
  5. Re-run this script

There is no way to route a Cloudflare Tunnel hostname from a domain
whose DNS is hosted elsewhere on the Free plan — the domain's zone
must be on Cloudflare.
EOF
  exit 1
fi
rm -f /tmp/cf-route-dns-err.$$
log_ok "DNS route created."

# --- Step 5: render cloudflared/config.yml + copy credentials --------------

cp "$CREDENTIALS_SRC" "${REPO_ROOT}/cloudflared/tunnel-credentials.json"
chmod 600 "${REPO_ROOT}/cloudflared/tunnel-credentials.json"

set_env_var CLOUDFLARE_TUNNEL_ID "$TUNNEL_ID"
set_env_var PUBLIC_AI_BASE_URL "https://${HOSTNAME_TO_ROUTE}"

# shellcheck disable=SC2016
CLOUDFLARE_TUNNEL_ID="$TUNNEL_ID" PUBLIC_HOSTNAME="$HOSTNAME_TO_ROUTE" \
  envsubst '${CLOUDFLARE_TUNNEL_ID} ${PUBLIC_HOSTNAME}' \
  < "${REPO_ROOT}/cloudflared/config.yml.template" \
  > "${REPO_ROOT}/cloudflared/config.yml"

log_ok "Wrote cloudflared/config.yml + cloudflared/tunnel-credentials.json (gitignored)."
log_ok "Set CLOUDFLARE_TUNNEL_ID and PUBLIC_AI_BASE_URL=https://${HOSTNAME_TO_ROUTE} in .env"

cat <<EOF

[OK] Cloudflare Tunnel '${TUNNEL_NAME}' is set up and routed to
     https://${HOSTNAME_TO_ROUTE}

Next steps:
  docker compose up -d cloudflared
  docker compose logs -f cloudflared      # confirm it connects, no
                                            # "no ingress rules" warning
  ./scripts/smoke-test-public.sh          # once you have a Virtual Key
EOF
