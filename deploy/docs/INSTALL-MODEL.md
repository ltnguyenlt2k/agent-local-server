# Installing and running the model — separate from the gateway deploy

This is intentionally **not** part of `docker compose up`. Ollama runs
natively (outside Docker) on whichever machine will do inference —
that can be this same machine or a different one; either way it's a
separate install/run step from the gateway stack in this `deploy/`
folder. Do this before or after the gateway steps in `README.md`, in
either order — just make sure `OLLAMA_BASE_URL` in `.env` ends up
pointing at wherever you actually did this.

## Two supported paths — pick one

- **Windows native** — simplest if the gateway also runs in WSL on the
  same Windows machine (Docker Desktop's WSL integration makes
  `host.docker.internal` resolve automatically).
- **Linux/WSL native** — if you want the whole stack on Linux, or
  you're deploying to a Linux server directly.

## Windows native

1. Install from https://docs.ollama.com/windows
2. Verify:
   ```powershell
   ollama --version
   ollama list
   ```
3. Pull a model:
   ```powershell
   ollama pull <MODEL_NAME>
   curl.exe http://localhost:11434/api/tags
   ```
4. **Context length — do this before wiring up any agent/tool-calling
   client.** Ollama's runtime context (`num_ctx`) defaults to **4096
   tokens regardless of what the model supports**. Exceeding it with
   large tool-calling payloads causes Ollama to silently truncate
   input — no error, just a corrupted/empty response that looks like a
   client bug. Set it persistently:
   - Start Menu → "Environment Variables" → add `OLLAMA_CONTEXT_LENGTH`
     = `16384` (start here, raise only if the workload needs it and
     VRAM allows — check with `nvidia-smi` after loading a model)
   - Fully restart the Ollama service/app (system tray → quit, then
     relaunch, or `Stop-Process -Name ollama` in an elevated
     PowerShell then relaunch)
   - Verify: `ollama ps` after sending one request — `CONTEXT` column
     should show `16384`, not `4096`
5. **Bind address**: default Ollama listening is localhost-oriented.
   If the gateway's `./scripts/preflight.sh` reports Ollama
   unreachable from Docker, you likely need `OLLAMA_HOST=0.0.0.0:11434`
   as another persistent environment variable (same place as step 4).
   Before doing this: check Windows Firewall immediately after, never
   port-forward 11434 on your router, and confirm from another device
   on your LAN that the port isn't reachable from somewhere you didn't
   intend.

## Linux / WSL native

1. Official install (creates a systemd service, needs sudo):
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```
2. Pull a model:
   ```bash
   ollama pull <MODEL_NAME>
   curl http://localhost:11434/api/tags
   ```
3. **Context length + bind address — set both together, persistently,
   via a systemd drop-in.** Same 4096-default gotcha as above applies
   identically on Linux (same Ollama binary). Use `tee`+heredoc, not
   the interactive `sudo systemctl edit ollama` — that editor has been
   observed to silently fail to save the drop-in in some remote/
   terminal setups with no error shown:
   ```bash
   sudo mkdir -p /etc/systemd/system/ollama.service.d
   sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
   [Service]
   Environment="OLLAMA_HOST=0.0.0.0:11434"
   Environment="OLLAMA_CONTEXT_LENGTH=16384"
   EOF
   sudo systemctl daemon-reload
   sudo systemctl restart ollama
   sudo systemctl enable ollama
   systemctl status ollama --no-pager
   ```
   Verify it actually took effect — don't just trust that the restart
   picked it up:
   ```bash
   ls /etc/systemd/system/ollama.service.d/          # confirm the file exists
   ollama ps                                           # after 1 request; CONTEXT should be 16384
   ```
4. If migrating from a manual/foreground `ollama serve` you were
   running before installing the systemd service: the old process
   still holds port 11434 and the new service will crash-loop with
   `Error: listen tcp 127.0.0.1:11434: bind: address already in use`.
   Kill the old process first (`pkill -f "ollama serve"`), then
   restart the service. The systemd service also uses its own model
   store (`/usr/share/ollama/.ollama/models`) — you'll need to
   `ollama pull` again if switching from a prior manual install,
   nothing carries over automatically.
5. If WSL: `systemctl enable` requires `systemd=true` in
   `/etc/wsl.conf` under `[boot]`, then `wsl.exe --shutdown` from
   Windows and reopen. `localhost` inside a Docker container is the
   container itself, not the WSL host — the gateway's
   `docker-compose.yml` already has `extra_hosts:
   host.docker.internal:host-gateway` to handle this, just make sure
   `OLLAMA_BASE_URL=http://host.docker.internal:11434` in `.env`.

## Picking a model

Don't pick by file size alone — VRAM needs weights + KV cache +
runtime buffers, and agent/tool-calling workloads need meaningfully
more context than short chat. Benchmark in stages (8K/16K → 32K → 64K
context) rather than assuming a large context up front, and measure
peak VRAM (`nvidia-smi`) plus tool-call accuracy at each stage —
tool-calling *reliability* varies a lot between models at similar
parameter counts and isn't predictable from size alone; test the
actual workload (number of tools, system prompt length) before
committing to one.

## Verify from the gateway side

Once Ollama is up and a model is pulled, go back to `README.md` in
this folder and run `./scripts/preflight.sh` — it tests Docker→Ollama
reachability from inside a throwaway container, which is the actual
path that matters (not just `curl` from your own shell).
