# App A integration — REFERENCE ONLY, OUT OF SCOPE

This document exists only so an external client ("App A": your
agent/application on a different machine) knows how to consume the API
this repository provides. **None of this is implemented in this
repository, and nothing here should ever be turned into source code,
packages, or services inside this repo.** See the root spec §2/§5/§26.

## What this repo gives you

```text
Base URL:  https://ai.example.com/v1
API Key:   <LiteLLM Virtual Key, from ./scripts/create-api-key.sh>
Model:     local-agent   (or whatever LITELLM_MODEL_ALIAS you set)
```

## Contract

```http
POST https://ai.example.com/v1/chat/completions
Authorization: Bearer <virtual-key>
Content-Type: application/json
```

```json
{
  "model": "local-agent",
  "messages": [{"role": "user", "content": "..."}]
}
```

OpenAI-compatible response. This repo's acceptance tests only cover
`chat/completions` (non-streaming and streaming) plus basic tool-call
response shape — don't assume every OpenAI endpoint/parameter works
until you've verified it against this specific gateway+model
combination.

## Client examples

Python:

```python
from openai import OpenAI
import os

client = OpenAI(
    base_url=os.environ["AI_BASE_URL"],
    api_key=os.environ["AI_API_KEY"],
)

response = client.chat.completions.create(
    model=os.environ["AI_MODEL"],
    messages=[{"role": "user", "content": "Hello"}],
)
print(response.choices[0].message.content)
```

TypeScript:

```ts
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: process.env.AI_BASE_URL,
  apiKey: process.env.AI_API_KEY,
});

const response = await client.chat.completions.create({
  model: process.env.AI_MODEL!,
  messages: [{ role: "user", content: "Hello" }],
});
console.log(response.choices[0].message.content);
```

App A should treat the provider as generic OpenAI-compatible
(`AI_PROVIDER=openai-compatible`), not hardcode Gemini/OpenAI-specific
behavior — that keeps it able to point at this gateway without
provider-specific branching.

## Streaming

Test both `stream=false` and `stream=true` end-to-end through Cloudflare
+ LiteLLM + Ollama before relying on streaming in production — buffering
anywhere in that chain would break SSE. `./scripts/smoke-test-public.sh`
only checks the non-streaming path; streaming needs a separate manual
check from App A's actual client library.

## Timeouts

Local model inference can have a much slower cold start than a cloud
API. Don't use a 5-second timeout. Use separate budgets:

```text
connect timeout:      short
request/read timeout: long, with margin over your measured cold-start time
agent/tool timeout:   workload-dependent
```

## Concurrency

A single local GPU is not a cloud cluster. Benchmark at 1/2/4
concurrent requests (latency, tokens/s, VRAM, queue behavior, OOM,
tool-call reliability) and give App A a concurrency cap/queue if the
GPU can't absorb bursts — this repo does not do that for you.

## Context budget

Don't send unbounded conversation history — local model KV cache is
VRAM-limited. App A should implement compaction/summarization/tool
result pruning and a max context budget; "the model's maximum context"
is not the same as "the context you should use on every request."

## Tool calling / MCP

If App A does tool calling, note that MCP client/server, agent loops,
and tool execution all live in App A — never in this repo. This repo
can optionally host a narrow **provider capability check** (does the
model return a well-formed `tool_calls` structure through this
gateway?) as a fixture, but that's a model/API capability test, not a
real MCP run. See the root spec §27 if you want to add such a fixture
here later — it wasn't included in this pass since it requires picking
a specific target model/tool schema first.

## Privacy note

Traffic to the local model doesn't leave machine B for
Google/Anthropic/OpenAI — but it does cross the public Cloudflare edge
in transit (it's a public tunnel). If you need to avoid the public edge
entirely, that's a private-networking alternative to Cloudflare
(e.g. Tailscale) — out of scope for this MVP, which uses Cloudflare per
the stated requirement.
