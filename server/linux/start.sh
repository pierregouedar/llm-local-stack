#!/usr/bin/env bash
# Starts (or restarts) the stack:
#   - llama-swap on <listen>:<llama_swap_port>, with an API key (config generated from the template)
#   - opencode serve (optional, if "opencode" is set in config.json) on <listen>:<opencode_port>
#   - the idle-sleep watchdog (unless idle_sleep_minutes is 0)
# --if-not-running : do nothing if the stack is already running and answering (used by the agent).
. "$(dirname "$0")/lib.sh"

PORT="$(cfg llama_swap_port)"

if [ "${1:-}" = "--if-not-running" ]; then
  ip="$(listen_ip 30)"
  if pgrep -x llama-swap >/dev/null; then
    for _ in $(seq 30); do
      if curl -s -o /dev/null --max-time 2 "http://$ip:$PORT/health"; then
        log "stack already running and answering, nothing to do"; exit 0
      fi
      sleep 2
    done
  fi
  log "stack missing or not answering, full restart"
fi

stop_stack
sleep 2
ip="$(listen_ip)"

# 1) llama-swap (config regenerated on every start)
yaml="$(write_llama_swap_config)"
cd "$SERVER_DIR"
nohup "$(cfg llama_swap)" --config "$yaml" --listen "$ip:$PORT" \
  >> "$LOGS/llama-swap.out.log" 2>> "$LOGS/llama-swap.err.log" < /dev/null &
log "llama-swap started on $ip:$PORT"

# 2) opencode serve (optional)
oc="$(cfg opencode)"
if [ -n "$oc" ]; then
  extra="$(cfg extra_path)"; [ -n "$extra" ] && export PATH="$extra:$PATH"
  OPENCODE_SERVER_PASSWORD="$(secret opencode-password.txt)" \
    nohup "$oc" serve --hostname "$ip" --port "$(cfg opencode_port)" \
    >> "$LOGS/opencode.out.log" 2>> "$LOGS/opencode.err.log" < /dev/null &
  log "opencode serve started on $ip:$(cfg opencode_port)"
fi

# 3) idle-sleep watchdog
if [ "$(cfg idle_sleep_minutes)" -gt 0 ] 2>/dev/null; then
  nohup "$SERVER_DIR/linux/idle-sleep.sh" >/dev/null 2>&1 < /dev/null &
  log "idle-sleep watchdog started ($(cfg idle_sleep_minutes) min)"
else
  log "idle sleep disabled"
fi
echo "llama-swap: http://$ip:$PORT (logs: $LOGS)"
