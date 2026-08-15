# Network security — segmentation & container hardening

## 1-network vs. 2-network (this repo defaults to 2)

A single shared network for all three services works and is simpler,
but means `cloudflared` — the only service with any exposure to the
Internet — sits on the same Docker network as Postgres. This repo's
`docker-compose.yml` instead uses two networks to shrink blast radius:

```text
ai_frontend   cloudflared <-> litellm
ai_backend    litellm <-> postgres        (internal: true, no route out)
```

```text
postgres     -> ai_backend only
litellm      -> ai_frontend + ai_backend
cloudflared  -> ai_frontend only
```

Result: even if `cloudflared` were compromised, it has no Docker-level
network route to Postgres — a second layer of defense on top of never
publishing port 5432 to the host (`docs/security.md`).

If you'd rather simplify back to one network for local testing, that's
an accepted trade-off, not a violation of anything — just be aware
you're giving up this specific isolation.

## Resource limits

Each service in `docker-compose.yml` sets `mem_limit`/`cpus` (the
legacy Compose fields) rather than `deploy.resources.limits`, because
the latter only fully applies under Swarm mode — with plain
`docker compose` on the Docker Engine version in your WSL, it may be
silently ignored depending on version. **Verify which form actually
takes effect on your Docker Engine version** (`docker compose config`
will echo back what it parsed either way, but that doesn't prove
enforcement — check `docker stats` under load) before relying on these
limits to protect the GPU-hosting machine from a runaway container.

Current defaults (adjust if a service is starved or a limit turns out
too tight for your workload):

| Service | mem_limit | cpus |
|---|---|---|
| postgres | 512m | 1.0 |
| litellm | 1g | 2.0 |
| cloudflared | 256m | 0.5 |

## Logging rotation

All three services use `json-file` logging capped at `max-size: 10m,
max-file: 5` (50MB per service max) so Docker logs can't grow
unbounded on machine B's disk.

## `no-new-privileges`

All three services set `security_opt: [no-new-privileges:true]`. This
was safe to apply blindly — it doesn't change what the process needs
to do at startup, only blocks privilege escalation.

## What was intentionally NOT applied (needs testing first)

`read_only: true` and `cap_drop: [ALL]` on `litellm`/`postgres` are
**not** in `docker-compose.yml`. Both images may need to write
temporary files or hold specific capabilities at startup (Postgres
definitely writes to its data directory; LiteLLM's exact startup needs
weren't verified against the pinned image in this pass). Enabling
either blind risks the entrypoint failing in a way that's confusing to
debug. If you want to pursue this:

1. Try `read_only: true` + a `tmpfs` mount for whatever temp path the
   container needs, on a non-production run first.
2. Watch the container logs for permission errors on startup.
3. Record the result here (what worked, what didn't) before relying on
   it.

This section should be updated with real findings once someone runs
the pinned images on actual machine B hardware — right now it
documents the recommendation and the reason it wasn't turned on by
default, not a tested outcome.
