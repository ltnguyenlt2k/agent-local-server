# Security

## Required

- **Never expose Ollama (`:11434`) to the Internet.** Only LiteLLM
  talks to it. No router port-forward, ever.
- **Never expose PostgreSQL (`:5432`)**, not even to the LAN, except
  briefly for debugging with a plan to close it again.
- **Never commit `.env`.** `.gitignore` covers `.env`, `.env.*`
  (except `.env.example`), backup dumps, logs, and the generated
  `litellm/config.yaml`.
- **Never give App A the Master Key.** App A only ever receives a
  Virtual Key from `./scripts/create-api-key.sh`.
- **One Virtual Key per client/purpose** (e.g. `machine-a-agent`,
  `vscode-agent`, `ci-client`) — a leaked key can be revoked alone via
  `./scripts/revoke-key.sh` without affecting other clients.
- **Don't rotate the Master Key just because one Virtual Key leaked** —
  revoke that specific key instead.
- **Pin all image tags** (`LITELLM_IMAGE`, `POSTGRES_IMAGE`,
  `CLOUDFLARED_IMAGE` in `.env`) — never `:latest` for these. See
  `docs/upgrade.md` for how to move to a new pin deliberately.
- **`LITELLM_SALT_KEY` is generated once and never rotated** after the
  database has stored encrypted credentials — rotating it breaks
  decryption of anything already stored.

## Network segmentation (default in this repo)

See `docs/network-security.md` for the full `ai_frontend`/`ai_backend`
split — `cloudflared` (the only Internet-facing service) has no Docker
network path to Postgres.

## Cloudflare Access

Do not put Cloudflare Access's interactive login in front of
`ai.example.com` for the MVP — see `docs/cloudflare.md` for why (a
generic OpenAI SDK can't complete a browser login flow). If you add
perimeter hardening later (service tokens, mTLS, WAF), App A must be
able to send whatever extra credentials that requires.

## Rate limiting

MVP relies on LiteLLM Virtual Keys + a single instance + usage
tracking; that's enough for a handful of clients. Don't add Redis
"because it looks more production" — add it only once you actually
have enough concurrent clients that distributed rate limiting/caching
matters.

## CORS

Only relevant if some App A runs directly in a browser and calls this
gateway's public URL from client-side JS. If so:

- Never put a Virtual Key in browser-shipped code — anyone can read it
  from the network tab. Put a small backend in front of App A's
  browser client to hold the key server-side (that backend is App A's
  responsibility, not this repo's).
- If you still need CORS for a specific trusted origin, uncomment and
  fill in `cors_allowed_origins` in `litellm/config.yaml.template`
  (never `"*"` on a gateway holding API keys), then
  `./scripts/render-config.sh && docker compose up -d litellm`.

## Secrets hygiene in scripts

`scripts/lib.sh`'s `mask_secret()` is used anywhere a secret needs to
be shown for debugging (first 6 chars + `***`). No script in this repo
uses `set -x` around code that touches `LITELLM_MASTER_KEY`,
`LITELLM_SALT_KEY`, `POSTGRES_PASSWORD`, `CLOUDFLARE_TUNNEL_TOKEN`
(legacy `--token` mode), or the tunnel credentials JSON file (default
locally-managed mode, see `docs/cloudflare.md`) — keep that invariant
if you modify or add scripts. The credentials file itself
(`cloudflared/tunnel-credentials.json`) is gitignored and never
printed by any script.
