<p align="center">
  <img src="assets/logo.svg" alt="local-llm-stack" width="128">
</p>

<h1 align="center">local-llm-stack</h1>

<p align="center">
  <b>Run a 35B coding model on a 10 GB gaming GPU, use it from anywhere, and wake the machine only when you need it.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/server-Windows%20%7C%20Linux-0078D6" alt="Windows | Linux">
  <img src="https://img.shields.io/badge/client-macOS%20%7C%20Linux-555555" alt="macOS | Linux">
  <img src="https://img.shields.io/badge/GPU-NVIDIA%20CUDA-76B900?logo=nvidia&logoColor=white" alt="NVIDIA CUDA">
  <img src="https://img.shields.io/badge/engine-llama.cpp-orange" alt="llama.cpp">
  <img src="https://img.shields.io/badge/router-llama--swap-blueviolet" alt="llama-swap">
  <img src="https://img.shields.io/badge/network-Tailscale-242424?logo=tailscale&logoColor=white" alt="Tailscale">
  <img src="https://img.shields.io/badge/waker-Docker-2496ED?logo=docker&logoColor=white" alt="Docker">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/prompt%20processing%20%4032k-2%2C949%20tok%2Fs%20(16%C3%97)-brightgreen" alt="prefill">
  <img src="https://img.shields.io/badge/generation-~50%20tok%2Fs-brightgreen" alt="generation">
  <img src="https://img.shields.io/badge/context-up%20to%20262k-blue" alt="context">
</p>

---

## What this is

A small, opinionated toolkit that turns a gaming PC into a **private, OpenAI-compatible LLM server** for coding agents:

