# waker/

A ~100-line Python service in a Docker container, for any **always-on Linux box on the same LAN as the GPU server**: NAS, Raspberry Pi, home server. It is optional: without it, everything works as long as the server is awake.

```
GET /status   {"pc_up": agent reachable, "stack_up": llama-swap reachable}
GET /wake     Wake-on-LAN if needed -> wait for the agent -> ask it to start the stack
              if it isn't running -> wait until llama-swap answers (up to ~4 min)
GET /stop     ask the agent to stop the stack (frees the VRAM)
```

The client's `pcwake` / `pcstatus` / `pcstop` commands call these routes.

## Setup

```bash
mkdir -p ~/pc-wake && cd ~/pc-wake
# copy docker-compose.yml and .env.example here
cp .env.example .env && chmod 600 .env
nano .env        # PC_MAC, BROADCAST, PC_IP, AGENT_TOKEN
docker compose up -d
curl http://localhost:8199/status
```

| Variable | Value |
|---|---|
| `PC_MAC` | MAC address of the server's network card |
| `BROADCAST` | broadcast address of the LAN (e.g. `192.168.1.255`) |
| `PC_IP` | server's Tailscale IP (or LAN IP), where the agent and llama-swap listen |
| `AGENT_TOKEN` | content of `server/secrets/agent-token.txt` |
| `AGENT_PORT`, `LLAMA_PORT`, `PCWAKE_PORT` | 8090, 8080, 8199 by default |

## Notes

- `network_mode: host` is required: the magic packet must reach the LAN.
- The service has **no authentication**: it can only wake the server and start or stop the model. Keep port 8199 on your tailnet / LAN, never on the internet.
- With Tailscale, the waker box must be in the same tailnet as the server and the clients.
- If `/wake` times out after 3 minutes, the server is probably shut down or was rebooted: run the start script on it once.
