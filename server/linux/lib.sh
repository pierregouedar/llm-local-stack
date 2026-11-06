#!/usr/bin/env bash
# Shared helpers for the Linux scripts. Load with:  . "$(dirname "$0")/lib.sh"
#   SERVER_DIR : the server/ folder (config.json, secrets/, logs/, generated llama-swap.yaml)
#   cfg KEY    : prints a value from server/config.json
set -u

SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG_FILE="$SERVER_DIR/config.json"
SECRETS="$SERVER_DIR/secrets"
LOGS="$SERVER_DIR/logs"
[ -f "$CFG_FILE" ] || { echo "Missing config: copy server/config.example.json to server/config.json and edit it." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
mkdir -p "$SECRETS" "$LOGS"
chmod 700 "$SECRETS"

cfg() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1],encoding="utf-8-sig")).get(sys.argv[2],""); print(v)' "$CFG_FILE" "$1"; }

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOGS/stack.log"; }

# Random secret, created on first use, kept in server/secrets/ (not committed).
secret() {  # $1 = file name, $2 = optional prefix
  local f="$SECRETS/$1"
  if [ ! -f "$f" ]; then
    (umask 077; printf '%s%s' "${2:-}" "$(python3 -c 'import secrets; print(secrets.token_hex(32))')" > "$f")
  fi
  tr -d '\r\n' < "$f"
}

# Listen address: this machine's Tailscale IP (default) or a fixed IP from config.json.
listen_ip() {  # $1 = seconds to wait for Tailscale (default 120)
  local listen; listen="$(cfg listen)"
  if [ "$listen" != "tailscale" ]; then echo "$listen"; return; fi
  local i ip
  for ((i = 0; i < ${1:-120} / 2; i++)); do
    ip="$(tailscale ip -4 2>/dev/null | head -n1)"
    case "$ip" in 100.*) echo "$ip"; return ;; esac
    sleep 2
  done
  log "Tailscale unavailable: listening on 127.0.0.1 only"
  echo 127.0.0.1
}

# Builds server/llama-swap.yaml from the template (paths + API key).
write_llama_swap_config() {
  local key; key="$(secret llama-api-key.txt sk-local-)"
  python3 - "$SERVER_DIR" "$(cfg llama_server)" "$(cfg models_dir)" "$key" <<'PY'
import sys, pathlib
d, server, models, key = sys.argv[1:]
t = (pathlib.Path(d) / "llama-swap.template.yaml").read_text(encoding="utf-8")
t = t.replace("{{LLAMA_SERVER}}", server).replace("{{MODELS_DIR}}", models).replace("{{API_KEY}}", key)
out = pathlib.Path(d) / "llama-swap.yaml"
out.write_text(t, encoding="utf-8")
out.chmod(0o600)
PY
  echo "$SERVER_DIR/llama-swap.yaml"
}

# Stops the stack processes (the agent is not part of the stack).
stop_stack() {
  pkill -f "$SERVER_DIR/linux/idle-sleep.sh" 2>/dev/null
  pkill -x llama-swap 2>/dev/null
  pkill -x llama-server 2>/dev/null
  pkill -f 'opencode serve' 2>/dev/null
  return 0
}
