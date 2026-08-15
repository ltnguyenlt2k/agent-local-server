# Ollama native inside WSL — Phương án B (alternative)

Use this instead of `docs/ollama-windows.md` if you want the entire AI
runtime on Linux, inside the same WSL distro Docker Compose runs in
(Ollama still stays **outside** Docker Compose either way).

## Install

Follow the official Linux install docs (https://docs.ollama.com/linux)
inside your WSL distro:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

This needs `sudo` (it creates a dedicated `ollama` system user and a
systemd service). If you don't have sudo access on the box:

```bash
sudo systemctl start ollama
sudo systemctl status ollama
sudo systemctl enable ollama   # requires systemd=true in /etc/wsl.conf — see below
```

### No-sudo alternative (manual install)

Verified working end-to-end (GPU detected, model pulled, inference
served) without root, for cases where `sudo` isn't available:

```bash
mkdir -p "$HOME/ollama"
curl -L -o /tmp/ollama.tar.zst \
  "https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst"
tar --zstd -xf /tmp/ollama.tar.zst -C "$HOME/ollama"
echo 'export PATH="$HOME/ollama/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/ollama/bin:$PATH"

ollama serve &        # or: setsid nohup ollama serve > ~/ollama.log 2>&1 &
```

Note the current release asset is `.tar.zst`, not the older `.tgz` —
if you see a 404 on a `.tgz` URL from an older guide, that's why. This
runs entirely as your own user: no systemd unit, no dedicated `ollama`
system account, no root. You're responsible for restarting `ollama
serve` yourself after a reboot (see README "Auto-start on boot" for
options, or just re-run the command above).

## Pull and verify

```bash
ollama pull <MODEL>
curl http://localhost:11434/api/tags
```

## The container-vs-shell gotcha

`localhost` inside the `litellm` container is the container itself, not
the WSL host — even though Ollama and Docker are both "in WSL" from
your point of view. You still need:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

(already in `docker-compose.yml`) and:

```dotenv
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

in `.env`. Don't assume `localhost` works just because everything is
"in the same WSL" — always confirm with `./scripts/preflight.sh`,
which runs the connectivity check from inside a throwaway container,
not from your shell.

## Bind address — you will likely need this

By default Ollama listens on `127.0.0.1:11434` only. Docker containers
reach the WSL host through a gateway address (typically `172.17.0.1`,
what `host.docker.internal` resolves to), which is a *different*
interface from `127.0.0.1` as far as the kernel's concerned — so a
loopback-only bind is invisible to them even though everything is "in
the same WSL." Confirmed by testing: LiteLLM failed with
`Cannot connect to host host.docker.internal:11434 ... [Connect call
failed ('172.17.0.1', 11434)]` until Ollama was restarted with:

```bash
OLLAMA_HOST=0.0.0.0:11434 ollama serve &
```

After that, both `curl http://127.0.0.1:11434/api/tags` (from the WSL
shell) and `curl http://172.17.0.1:11434/api/tags` (simulating the
Docker gateway) succeeded. This only widens exposure within WSL's own
network namespace, not to your LAN or the Internet — but see the
firewall caution in `docs/ollama-windows.md`'s "Bind address" section
if you're unsure, and never port-forward 11434 on your router
regardless of which bind address you use.

## systemd in WSL

`systemctl enable` requires systemd support enabled for the distro:

```ini
# /etc/wsl.conf
[boot]
systemd=true
```

then restart WSL (`wsl.exe --shutdown` from Windows, then reopen).
Without this, Ollama won't auto-start after a WSL restart and you'll
need another mechanism (see README "Auto-start on boot").

## Context length — read this before going anywhere near tool calling

**This is the single most impactful setting for agent/tool-calling
workloads, and it is not obvious.** Ollama caps the *runtime* context
window (`num_ctx`) at **4096 tokens by default**, regardless of what
the model itself supports (e.g. `qwen2.5:7b` supports up to 32768 —
`ollama list` and `ollama show` will both tell you the model's max,
which has nothing to do with what actually gets used at request time).

Confirmed by testing on this repo's deployment: with a real agent
sending 25 tool definitions + a long system prompt, the combined input
exceeded 4096 tokens. Ollama **silently truncated the context** (no
error, no warning) instead of rejecting the request — this corrupted
the tool-calling output structure and produced a *completely empty*
response (`content: "", tool_calls: []`) from the gateway, which looked
exactly like a client-side bug and took real debugging effort to trace
back to this cause. The tell: `prompt_eval_count` in the Ollama API
response gets stuck at a fixed number even as you increase input size
past the limit — see `docs/troubleshooting.md`.

### Fix — set `OLLAMA_CONTEXT_LENGTH` persistently via systemd

Don't just export it in a shell before running `ollama serve` — that
only lasts for that one process. Set it in a systemd drop-in so it
survives every restart/reboot:

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_CONTEXT_LENGTH=16384"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama
systemctl status ollama --no-pager
```

**Use the `tee`+heredoc form above, not `sudo systemctl edit ollama`.**
The interactive `systemctl edit` editor has been observed to silently
fail to save the drop-in file in some remote/terminal setups (no error
shown, but `/etc/systemd/system/ollama.service.d/` simply doesn't get
created) — always verify with `ls /etc/systemd/system/ollama.service.d/`
and `journalctl -u ollama | grep OLLAMA_CONTEXT_LENGTH` after restarting,
don't assume the edit was picked up just because the editor closed
without an error.

Verify it actually took effect — check the *active* context, not just
that the service is running:

```bash
ollama ps   # after sending at least one request; CONTEXT column should show your value, not 4096
```

### Sizing guidance

Follow the staged approach from the root spec (mục 14): start at 8K/16K,
measure, only go higher if the workload actually needs it. 16384 was
sufficient for a 25-tool agent + long system prompt in this repo's own
testing (`prompt_eval_count` scaled correctly with input size, no more
truncation). Bigger context costs more VRAM for KV cache — check
`nvidia-smi` after loading the model with the new setting before
assuming it fits.

### Gotcha when migrating from a manual/foreground `ollama serve` to the systemd service

If you were running Ollama manually (`ollama serve &`, e.g. from the
no-sudo install path above) and then install the official systemd
version, **the old manual process keeps holding port 11434** and the
new `ollama.service` will crash-loop with `Error: listen tcp
127.0.0.1:11434: bind: address already in use` (check with
`journalctl -u ollama`). Kill the old manual process first
(`pkill -f "ollama serve"`, confirm with `ss -ltnp | grep 11434`), then
restart the service. Also note: the systemd service uses its own model
store (`/usr/share/ollama/.ollama/models`, owned by the dedicated
`ollama` system user) — separate from a manual install's
`~/.ollama/models`. You'll need to `ollama pull <model>` again after
switching; nothing carries over automatically.
