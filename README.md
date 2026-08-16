# local-ai-gateway

Turns "machine B" (a local PC/workstation running Ollama) into an
OpenAI-compatible AI API gateway reachable from the Internet:
**LiteLLM (gateway/auth/virtual keys) + PostgreSQL (key/usage store) +
Cloudflare Tunnel (exposure)**, routing to **Ollama running natively,
outside Docker**.

## Scope

**In scope** — everything needed to run this stack on machine B and
hand out a Base URL + Virtual API Key + model alias.

**Out of scope, on purpose** — any "Machine A" application code: agent
orchestration, MCP client/server, tool execution, business logic. If
you're tempted to add App-A source code, a tool implementation, or an
MCP server to this repo, don't — see `docs/app-a-integration.md`
(reference-only) and the root spec's §2/§5 for the full boundary. This
repo's only external product is:

```text
AI_BASE_URL=https://ai.example.com/v1
AI_API_KEY=<LiteLLM Virtual Key>
AI_MODEL=local-agent
```

## Architecture

```text
App A (external, out of scope)
  │ HTTPS, Bearer <Virtual Key>
  ▼
Cloudflare edge
  │ Tunnel (outbound-only from machine B)
  ▼
cloudflared ── litellm:4000 ── PostgreSQL
                  │
                  ▼
        Ollama (native, machine B, :11434)
                  │
                  ▼
             Local model / GPU
```

Full diagrams and trust boundary: `docs/architecture.md`.

## Prerequisites

- Machine B: Windows + WSL2 + Docker (Desktop w/ WSL integration, or
  Docker Engine natively in WSL), NVIDIA/AMD GPU.
- A domain with DNS managed by Cloudflare, and a Cloudflare account.
- Ollama installed natively (not in Docker) — see
  `docs/ollama-windows.md` (recommended default) or `docs/ollama-wsl.md`.

## Quick Start

### 1. Install Ollama and pull a model

```powershell
# On Windows (default assumption — see docs/ollama-windows.md)
ollama pull <MODEL_NAME>
curl.exe http://localhost:11434/api/tags
```

### 2. Clone this repo and configure `.env`

```bash
git clone <this-repo>
cd local-ai-gateway
cp .env.example .env
nano .env   # fill in OLLAMA_MODEL, generate secrets (see below)
```

Generate secrets:

```bash
openssl rand -hex 32   # use for LITELLM_MASTER_KEY (prefix with sk-), LITELLM_SALT_KEY (prefix with sk-), POSTGRES_PASSWORD
```

Or let `./scripts/bootstrap.sh` (step 4) offer to generate them for you.

### 3. Set up the Cloudflare Tunnel

Your domain's zone must be on Cloudflare first (see `docs/cloudflare.md`
if it isn't — this is the step most likely to trip you up). Then:

```bash
./scripts/cloudflare-setup.sh <tunnel-name> ai.example.com
```

Creates the tunnel, routes the hostname, and writes
`CLOUDFLARE_TUNNEL_ID`/`PUBLIC_AI_BASE_URL` into `.env` plus
`cloudflared/config.yml` — no Cloudflare Zero Trust dashboard visit
needed (see `docs/cloudflare.md` for why that dashboard is avoided on
purpose).

### 4. Bring the stack up

```bash
./scripts/bootstrap.sh
```

This validates `.env` (`preflight.sh`), renders `litellm/config.yaml`
from the template, pulls pinned images, starts the stack, and waits
for everything to report healthy. Equivalent manual steps:

```bash
./scripts/preflight.sh
docker compose pull
docker compose up -d
docker compose ps
```

Logs:

```bash
docker compose logs -f postgres
docker compose logs -f litellm
docker compose logs -f cloudflared
```

### 5. Create a Virtual API Key

```bash
./scripts/create-api-key.sh machine-a-app
```

Save the printed key immediately — it's shown once and never stored by
this repo.

### 6. Test locally (bypasses Cloudflare)

```bash
AI_KEY=<virtual-key> ./scripts/smoke-test-local.sh
```

### 7. Test publicly

```bash
AI_KEY=<virtual-key> ./scripts/smoke-test-public.sh
```

Run this again from a different network (e.g. mobile data) to confirm
it's really reachable from the Internet, not just from machine B.

### 8. Configure Machine A

Hand the operator of App A:

```env
AI_BASE_URL=https://ai.example.com/v1
AI_API_KEY=<virtual-key>
AI_MODEL=local-agent
```

See `docs/app-a-integration.md` for client examples — reference only,
not implemented here.

### 9. Optional: tool-calling capability check

