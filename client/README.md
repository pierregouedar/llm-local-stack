# client/

Everything for the machine you work from (macOS or Linux): configs for [omp](https://github.com/can1357/oh-my-pi) and [OpenCode](https://opencode.ai), shell commands to wake the server, and the rules given to coding agents.

```
client/
  install.sh               installs everything below, never overwrites an existing file
  shell.sh                 pcstatus / pcwake / pcstop / ompw / ocw (appended to ~/.zshrc or ~/.bashrc)
  omp/models.yml           "pc" provider -> ~/.omp/agent/models.yml
  omp/config.yml           roles, approvals, git safety prompts -> ~/.omp/agent/config.yml
  opencode/opencode.json   "pc" provider + /goal command -> ~/.config/opencode/opencode.json
  AGENTS.md                rules for coding agents (no invented data, real tests, stay in the project)
```

## Install

Copy `server/secrets/llama-api-key.txt` from the server to this machine, then:

```bash
./install.sh <server-tailscale-name> <waker-tailscale-name> ~/llama-key.txt
```

Use `-` as the waker name if you don't run one. Any file that already exists is left untouched and the script tells you what to merge by hand (your shell rc file gets a dated backup before the block is appended).

Check in a new terminal:

```bash
pcstatus
omp -p --no-session "Reply with exactly: OK"
opencode models pc
```

## Commands

| Command | Effect |
|---|---|
| `pcstatus` | is the server awake? is the stack running? |
| `pcwake` | wake the server and start the stack if needed |
| `pcstop` | stop the stack (frees the VRAM) |
| `ompw ...` / `ocw ...` | `pcwake`, then omp / OpenCode with the same arguments |
| `omp --model pc/cybertiel-mtp` | pick a model (names from `server/llama-swap.template.yaml`) |

## Other clients

Any OpenAI-compatible tool works without this folder:

- base URL: `http://<server>:8080/v1`
- API key: content of `server/secrets/llama-api-key.txt`
- model: one of the names in the `models:` section of the llama-swap template

If you rename or add models on the server, update the model lists in `omp/models.yml` and `opencode/opencode.json` too (ids and context sizes).
