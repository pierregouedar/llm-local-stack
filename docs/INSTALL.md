# Installation

Three roles, usually three machines on the same [Tailscale](https://tailscale.com) network:

| Role | What runs there | Folder |
|---|---|---|
| **Server** | the GPU machine (Windows or Linux): llama-swap + llama.cpp, the agent, idle sleep | [`server/`](../server/) |
| **Waker** (optional) | an always-on Linux box with Docker (NAS, Raspberry Pi...): Wake-on-LAN + remote start | [`waker/`](../waker/) |
| **Client** | the machine you code from (macOS or Linux): omp / OpenCode / any OpenAI client | [`client/`](../client/) |

Without a waker, everything works as long as the server is awake. Without Tailscale, use LAN IPs (`"listen"` in `server/config.json`) and keep the ports off the internet.

## 1. Server

1. Install llama.cpp, llama-swap, Python 3 and Tailscale, and download your GGUF model(s) (details: [server/README.md](../server/README.md#requirements)).
2. Clone this repository on the server.
3. Copy `server/config.example.json` to `server/config.json` and fill in the paths.
4. Adapt `server/llama-swap.template.yaml` to your models and VRAM ([TUNING.md](TUNING.md)).
5. Start it:
   - Windows: double-click `server\windows\start.bat`
   - Linux: `server/linux/start-agent.sh && server/linux/start.sh`
6. Check: `curl http://<server-ip>:8080/v1/models -H "Authorization: Bearer <key>"` (key in `server/secrets/llama-api-key.txt`).
7. For remote wake-up, enable Wake-on-LAN on the server ([server/README.md](../server/README.md#sleep-and-wake-on-lan)).

After a **reboot**, start it again (no service or scheduled task, by design).

## 2. Waker (optional)

On the always-on box, in a folder holding `waker/docker-compose.yml` and `waker/.env.example`:

```bash
cp .env.example .env && chmod 600 .env    # PC_MAC, BROADCAST, PC_IP, AGENT_TOKEN
docker compose up -d
curl http://localhost:8199/status          # {"pc_up": true, "stack_up": true}
```

`AGENT_TOKEN` is the content of `server/secrets/agent-token.txt`. Details: [waker/README.md](../waker/README.md).

## 3. Client

Copy `server/secrets/llama-api-key.txt` to the client (e.g. `~/llama-key.txt`), then:

```bash
cd client && ./install.sh <server-tailscale-name> <waker-tailscale-name> ~/llama-key.txt
```

The script **never overwrites** an existing config; it tells you what to merge. Then, in a new terminal:

```bash
pcstatus
pcwake && omp --model pc/cybertiel-mtp
```

Details and other clients: [client/README.md](../client/README.md).

## Daily use

| Where | Command | Effect |
|---|---|---|
| client | `pcwake` | wake the server and start the stack if needed |
| client | `pcstop` | stop the stack (frees the VRAM) |
| client | `pcstatus` | server awake? stack running? |
| server | `start` / `stop` script | same, locally |

The server goes back to sleep after `idle_sleep_minutes` without model activity or user input.

## Uninstall

- Server: run the stop script, stop the `agent.py` process, delete the repository folder.
- Waker: `docker compose down` in its folder.
- Client: remove `~/.omp/agent/{models,config}.yml`, the `pc` provider in OpenCode and the block appended to your shell rc file (a dated `.bak` copy was made before it was added).