If App A needs tool/function calling, see root spec §27 for the
pattern (not included as a ready-made script in this pass — pick a
target model/tool schema first, then add the fixture).

## Everyday operations

```bash
./scripts/status.sh                       # health summary
./scripts/list-keys.sh                    # list virtual keys
./scripts/revoke-key.sh <key-or-id>        # revoke (interactive confirm)
./scripts/rotate-key.sh <purpose>          # issue new + guided old-key revoke
./scripts/backup-db.sh                     # pg_dump -> backups/
./scripts/restore-db.sh <file>             # pg_restore (interactive confirm)
```

Or via `make` (see `Makefile`): `make up|down|logs|status|key
NAME=...|list-keys|revoke-key KEY=...|rotate-key NAME=...|backup|restore
FILE=...|smoke-local|smoke-public`.

## Auto-start on boot

- Docker daemon: enable "start on login" (Docker Desktop) or `sudo
  systemctl enable docker` (native Docker Engine in WSL with
  `systemd=true`).
- WSL itself doesn't start automatically on Windows boot by default —
  use Windows Task Scheduler ("At log on"/"At startup") to run:
  ```powershell
  wsl.exe -d <YourDistro> -- bash -lc "/path/to/local-ai-gateway/scripts/wsl-autostart.sh"
  ```
- Ollama: Windows installer usually runs it in the background and can
  be added to Startup Apps; for WSL-native Ollama, `sudo systemctl
  enable ollama` (needs `systemd=true` in `/etc/wsl.conf`).
- Disable Windows sleep/hibernate on machine B if you want 24/7
  availability (display can still turn off).

## Deploying to another machine

`deploy/` is a self-contained copy of everything needed to run this
stack on a *different* machine — docker-compose.yml, env template,
config templates, and every script, plus its own focused docs
(`deploy/docs/CONFIGURATION.md`, `deploy/docs/INSTALL-MODEL.md`). Copy
that folder to the target machine and follow `deploy/README.md`.

It's a generated copy, not a second source of truth — after changing
`docker-compose.yml`, any `*.template` file, or anything in `scripts/`,
run `./scripts/sync-deploy.sh` (or `make sync-deploy`) so `deploy/`
doesn't silently drift from what's actually been tested here.

## Troubleshooting / Security / Backup / Upgrade

- `docs/troubleshooting.md` — layered debug flow, one section per
  failure scenario.
- `docs/security.md` — required hardening checklist.
- `docs/network-security.md` — network segmentation & container
  hardening rationale (what's applied vs. recommended-but-untested).
- `docs/disaster-recovery.md` — full machine-B rebuild runbook.
- `docs/upgrade.md` — how to move a pinned image version forward safely.

## Acceptance checklist

Before considering this deployment done, verify (see the root spec
`local-ai-gateway-implementation-plan-v3-reviewed.md` §54 for the full
list):

- [x] `docker compose up -d` works in WSL; `postgres`/`litellm`/
      `cloudflared` all report healthy. Verified with real containers
      (pinned images, real Postgres + Prisma migration, real
      `/health/readiness` 200, real tunnel connections to Cloudflare
      edge).
- [x] Ollama reachable from a Docker container (`./scripts/preflight.sh`).
      Verified for real, including the `OLLAMA_HOST=0.0.0.0` bind-address
      fix — see `docs/ollama-wsl.md`.
- [x] `local-agent` (or your alias) routes to the right Ollama model.
      Verified for real: chat-completion requests went client → LiteLLM
      → Postgres (key check) → Ollama → GPU → response, HTTP 200.
- [x] Unauthorized/invalid-key requests are rejected (401); valid key
      succeeds. Verified for real via `smoke-test-local.sh` against a
      live stack.
- [x] Public endpoint reachable over the real Internet
      (`smoke-test-public.sh`), HTTPS works, port 11434/5432 not
      public. Verified for real: unauthorized/invalid-key 401, valid
      key returned the expected response over `https://` through
      Cloudflare Tunnel. Still worth re-running from a genuinely
      different network (e.g. mobile data) yourself for full
      confidence — see `docs/cloudflare.md`.
- [ ] Backup/restore drill completed at least once
      (`docs/disaster-recovery.md`).
- [ ] Reboot recovery verified (`docs/troubleshooting.md`/README
      "Auto-start on boot").

The checked items were verified against real containers, real
Ollama+GPU, and a real Cloudflare Tunnel over the public Internet while
building this repo — not just syntax-checked. The remaining two need a
real backup/restore drill and a real reboot, which weren't exercised
in this pass.
