# server/

Runs on the machine with the GPU. Starts **llama-swap** (one OpenAI-compatible endpoint for all your models, protected by an API key), an optional **opencode serve**, an **idle-sleep watchdog**, and a tiny **agent** that lets the [waker](../waker/) start or stop the stack remotely.

Works on **Windows** (reference machine) and **Linux**. Nothing is installed as a service or scheduled task: you start it, it keeps running through sleep, and a reboot stops it.

```
server/
  config.example.json        copy to config.json and edit
  llama-swap.template.yaml   your models and every llama.cpp flag (commented)
  agent.py                   remote start/stop agent (Windows + Linux)
  windows/                   start.bat, stop.bat and the PowerShell scripts behind them
  linux/                     start.sh, stop.sh, start-agent.sh, idle-sleep.sh
  -- generated, never committed --
  config.json  llama-swap.yaml  secrets/  logs/
```

## Requirements

| | Windows | Linux |
|---|---|---|
| [llama.cpp](https://github.com/ggml-org/llama.cpp/releases) | CUDA release zip + matching `cudart` zip, extracted to the same folder | release build or your own CUDA build |
| [llama-swap](https://github.com/mostlygeek/llama-swap/releases) | `llama-swap_<version>_windows_amd64.zip` | `llama-swap_<version>_linux_amd64.tar.gz` |
| Python 3 | for the agent (`pythonw.exe` = no window) | `python3` (also used by the scripts), plus `curl` and `pgrep` |
| [Tailscale](https://tailscale.com) | recommended | recommended |
| GGUF model(s) | on an NVMe drive if possible (3.5x faster loading) | same |

## 1. Configure

Copy `config.example.json` to `config.json`:

| Key | Meaning |
|---|---|
| `llama_server` | path to `llama-server` (`.exe` on Windows) |
| `llama_swap` | path to `llama-swap` |
| `models_dir` | folder with the GGUF files, used as `{{MODELS_DIR}}` in the template |
| `python` | interpreter for the agent: `pythonw.exe` on Windows, `python3` on Linux |
| `opencode` | optional: path to `opencode` to also run `opencode serve` (password in `secrets/`) |
| `extra_path` | optional: folders prepended to `PATH` for opencode (e.g. your toolchains) |
| `listen` | `"tailscale"` = this machine's Tailscale IP; or a fixed IP (`192.168.1.20`, `127.0.0.1`) |
| `llama_swap_port`, `agent_port`, `opencode_port` | 8080, 8090, 4096 by default |
| `idle_sleep_minutes` | sleep after N minutes with no model activity and no user input; `0` disables it |

Linux example:

```json
{
  "llama_server": "/opt/llama.cpp/build/bin/llama-server",
  "llama_swap": "/usr/local/bin/llama-swap",
  "models_dir": "/srv/models",
  "python": "python3",
  "opencode": "",
  "extra_path": "",
  "listen": "tailscale",
  "llama_swap_port": 8080,
  "agent_port": 8090,
  "opencode_port": 4096,
  "idle_sleep_minutes": 30
}
```

Then edit **`llama-swap.template.yaml`**: model file names, sampling, and above all `-ncmoe` for your VRAM ([docs/TUNING.md](../docs/TUNING.md)). Model names (`cybertiel`, `cybertiel-mtp`...) are what clients put in `"model"`.

## 2. Start / stop

**Windows**: double-click `windows\start.bat` (agent + stack) and `windows\stop.bat` (stack only, frees the VRAM, e.g. before gaming).
`windows\start.ps1 -KeepAwakeHours 4` keeps the machine awake instead of watching for idle time.

**Linux**:

```bash
server/linux/start-agent.sh   # once per boot, only needed for the waker
server/linux/start.sh         # llama-swap (+ opencode serve) + idle-sleep
server/linux/stop.sh
```

On first start, secrets are created in `secrets/`:

| File | Used by |
|---|---|
| `llama-api-key.txt` | clients (copy it to the client machine) |
| `agent-token.txt` | the waker (`AGENT_TOKEN` in `waker/.env`) |
| `opencode-password.txt` | `opencode attach`, only if `opencode` is set |

Check: `curl http://<server-ip>:8080/v1/models -H "Authorization: Bearer <key>"`. Logs are in `logs/`.

## The agent

`agent.py` listens on `<listen>:8090` and answers only three token-protected routes, each mapped to a fixed script:

| Route | Action |
|---|---|
| `GET /status` | is llama-swap running and reachable? |
| `POST /start` | start script in "only if not running" mode |
| `POST /stop` | stop script (the agent itself keeps running) |

## Sleep and Wake-on-LAN

- **Windows**: the watchdog blocks sleep while the model is computing, and sleeps (S3) after `idle_sleep_minutes` with no model activity and no keyboard/mouse input. Power settings are not modified.
  Enable Wake-on-LAN in Device Manager > network adapter > *Power Management* ("Allow this device to wake the computer" + "Only allow a magic packet") and *Advanced* ("Wake on Magic Packet").
- **Linux**: the watchdog calls `systemctl suspend` (a polkit rule may be needed when no desktop session is active); user activity is only detected on X11 with `xprintidle`. Enable Wake-on-LAN with `ethtool -s <iface> wol g` and make it persistent with your network manager.
- Waking from **shutdown** (not sleep) needs BIOS support (ErP off, wake on PCI-E) and, on Windows, Fast Startup disabled.

## Coding agent rules

If you use `opencode serve` here, copy [`../client/AGENTS.md`](../client/AGENTS.md) to `~/.config/opencode/AGENTS.md` on this machine and add what is specific to it (shell, toolchain paths, "never stop the llama processes").
