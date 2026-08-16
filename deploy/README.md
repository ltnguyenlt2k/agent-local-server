# local-ai-gateway — deploy package

Self-contained copy of everything needed to run the LiteLLM + PostgreSQL
+ Cloudflare Tunnel gateway stack on a **new machine** ("máy 2"). Copy
this whole `deploy/` folder to the target machine and follow the steps
below. Ollama (the model itself) is **not** part of this package — see
`docs/INSTALL-MODEL.md` for that, done as a separate step before or
after this one.

> This is a generated copy of the canonical files at the repo root
> (kept in sync via `scripts/sync-deploy.sh` — see the root README if
> you're looking at the source repo, not a copied `deploy/` folder on
> a target machine).

## What "docker compose build && up" actually does here

There is **no custom application code in this repo** — nothing for
`docker compose build` to build. Every service (`postgres`, `litellm`,
`cloudflared`) uses a pinned, publicly-published image from its
vendor. So on a fresh machine:

```bash
docker compose build   # no-op — no service defines a `build:` key, this just succeeds instantly
docker compose pull    # actually fetches the 3 pinned vendor images
docker compose up -d
```

`build` is safe to run out of habit (it won't error, it just has
nothing to do) — the real work happens in `pull`/`up`. This repo's CI
(`compose-config` job) validates that these exact pinned image
versions + this exact `docker-compose.yml` are internally consistent
on every push, so what you pull here is the same configuration that
was last validated in CI — not a custom image CI built for you.

## Quick start on the new machine

1. **Prerequisites**: Docker + Docker Compose installed, reachable to
   the Internet (to pull images and connect the Cloudflare Tunnel).
   Ollama does **not** need to be installed on *this* machine if
   you're pointing `OLLAMA_BASE_URL` at a different machine's Ollama —
   see step 3.

2. **Configure**: see `docs/CONFIGURATION.md` for the full walkthrough
   (secrets, Ollama connection, Cloudflare). Short version:
   ```bash
   cp .env.example .env
   nano .env   # fill in secrets, OLLAMA_BASE_URL, OLLAMA_MODEL
   ```

3. **Cloudflare Tunnel**: run the setup script — it only asks you to
   log in interactively if there's no cached Cloudflare login on this
   machine yet (opens a URL, you authorize in a browser once):
   ```bash
   ./scripts/cloudflare-setup.sh <tunnel-name> ai.yourdomain.com
   ```
   See `docs/CONFIGURATION.md` if the domain isn't on Cloudflare yet —
   that's a one-time prerequisite, not something this script can do
   for you.

4. **Bring the stack up**:
   ```bash
   ./scripts/preflight.sh
   docker compose build
   docker compose pull
   docker compose up -d
   ./scripts/wait-for-stack.sh
   ```
   Or just `./scripts/bootstrap.sh`, which does all of the above plus
   optional secret generation if `.env` still has placeholder values.

5. **Create a Virtual API Key** for whatever app will call this
   gateway:
   ```bash
   ./scripts/create-api-key.sh my-app
   ```

6. **Verify end-to-end**:
   ```bash
   AI_KEY=<key-from-step-5> ./scripts/smoke-test-local.sh
   AI_KEY=<key-from-step-5> ./scripts/smoke-test-public.sh
   ```

## Installing/running the model — separate step

This package only runs the **gateway** (LiteLLM/Postgres/cloudflared).
The model itself (Ollama) is installed and run independently, either
on this same machine or a different one — whichever machine you point
`OLLAMA_BASE_URL` at in `.env`. See `docs/INSTALL-MODEL.md`.

## Day-to-day operations

```bash
./scripts/status.sh                      # health summary
./scripts/list-keys.sh                   # list virtual keys
./scripts/revoke-key.sh <token>           # revoke a key (interactive confirm)
./scripts/rotate-key.sh <purpose>         # issue new + guided old-key revoke
./scripts/backup-db.sh                    # pg_dump -> backups/
./scripts/restore-db.sh <file>            # pg_restore (interactive confirm)
```

## Files in this folder

```
docker-compose.yml               postgres + litellm + cloudflared
.env.example                     copy this to .env and fill in
litellm/config.yaml.template     rendered to config.yaml by render-config.sh
cloudflared/config.yml.template  rendered to config.yml by cloudflare-setup.sh
scripts/                         all operational scripts (same as repo root)
docs/CONFIGURATION.md            how to fill in .env / secrets / Cloudflare
docs/INSTALL-MODEL.md            installing & running Ollama (separate step)
backups/, logs/                  empty on a fresh copy, gitignored once populated
```

`.env`, the rendered `litellm/config.yaml` and `cloudflared/config.yml`,
and `cloudflared/tunnel-credentials.json` are all gitignored — they
hold real secrets and are generated/filled in on the target machine
itself, never copied between machines by hand (regenerate them there
instead — see `docs/CONFIGURATION.md`).
