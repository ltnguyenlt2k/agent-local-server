# Architecture

## Scope

This repository runs **only on machine B** and turns it into an
OpenAI-compatible AI gateway. Anything about "Machine A" (application,
agent orchestration, MCP client/server, tool execution) is out of
scope — it's mentioned only to explain the API contract this repo must
serve. See the root spec document
(`local-ai-gateway-implementation-plan-v3-reviewed.md`, §2) for the
full scope boundary this repo was built against.

## Components and roles

| Component | Role | Runs where |
|---|---|---|
| Ollama | Loads/serves the local model, does inference | Native on machine B, **outside** Docker Compose |
| LiteLLM | OpenAI-compatible gateway: auth, virtual keys, model aliasing, routing, usage tracking | Docker Compose |
| PostgreSQL | Stores LiteLLM's virtual keys / usage / config | Docker Compose |
| cloudflared | Outbound-only tunnel exposing LiteLLM to the Internet | Docker Compose |

```text
LiteLLM -> Ollama -> Local model -> GPU
```

Ollama is not a gateway: it doesn't do per-app API keys, user
management, or quota — that's LiteLLM's job, standing in front of it.

## Trust boundary

```text
UNTRUSTED / INTERNET
       │
       ▼
Cloudflare
       │
       ▼
LiteLLM authentication boundary   <- Bearer <Virtual Key> checked here
       │
       ▼
TRUSTED MACHINE B INTERNAL
       │
       ├── PostgreSQL   (ai_backend network, no route to Internet)
       └── Ollama
             │
             ▼
            GPU
```

Never invert this into `Internet -> Ollama -> LiteLLM`. LiteLLM must
always be the thing that authenticates a request before Ollama ever
sees it.

## Docker network segmentation

```text
ai_frontend   cloudflared <-> litellm
ai_backend    litellm <-> postgres      (internal: true — no route out)
```

`cloudflared` is the only service with any path to/from the Internet.
It only sits on `ai_frontend`, so even if it were compromised it has no
Docker-level network route to Postgres — on top of Postgres's port
never being published to the host (see `docs/network-security.md`).

## End-to-end request flow

```text
App A
  │ POST https://ai.example.com/v1/chat/completions
  │ Authorization: Bearer <Virtual Key>
  ▼
Cloudflare edge
  ▼
cloudflared (ai_frontend)
  ▼
litellm:4000 (ai_frontend + ai_backend)
  │ validate Virtual Key against Postgres
  │ resolve model alias (e.g. "local-agent") -> ollama_chat/<OLLAMA_MODEL>
  ▼
host.docker.internal:11434  (native Ollama on machine B)
  ▼
local model -> GPU inference
  ▼
response flows back through the same path to App A
```

## Model alias indirection

App A always requests `model: <LITELLM_MODEL_ALIAS>` (default
`local-agent`) — never the real Ollama model name. Swapping the local
model is a one-line change to `OLLAMA_MODEL` in `.env` followed by
`./scripts/render-config.sh && docker compose up -d litellm`; App A's
code and config never change. The same indirection is what lets future
cloud providers be added to `litellm/config.yaml.template` later
without App A caring (see the commented example in that file) — note
that a Claude Pro/ChatGPT Plus *subscription* is not the same
entitlement as API access; routing to those providers later still
needs a real API key + billing for that provider.
