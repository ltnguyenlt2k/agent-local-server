# Ollama on Windows (native) — Phương án A, recommended default

This is the default `.env.example` assumes: Ollama installed natively
on Windows, GPU inference via Windows' native driver stack, while
Docker Compose (LiteLLM/Postgres/cloudflared) runs inside WSL and
reaches Ollama through Docker Desktop's `host.docker.internal`.

## Install

1. Install Ollama from the official Windows installer
   (https://docs.ollama.com/windows).
2. Verify:
   ```powershell
   ollama --version
   ollama list
   ```

## Pull a model

```powershell
ollama pull <MODEL_NAME>
```

Don't pick a model purely by file size — see "Model sizing" below and
`docs/security.md`'s sibling considerations in the root spec §14/§15
for tool-calling/context requirements if App A needs function calling.

## Verify the local API

```powershell
curl.exe http://localhost:11434/api/tags
curl.exe http://localhost:11434/v1/models
```

## `ollama run` vs. the service

`ollama run <model>` is for interactive CLI testing — you don't need to
keep it open. Applications (and LiteLLM) talk to the **Ollama service**
directly on port 11434. The model loads into VRAM on first request and
may stay loaded for a configurable keep-alive window afterward; the
service running does not mean the GPU is at 100% continuously — only
active inference does that.

## Bind address — read before changing

Ollama defaults to listening in a way primarily reachable from
localhost. If `./scripts/preflight.sh` reports Ollama unreachable from
Docker, you may need to set `OLLAMA_HOST=0.0.0.0:11434` so Docker/WSL
can reach it. **Do not do this blindly.** If you widen the bind
address:

- Check Windows Firewall rules for port 11434 immediately after.
- Do **not** port-forward 11434 on your router — it must stay
  unreachable from the Internet.
- Test from another device on your LAN that the port is *not*
  reachable from outside what you intended.

Goal: `Internet -> cannot reach Ollama directly`, `Docker/LiteLLM ->
can reach Ollama`.

## Auto-start

Ollama's Windows installer typically runs it in the background after
install and can be configured to start with Windows via Startup Apps.
Confirm this is set if you want machine B to behave as an always-on
server — see the root README's "Auto-start on boot" section.

## Model sizing / VRAM

VRAM must fit: model weights + KV cache + runtime buffers +
context-dependent memory — not just the model file size. Agent/coding
workloads typically need much larger context than short chat. Don't
hardcode a huge context window from day one; benchmark in stages
(8K/16K → 32K → 64K) and measure TTFT, tokens/s, peak VRAM, and
tool-call accuracy at each stage before committing to a context size.

## Context length — do this before wiring up any agent/tool-calling client

**Ollama's runtime context (`num_ctx`) defaults to 4096 tokens
regardless of what the model itself supports.** `ollama list`/`ollama
show` report the model's *maximum* supported context (e.g. 32768 for
`qwen2.5:7b`), which has nothing to do with what's actually used per
request unless you explicitly raise it. Confirmed by testing (on the
WSL-native path, but the underlying Ollama behavior is identical on
Windows): once system prompt + tool schemas + conversation exceed
4096 tokens, Ollama **silently truncates** — no error — which corrupts
tool-calling output and produces a completely empty response
(`content: "", tool_calls: []`). See `docs/troubleshooting.md` for the
full symptom description and diagnostic signal.

Set it persistently via a Windows environment variable (not just a
one-off PowerShell session variable, which won't survive the Ollama
service restarting):

1. Start Menu → search "Environment Variables" → **Edit environment
   variables for your account** (or System, if Ollama runs as a
   system-wide service).
2. Add a new variable: `OLLAMA_CONTEXT_LENGTH` = `16384` (start here
   per the staged sizing guidance above; raise only if the workload
   needs it and VRAM allows).
3. Restart the Ollama service/app for it to take effect (fully quit
   Ollama from the system tray, or `Stop-Process -Name ollama` in an
   elevated PowerShell, then relaunch).
4. Verify it actually took effect — don't just assume the restart
   picked it up:
   ```powershell
   ollama ps   # after sending at least one request; CONTEXT column should show 16384, not 4096
   ```

If you're running Ollama as a Windows Service (rather than the
tray-app default), set the variable in the service's configuration
instead of per-user environment variables, since services don't
inherit the interactive user's environment the same way.
