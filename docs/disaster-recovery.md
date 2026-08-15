# Disaster recovery runbook

Full rebuild of machine B from nothing (disk failure, Windows
reinstall, new machine). Update the "last performed" line at the
bottom after each real drill.

1. **Re-install Ollama** — `docs/ollama-windows.md` or
   `docs/ollama-wsl.md`, whichever you use.
2. **Re-pull models**: `ollama pull <model>` for everything you need.
3. **Re-clone this repository.**
4. **Restore `.env` and `cloudflared/`** from wherever you keep them
   *outside Git* (password manager / vault — both are gitignored on
   purpose and were never committed: `.env` has the LiteLLM/Postgres
   secrets, `cloudflared/tunnel-credentials.json` has the tunnel
   credentials). If you don't have a saved copy of either:
   - Generate fresh secrets per `docs/security.md` /
     `scripts/bootstrap.sh`'s auto-generate prompt.
   - Create a **new** Cloudflare Tunnel via `./scripts/cloudflare-setup.sh`
     (`docs/cloudflare.md`) — do not try to reuse old credentials, treat
     them as permanently lost. If the domain's zone is still on
     Cloudflare from before, this is fast; if not, you'll need to
     redo the nameserver delegation too.
5. **Restore the database**, if you have a backup:
   ```bash
   docker compose up -d postgres
   ./scripts/restore-db.sh backups/litellm-<timestamp>.dump
   ```
   If there is no backup, the database starts empty — every old
   Virtual Key is gone. You'll need to `./scripts/create-api-key.sh`
   again for each client and update `.env`/config on every Machine A.
6. **Bring up the rest of the stack**:
   ```bash
   ./scripts/render-config.sh
   docker compose up -d
   ```
7. If the tunnel was recreated in step 4, `cloudflare-setup.sh` already
   rendered `cloudflared/config.yml` with the hostname->service mapping —
   nothing further to configure in any dashboard.
8. **Run the full smoke test suite**:
   ```bash
   ./scripts/smoke-test-local.sh
   ./scripts/smoke-test-public.sh
   ```
9. **Update the "last performed" line below** so the next person knows
   how current this runbook is.

## Backups belong off machine B

`./scripts/backup-db.sh` writes to `backups/` on the same disk as
everything else. If that disk fails, the backup goes with it. Run
backups on a schedule (cron calling `backup-db.sh`) and copy the
resulting `.dump` files to storage that isn't machine B's primary
drive — an external drive, NAS, or off-machine object storage.

## Last performed

Not yet run for real — this section should be updated with a date and
outcome the first time this runbook is actually executed against a
real rebuild.
