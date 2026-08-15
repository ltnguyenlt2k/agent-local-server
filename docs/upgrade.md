# Upgrade procedure

Never `docker compose pull` a floating tag. This repo pins every image
via `.env` (`LITELLM_IMAGE`, `POSTGRES_IMAGE`, `CLOUDFLARED_IMAGE`) —
upgrading means deliberately changing a pin, not chasing `latest`.

## Procedure

1. Read the release notes for the component you're upgrading:
   - LiteLLM: https://github.com/BerriAI/litellm/releases
   - Postgres: https://www.postgresql.org/docs/release/
   - cloudflared: https://hub.docker.com/r/cloudflare/cloudflared/tags
2. **Backup first**: `./scripts/backup-db.sh`.
3. Record the current pinned image tag somewhere (git history of
   `.env` if you track a non-secret template of it, or just note it
   manually) so you have an exact rollback target.
4. Check for DB migration requirements in the release notes — LiteLLM
   in particular may run Prisma migrations on startup with the
   `litellm-database` image; know what to expect before upgrading.
5. Update the relevant `*_IMAGE` value in `.env`.
6. `docker compose pull`
7. `docker compose up -d` (recreates the changed service).
8. Run the acceptance checks:
   ```bash
   ./scripts/wait-for-stack.sh
   ./scripts/smoke-test-local.sh
   ./scripts/smoke-test-public.sh
   ```
   Also re-run any tool-calling/provider-capability check you rely on
   (root spec §27) if App A depends on tool calling.
9. If anything fails, roll back by reverting the `*_IMAGE` value in
   `.env` and re-running `docker compose pull && docker compose up -d`.

## `LITELLM_SALT_KEY` never changes

This is worth repeating because it's the one thing an upgrade must
never touch: `LITELLM_SALT_KEY` encrypts credentials already stored in
Postgres. Changing it after keys exist breaks decryption of everything
already stored — it is not part of a normal upgrade or rotation
procedure, ever.
