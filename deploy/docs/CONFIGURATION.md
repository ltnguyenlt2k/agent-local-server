# Configuration guide — filling in `.env` and connecting Cloudflare

This covers everything you need to set before `docker compose up`
works: secrets, where to find Ollama, and the Cloudflare Tunnel. This
does **not** cover installing/running the model itself — see
`INSTALL-MODEL.md` for that, a deliberately separate step.

## 1. Copy and open `.env`

```bash
cp .env.example .env
```

Every variable has an explanatory comment directly above it in
`.env.example` — read those inline, this doc only covers the parts
that need a decision, not every field.

## 2. Generate secrets

```bash
openssl rand -hex 32
```

Run this **three times** for `LITELLM_MASTER_KEY` (prefix with `sk-`),
`LITELLM_SALT_KEY` (prefix with `sk-`), and `POSTGRES_PASSWORD`. Update
`DATABASE_URL`'s password to match whatever you set for
`POSTGRES_PASSWORD` — they must agree.

`LITELLM_MASTER_KEY` is the admin credential — never hand it to any
app calling this gateway; only the Virtual Keys created via
`./scripts/create-api-key.sh` should go to client apps. `LITELLM_SALT_KEY`
must never change once the database has stored encrypted credentials —
generate it once, keep it forever.

Alternatively, `./scripts/bootstrap.sh` offers to generate all three
for you interactively if it detects placeholder values.

## 3. Point at Ollama

```dotenv
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_MODEL=<name as shown by `ollama list` on wherever Ollama runs>
LITELLM_MODEL_ALIAS=local-agent
```

`OLLAMA_BASE_URL` must be reachable **from inside the `litellm`
container**, not just from this machine's shell — those can differ.
`./scripts/preflight.sh` checks this correctly (from inside a
throwaway container); don't just `curl` it from your own shell and
assume that proves anything.

If Ollama runs on a **different** machine than this gateway package,
point `OLLAMA_BASE_URL` at that machine's real IP/hostname instead of
`host.docker.internal` (which only resolves to "this same machine's
host"), and make sure Ollama there is bound to an address reachable
from this machine (not just `127.0.0.1`) — see `INSTALL-MODEL.md`'s
bind-address section, and open the firewall for exactly that one port
to exactly this gateway machine, nothing broader.

## 4. `LITELLM_PORT` — check it's actually free

```bash
ss -ltn | grep :4000
```

4000 is a common default and can collide with something else already
running on the target machine. Change `LITELLM_PORT` in `.env` if so —
nothing else in this package hardcodes 4000.

## 5. Cloudflare Tunnel

**Prerequisite**: the domain (or a domain dedicated to this) must have
its DNS zone on Cloudflare — not just any DNS provider. If it isn't
yet:

1. Cloudflare Dashboard → **Add a domain** → **Connect a domain**
2. Enter the domain, pick the **Free** plan
3. Update the domain's nameservers at your registrar to the two
   Cloudflare-assigned ones shown
4. Wait for Cloudflare to mark the zone **Active** (minutes to hours)

There is no free-tier way to use only a subdomain without moving the
whole domain's nameservers to Cloudflare — if you don't want to move
an existing site's domain, use a separate domain dedicated to this
gateway instead.

Once the zone is Active:

```bash
./scripts/cloudflare-setup.sh <tunnel-name> ai.yourdomain.com
```

This creates the tunnel, routes the hostname, and writes
`CLOUDFLARE_TUNNEL_ID` + `PUBLIC_AI_BASE_URL` into `.env` plus renders
`cloudflared/config.yml` — all without needing the Cloudflare Zero
Trust dashboard (which, as of writing, gates access behind an
"Activate Zero Trust" payment-method prompt even for the free tier —
this package avoids that entirely by using a locally-managed,
config-file-based tunnel instead of the simpler-but-dashboard-gated
`--token` mode).

**You only need to log in interactively if** `~/.cloudflared/cert.pem`
doesn't already exist on this machine from a prior login — the script
opens a URL, you authorize once in a browser, done. If it does exist
but was authorized for a *different* domain than the one you're
routing now, delete it and re-run the script to log in again and
select the new domain.

## 6. Render and start

```bash
./scripts/render-config.sh
docker compose up -d
./scripts/wait-for-stack.sh
```

## Troubleshooting

If something doesn't come up healthy, check
`https://github.com/<this-repo>/tree/main/docs/troubleshooting.md` in
the source repo (not duplicated into this package) for the full
layered debug flow — it covers the specific failure signatures for
each of the checks above (Ollama unreachable, LiteLLM unhealthy,
cloudflared 503s, DNS not actually on Cloudflare).
