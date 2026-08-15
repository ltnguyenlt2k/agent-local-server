# Troubleshooting

Debug **one layer at a time**, in order. Don't change LiteLLM config
because of a symptom that's actually a network problem two layers down.

```text
Layer 1: Is Ollama running at all?
Layer 2: Is Ollama bound to an address Docker can reach?
Layer 3: Is Windows Firewall blocking it?
Layer 4: Does host.docker.internal resolve inside containers?
Layer 5: WSL networking mode (mirrored vs NAT)?
Layer 6: Is LiteLLM itself healthy (Postgres connection, config parse)?
Layer 7: Is cloudflared connected / is its ingress config correct?
Layer 8: Is the hostname's DNS zone actually on Cloudflare?
```

## Layer 1–5: Docker can't reach Ollama

```bash
./scripts/preflight.sh
```

does exactly this check, from inside a throwaway container (not your
shell — `host.docker.internal` can resolve differently between the
two, see `docs/ollama-wsl.md`). If it fails:

```bash
docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  curlimages/curl:latest \
  http://host.docker.internal:11434/api/tags
```

Manual layer checks:

- **Layer 1**: `ollama list` / `ollama --version` on machine B — is the
  service actually up?
- **Layer 2**: default Ollama bind is localhost-oriented; Docker/WSL
  containers may not reach it without `OLLAMA_HOST=0.0.0.0:11434` — see
  the bind-address section in `docs/ollama-windows.md` (read the
  security caveats there before changing this).
- **Layer 3**: Windows Firewall rule for port 11434 — check inbound
  rules if you changed the bind address.
- **Layer 4**: `getent hosts host.docker.internal` inside a container;
  behavior differs between Docker Desktop WSL integration and a native
  Docker Engine installed directly in WSL.
- **Layer 5**: WSL networking mode changes can affect what's reachable
  from WSL to Windows and vice versa — check `wsl.conf`/WSL settings if
  the above don't explain it.

## Ollama reachable but tool-calling responses come back empty

