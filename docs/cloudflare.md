# Cloudflare Tunnel setup

Uses a **locally-managed tunnel** (config file + credentials file
mounted into the `cloudflared` container) rather than the simpler
`--token` remotely-managed mode. This was a deliberate choice made
after hitting a real blocker — see "Why not `--token` mode?" below —
not the first thing tried.

## Prerequisite: your domain's zone must be on Cloudflare

This is the part that's easy to get wrong, and got gotten wrong once
while building this repo, so it's worth stating plainly:

> **Cloudflare Tunnel hostname routing only works for domains whose
> DNS zone is in your Cloudflare account.** Adding a CNAME record at a
> *different* DNS provider (your registrar, e.g.) pointing to
> `<tunnel-id>.cfargotunnel.com` does **not** work — confirmed both by
> Cloudflare's own docs ("the cfargotunnel.com subdomain only proxies
> traffic for DNS records in the same Cloudflare account") and by
> testing it: the AAAA record resolves to a non-routable placeholder
> (`fd10::/8`), not a real Cloudflare IP, and the `curl`/browser
> request fails or times out.

If your domain (or the subdomain you want to use) isn't already on
Cloudflare:

1. Cloudflare Dashboard → **Add a domain** → **Connect a domain**
   (not "Buy a domain" or "Transfer a domain" — you're keeping the
   domain where it is, just pointing its DNS at Cloudflare).
2. Enter the domain, pick the **Free** plan, continue past the DNS
   scan (it's fine if it finds 0 existing records).
3. Cloudflare shows two nameservers (e.g. `xxx.ns.cloudflare.com`,
   `yyy.ns.cloudflare.com`). At your current registrar/DNS provider,
   replace the domain's nameservers with those two.
4. Wait for Cloudflare to detect the change and mark the zone
   **Active** (minutes to a few hours). `dig NS yourdomain.com` should
   show the Cloudflare nameservers once it's propagated.

**This affects the whole domain's DNS**, not just one subdomain —
there is no free-tier way to delegate only a subdomain to Cloudflare
while leaving the rest of the domain elsewhere ("Subdomain Setup" as
a distinct Cloudflare product is Enterprise-only). If you don't want
to move an existing site's domain to Cloudflare, use a separate
domain dedicated to this gateway instead — that's what this repo's
own deployment did.

## Automated: `scripts/cloudflare-setup.sh`

Once your domain's zone is Active on Cloudflare:

```bash
./scripts/cloudflare-setup.sh <tunnel-name> ai.example.com
# e.g.: ./scripts/cloudflare-setup.sh local-ai-gateway ai.example.com
```

This drives the `cloudflared` CLI to create a tunnel, route the DNS
hostname, and render `cloudflared/config.yml` + copy the tunnel's
credentials file into `cloudflared/tunnel-credentials.json` (both
gitignored — only `cloudflared/config.yml.template` is tracked). It
also writes `CLOUDFLARE_TUNNEL_ID` and `PUBLIC_AI_BASE_URL` into
`.env`. Verified end-to-end against a live tunnel: real HTTP 200 with
the expected response body, through the actual public Internet.

It requires you interactively once: `cloudflared tunnel login` opens a
URL you must visit and authorize under your own Cloudflare account —
**select the domain you're routing to** when prompted (skipped
automatically if `~/.cloudflared/cert.pem` already exists, but that
cert only authorizes whatever zone was selected during its own login;
if you added a new domain to Cloudflare after an earlier login, delete
the old cert and re-run to select the new one). Everything else runs
non-interactively.

**It only ever creates a new, separate tunnel** — it never modifies or
deletes anything you already have configured (e.g. an existing tunnel
serving another site stays untouched).

## Why not `--token` mode?

The simpler `--token` remotely-managed mode (a single token, no local
config file) was the original design here. It technically works for
the tunnel *connection* — but configuring which hostname maps to which
local service (the "Public Hostname" setting) for a `--token` tunnel
can only be done through the **Cloudflare Zero Trust dashboard**. As
of building this repo, opening that dashboard for the first time
prompts an "Activate Zero Trust" checkout screen asking for a payment
method on file — even though the plan shown is $0/month. That's a real
adoption blocker, not just an annoyance: without it, a `--token`
tunnel with no ingress rules configured returns `503` for every
request (confirmed: `docker compose logs cloudflared` shows *"No
ingress rules were defined... cloudflared will return 503 for all
incoming HTTP requests"*).

The locally-managed approach (`cloudflared/config.yml` +
`tunnel-credentials.json`, both produced by `cloudflare-setup.sh`)
sets the same hostname→service mapping in a file instead, using
credentials `cloudflared` already saves locally when a tunnel is
created via the CLI. No Zero Trust activation, no payment method,
ever. If you've already activated Zero Trust and prefer the dashboard,
you can switch `docker-compose.yml`'s `cloudflared` service back to
`--token` mode manually — `CLOUDFLARE_TUNNEL_TOKEN` is still in
`.env.example` for that case.

## Subdomain doesn't touch other existing sites

```text
your-main-site.com      -> unchanged, wherever it already runs
ai.your-gateway-domain.com  -> this repo, via Cloudflare Tunnel
```

If you already run a Cloudflare Tunnel on the same machine for another
site (common setup), this repo's tunnel is independent — different
tunnel ID, different credentials file, different `docker-compose.yml`
service. Creating it doesn't touch the other tunnel's config,
credentials, or DNS records.

## Cloudflare Access — think before enabling

Cloudflare Access can put an interactive login page in front of a
hostname. **Don't enable it on your gateway hostname for the MVP** — a
generic OpenAI-compatible SDK on App A doesn't know how to complete a
browser login flow, so it would break the API contract entirely.

MVP auth model is:

```text
Cloudflare Tunnel public hostname + LiteLLM Bearer Virtual Key
```

If you need stronger perimeter hardening later, look at Cloudflare
service tokens / mTLS / WAF rules — but only after the plain end-to-end
flow works, and only if App A can actually send the extra
headers/credentials required.

## Testing

- Local (bypasses Cloudflare): `./scripts/smoke-test-local.sh`
- Public (through the tunnel): `./scripts/smoke-test-public.sh` — run
  this from a network other than machine B's when possible (e.g.
  mobile data), not only from machine B itself, to catch tunnel/DNS
  issues a same-machine test would miss.

## If cloudflared won't come up, or requests 503

```bash
docker compose logs -f cloudflared
```

- `"No ingress rules were defined..."` → `cloudflared/config.yml`
  wasn't mounted/rendered, or is missing the `ingress:` section. Re-run
  `./scripts/cloudflare-setup.sh`.
- `"Authentication error"` on `route dns` → the domain's zone isn't in
  this Cloudflare account yet, or `cert.pem` was authorized for a
  different domain — see the prerequisite section above.
- Tunnel connects (`Registered tunnel connection` in logs) but the
  public hostname still 404s/503s → double check
  `cloudflared/config.yml`'s `ingress.hostname` matches
  `PUBLIC_AI_BASE_URL` in `.env` exactly.

See `docs/troubleshooting.md` for the full layered debug flow.