- **Serve** one or more GGUF models through [llama.cpp](https://github.com/ggml-org/llama.cpp) behind [llama-swap](https://github.com/mostlygeek/llama-swap) (one URL, one API key, models loaded on demand). The server runs on **Windows or Linux**.
- **Reach it from anywhere** over [Tailscale](https://tailscale.com), from any OpenAI-compatible client ([omp](https://github.com/can1357/oh-my-pi) and [OpenCode](https://opencode.ai) configs included, for macOS and Linux).
- **Wake it on demand**: a tiny Docker service on an always-on box (NAS, Raspberry Pi, home server) sends Wake-on-LAN, then asks the server to start the model if it isn't running. The server goes back to sleep after 30 idle minutes.
- **No service, no scheduled task**: you start the stack yourself (one double-click on Windows, one command on Linux), and it survives sleep.

It ships with a **reference configuration measured on real hardware** (Windows, RTX 3080 10 GB, Ryzen 7 3800X, 32 GB DDR4) and the full benchmark log behind every parameter, so you can see *why* each flag is there and re-tune it for your machine.

## Results on the reference machine

Measured by querying `llama-server` with real source code, median of 2 runs.

| | Starting point | Tuned | |
|---|---|---|---|
| Prompt processing, 32k tokens | 178 tok/s | **2,949 tok/s** | **16×** |
| Prompt processing, 64k tokens | spilled out of VRAM | **2,461 tok/s** | 64k read in ~27 s |
| Generation | 20–37 tok/s | **~50 tok/s** (MTP) | |
| Second turn of a conversation | re-reads 2,048 tokens (10–15 s) | **20 tokens in 0.27 s** | |
| Average agent request | 72 s | **46 s** | −36 % |
| Model load | ~71 s | **~20 s** | NVMe |

```mermaid
xychart-beta
    title "Prompt processing on 32k tokens of code (tok/s)"
    x-axis ["Baseline", "Newer llama.cpp only", "Tuned flags", "Production"]
    y-axis "tok/s" 0 --> 3200
    bar [178, 193, 2835, 2949]
```

**What actually mattered**, in order:

1. **Not spilling out of VRAM.** With a MoE model partly on CPU, a `--n-cpu-moe` value one or two layers too low silently overflows into shared memory and divides speed by 10. This was the #1 problem.
2. **A recent llama.cpp build**: +51 to +67 % prompt processing at 32–64k.
3. **`-ub 4096`** (+41 %) and **`--load-mode none`** (+36 %).
4. **Q4_K instead of IQ4** quants when experts run on CPU: +40 % generation.
5. **MTP speculative decoding** (+5 to 20 % generation) and a **bounded reasoning budget** (−36 % time per agent request).

**No measurable effect**: Windows power plan, `-tb`, `--cache-reuse`, CUDA 13 vs 12, RAM/VRAM/GPU overclocking.

Every number, chart and dead end: [docs/BENCHMARKS.md](docs/BENCHMARKS.md). Raw data: [bench/results.csv](bench/results.csv) (164 measurements) and the full [optimization report](bench/REPORT.md).

---

## How it works

```mermaid
flowchart LR
    subgraph CLIENT["client/ (macOS or Linux)"]
        AG["coding agent<br/>omp / OpenCode / any OpenAI client"]
        SH["pcwake / pcstop / pcstatus"]
    end
    subgraph WAKER["waker/ (always-on box, optional)"]
        WAKE["pc-wake :8199<br/>Docker"]
    end
    subgraph SERVER["server/ (GPU, Windows or Linux)"]
        AGENT["agent.py :8090<br/>token"]
        SWAP["llama-swap :8080<br/>API key"]
        LLAMA["llama-server<br/>GGUF model"]
        IDLE["idle sleep<br/>30 min"]
    end
    SH -- "HTTP over Tailscale" --> WAKE
    WAKE -- "Wake-on-LAN" --> SERVER
    WAKE -- "status / start / stop" --> AGENT
    AGENT -- "start script" --> SWAP
    AG -- "OpenAI API over Tailscale" --> SWAP
    SWAP --> LLAMA
```

| Folder | Runs on | What it does | Required? |
|---|---|---|---|
| [`server/`](server/) | the GPU machine, Windows or Linux | llama-swap + llama.cpp behind an API key, start/stop scripts, idle sleep, and a 3-action agent for remote start | **yes** |
| [`waker/`](waker/) | NAS / Raspberry Pi / home server, Docker | Wake-on-LAN + "start the stack if it isn't running" | optional |
| [`client/`](client/) | your laptop, macOS or Linux | omp and OpenCode configs, `pcwake` / `pcstop` / `pcstatus`, agent rules; the installer **never overwrites existing files** | optional |
| [`bench/`](bench/) | the GPU machine (Windows) | reproducible benchmark script and every result | for tuning |
| [`docs/`](docs/) | | install guide, tuning guide, benchmarks, use case | |

A typical session from the client: `pcwake` → the server wakes up (or is already on) → the model is started if needed → your agent talks straight to llama-swap → you walk away → the server sleeps 30 minutes later.

---

## Adapting it to your setup

The scripts are generic; the **numbers** in [`server/llama-swap.template.yaml`](server/llama-swap.template.yaml) are the only machine-specific part.

| Your situation | What to do |
|---|---|
| **Linux server** | Same config and template; use `server/linux/*.sh` instead of `server/windows/`. See [server/README.md](server/README.md). |
| **Different GPU / VRAM** | Re-tune `--n-cpu-moe` (and possibly `-ub`) per model. Rule: the smallest value that leaves ~400–500 MB of VRAM free at peak, with your usual apps open. See [Tuning](#tuning-for-your-hardware). |
| **24 GB+ VRAM** | A 35B-A3B Q4 model (~20 GB) fits entirely on the GPU: drop `--n-cpu-moe` and expect much faster generation (not measured here). |
| **Different model** | Edit the template: file name, sampling (use the model card's recommended values), remove the MTP flags if the model has no MTP head. Update the model lists in `client/omp/models.yml` and `client/opencode/opencode.json`. |
| **Dense model instead of MoE** | `--n-cpu-moe` doesn't apply; use `-ngl` to choose how many layers go on the GPU. A dense model that doesn't fit in VRAM will be slow (3.5 tok/s for a 27B here). |
| **No always-on box** | Skip `waker/`. Start the stack on the server and keep it awake (`idle_sleep_minutes: 0`, or `start.ps1 -KeepAwakeHours N` on Windows). |
| **No Tailscale** | Set `"listen"` in `server/config.json` to a LAN IP or `127.0.0.1`. Don't expose port 8080 to the internet. |
| **Another client** (Continue, Aider, scripts…) | Any OpenAI-compatible client works: base URL `http://<server>:8080/v1`, API key from `server/secrets/llama-api-key.txt`, model name = a key of the template's `models:` section. |
| **bash instead of zsh** | `client/install.sh` appends the shell commands to `~/.bashrc` when your shell is bash. |

### Tuning for your hardware

Settings that **transfer as is** to any NVIDIA + partial CPU offload setup:

| Flag | Why |
|---|---|
| `--load-mode none` | without mmap, prompt processing is much faster once experts are on CPU |
| `-b 4096 -ub 4096` | large batches amortize copying CPU-side experts to the GPU (use 2048 if VRAM is tight) |
| `-ctk q8_0 -ctv q8_0` | same speed as f16, less VRAM, quality preserved |
| `-fa on` | flash attention |
| `-np 2 --checkpoint-min-step 2048` | agents: side requests (titles, sub-agents) don't evict the main conversation's cache |
| `--reasoning-budget 4000` | bounds thinking: shorter answers, faster agent loops |
| `CUDA_MODULE_LOADING=EAGER` | fixes `CUDA error: shared object initialization failed` at startup |
| Q4_K quants rather than IQ4 | faster when part of the model runs on CPU (+40 % generation here) |
| Models on NVMe | 3.5× faster loading |

Settings you **must re-measure**:

1. **`--n-cpu-moe`**: start high (e.g. 40 on 10 GB), lower it 1–2 at a time while peak VRAM stays below *total VRAM − 500 MB* and prompt processing doesn't collapse (a 3× drop means overflow). MTP needs ~1.3 GB more (≈ 3–4 extra expert layers on CPU).
2. **`-t`**: try your physical core count, then −1, −2. Generation is RAM-bound; SMT made it 12 % slower here.
3. **MTP**: only if the GGUF really contains MTP layers; `--spec-draft-n-max 2`.
4. **Context**: 64k per conversation is plenty for one-task-per-session agents; for long sessions use `-c 262144 -np 2 --kv-unified` at the cost of a few more expert layers on CPU.

On Windows, [`bench/bench.ps1`](bench/bench.ps1) automates this: it feeds a real code repository to the real server, records peak VRAM and appends everything to `bench/results.csv`.

```powershell
.\bench\bench.ps1 -Label try-ncmoe34 -SkipBench -PromptSizes 32768 -Runs 1 -CodeDir C:\code\some-repo `
  -ServerArgs "-ngl 99 --n-cpu-moe 34 -c 131072 -np 2 -fa on -ctk q8_0 -ctv q8_0 -b 4096 -ub 4096 -t 6 --load-mode none"
```

Full method and diagnosis table: [docs/TUNING.md](docs/TUNING.md).

---

## Reference models

What the template serves on the reference machine (one model in VRAM at a time; switching takes ~20 s to 2 min):

| llama-swap name | Prompt processing @32k | Generation | Context per conversation | Use |
|---|---|---|---|---|
| `cybertiel` | ~2,950 tok/s | ~47 tok/s | 64k | fastest prompt processing |
| **`cybertiel-mtp`** | ~2,380 tok/s | **~50 tok/s** | 64k | **daily coding** |
| `cybertiel-262k` | ~2,440 tok/s | ~40 tok/s (32k → 128k) | **~250k** | long sessions |
| `heretic` | ~2,200 tok/s | ~47 tok/s | 64k | general use |

Models: [Cyber-Tiel Coder 35B-A3B](https://huggingface.co/peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP) (`UD-Q4_K_S`) and Qwen3.6-35B-A3B heretic (`Q4_K_S`). Both are MoE models with ~3B active parameters, which is what makes a 35B usable with 10 GB of VRAM.

---

## Quick start

**1. Server (Windows or Linux, NVIDIA GPU)**

```bash
cp server/config.example.json server/config.json      # then set the paths
# edit server/llama-swap.template.yaml for your models and VRAM
```

- Windows: double-click `server\windows\start.bat`
- Linux: `server/linux/start-agent.sh && server/linux/start.sh`

Secrets (API key, agent token) are generated in `server/secrets/` on first start.

**2. Waker (optional, any always-on Linux box with Docker)**

```bash
cd waker && cp .env.example .env    # server MAC, broadcast, server IP, agent token
docker compose up -d
```

**3. Client (macOS or Linux)**

```bash
cd client && ./install.sh <server-tailscale-name> <waker-tailscale-name> ~/llama-key.txt
pcwake && omp --model pc/cybertiel-mtp
```

Step-by-step guide: [docs/INSTALL.md](docs/INSTALL.md). Each folder has its own README with the details.

---

## Repository layout

```
server/
  config.example.json          machine config (copy to config.json)
  llama-swap.template.yaml     models and every llama.cpp flag, commented
  agent.py                     remote start/stop agent (Windows + Linux)
  windows/                     start.bat, stop.bat + PowerShell scripts
  linux/                       start.sh, stop.sh, start-agent.sh, idle-sleep.sh
waker/                         docker-compose.yml + .env.example
client/                        install.sh, shell.sh, omp/, opencode/, AGENTS.md
bench/                         bench.ps1, results.csv, REPORT.md
docs/                          INSTALL, TUNING, BENCHMARKS, USE-CASE
assets/                        logo
```

Generated and **never committed**: `server/config.json`, `server/secrets/`, `server/logs/`, `server/llama-swap.yaml`, `waker/.env`.

## Security

| Service | Exposed on | Protection |
|---|---|---|
| llama-swap `:8080` | Tailscale IP only | API key |
| agent `:8090` | Tailscale IP only | token; 3 fixed actions, no arbitrary commands |
| opencode serve `:4096` (optional) | Tailscale IP only | password |
| pc-wake `:8199` | tailnet + LAN | none: it can only wake the server or stop the model |

The included [`client/AGENTS.md`](client/AGENTS.md) rules tell coding agents not to invent missing data, to stop and ask when information is missing, to test against real data, not to write outside the project and never to `git push` without asking. With a local model this mattered: it would otherwise fabricate inputs and write tests that validated them.

## Limitations

- After a **reboot**, nothing starts on its own (by design): run the start script once.
- Wake-on-LAN works from **sleep**; waking from shutdown needs BIOS support (and Fast Startup disabled on Windows).
- `--n-cpu-moe` values are specific to 10 GB of VRAM.
- The reference measurements come from the Windows machine; the Linux scripts are syntax-checked but have not been run on a Linux GPU server yet.
- `bench/bench.ps1` is Windows-only.
- Model **quality** was checked on real coding tasks, not with a systematic benchmark.

## Background

Why this exists, the constraints (gaming PC that must stay on Windows, no WSL, nothing to buy, no hidden services) and the full tuning journey: [docs/USE-CASE.md](docs/USE-CASE.md).

## License

[MIT](LICENSE). Models and third-party tools keep their own licenses.