Symptom: HTTP 200, no error anywhere in `docker compose logs litellm`,
but the response is completely empty — `content: ""` and `tool_calls:
[]` (or the equivalent in whatever client library you're using). This
is **not a network/auth problem** (those layers already passed if
you're seeing a 200) — it happens specifically with agent workloads
that send many tool definitions and/or a long system prompt.

**Root cause, confirmed by testing on this repo's own deployment:**
Ollama defaults to a 4096-token runtime context (`num_ctx`) regardless
of what the model supports. Once system prompt + tool schemas + user
message exceeds that, Ollama silently truncates the input — no error —
which corrupts the tool-calling output structure and produces an empty
response. Full writeup, fix, and the exact diagnostic signal
(`prompt_eval_count` getting stuck at a fixed value as you add more
tools) are in `docs/ollama-wsl.md`'s "Context length" section — **read
that before assuming this is a LiteLLM or App A bug**, it cost real
debugging time before being traced back to Ollama's context default.

Quick check: `ollama ps` while a request is in flight — the `CONTEXT`
column shows what's actually active. If it's `4096` and your workload
has more than a handful of tools, this is almost certainly it.

Even after fixing context, a model can still be *inherently* unreliable
at emitting well-formed tool calls for large tool sets (this is a
separate, model-capability issue — not something this repo's
infrastructure can fully fix). If context is confirmed correct and
empty/malformed tool-calling responses persist, that points to the
model's own tool-calling reliability at the given tool count, not a
config problem — see the root spec's mục 15/27 for how to
evaluate/benchmark that before switching models.

## Layer 6: LiteLLM unhealthy

```bash
docker compose logs -f litellm
docker compose ps
```

Common causes:

- `litellm/config.yaml` wasn't rendered (`./scripts/render-config.sh`)
  or is stale relative to `.env` — the compose mount uses the rendered
  file, not the template.
- Postgres not yet healthy — `litellm` has `depends_on: postgres:
  condition: service_healthy`, so check `docker compose logs postgres`
  first.
- `DATABASE_URL` doesn't match `POSTGRES_USER`/`POSTGRES_PASSWORD`/
  `POSTGRES_DB` — these must agree.

## Layer 7: cloudflared / public endpoint

```bash
docker compose logs -f cloudflared
```

- `"No ingress rules were defined... cloudflared will return 503 for
  all incoming HTTP requests"` → `cloudflared/config.yml` is missing
  or wasn't mounted. Re-run `./scripts/cloudflare-setup.sh`, confirm
  `cloudflared/config.yml` exists and has an `ingress:` section with
  `service: http://litellm:4000` (not `localhost:4000` — `localhost`
  inside the `cloudflared` container is the container itself).
- `cloudflared` connects (`Registered tunnel connection` in logs, no
  ingress warning) but requests still fail → check
  `cloudflared/config.yml`'s `ingress.hostname` matches
  `PUBLIC_AI_BASE_URL` in `.env` exactly.
- `cloudflared` container itself unhealthy/restarting → check
  `cloudflared/tunnel-credentials.json` exists and is valid JSON
  (`AccountTag`/`TunnelSecret`/`TunnelID` keys) — see
  `docs/cloudflare.md`.

## Layer 8: DNS zone not actually on Cloudflare

`cloudflared tunnel route dns` fails with `Authentication error`, or
the public hostname resolves to a non-routable placeholder address
(`fd10::/8` was observed) instead of a real Cloudflare IP:

- Confirm with `dig NS yourdomain.com` — the nameservers must be
  Cloudflare's (`*.ns.cloudflare.com`), not your registrar's.
- If they aren't, the domain's zone was never added to Cloudflare, or
  the nameserver change hasn't propagated yet — see the prerequisite
  section in `docs/cloudflare.md`.
- If `cert.pem` predates adding the domain to Cloudflare, delete
  `~/.cloudflared/cert.pem` and re-run `./scripts/cloudflare-setup.sh`
  to log in again and select the (now-added) domain.

## Failure scenarios and expected behavior

| Scenario | Expected |
|---|---|
| Ollama stopped | LiteLLM stays reachable; requests to the model alias return a controlled upstream error, not a gateway crash. Restarting Ollama should make requests work again without restarting LiteLLM. |
| Model not pulled | Upstream "model not found" style error. Fix: `ollama pull <MODEL>` on machine B. |
| Context too small for the workload | HTTP 200, completely empty response (no text, no tool_calls), no errors anywhere. Not a crash — Ollama silently truncates. See "Ollama reachable but tool-calling responses come back empty" above and `docs/ollama-wsl.md`. |
| LiteLLM stopped | Cloudflare/clients see a 502-style upstream failure. |
| cloudflared stopped | `http://127.0.0.1:${LITELLM_PORT}` still works locally; only the public hostname stops resolving to this stack. |
| PostgreSQL stopped | Key management/gateway behavior depends on the pinned LiteLLM release — verify on your actual deployment; container health/logs must point at Postgres, not a generic error. |
| Machine B loses Internet | Local Ollama inference can still work if something is calling it directly; the public Cloudflare endpoint stops being reachable from Machine A. |
| Machine B sleeps | API becomes unavailable. If you want 24/7 uptime, disable Windows sleep/hibernate for this machine (display can still turn off). |

## Never do this while debugging

- Don't leave a healthcheck that always passes just to make
  `docker compose ps` look green. `cloudflared`'s `tunnel --metrics
  127.0.0.1:2000 ready` was tested directly against the pinned
  2026.8.2 binary (real quick tunnel, both quic and http2 transport) —
  confirmed working, including the non-obvious requirement that
  `--metrics` must come before the `ready` subcommand. `litellm`'s
  `/health/readiness` endpoint has **not** been tested against a real
  container yet — confirm it exists on your pinned `LITELLM_IMAGE`
  before trusting that healthcheck.
- Don't change more than one layer at a time — you'll lose the ability
  to tell which change fixed (or broke) things.
