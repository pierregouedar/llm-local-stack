#!/usr/bin/env bash
# Idle-sleep watchdog (Linux): suspends the machine when llama-server has been idle for
# idle_sleep_minutes AND no user is active (graphical idle time via xprintidle if available).
# Suspending uses "systemctl suspend" (may need a polkit rule when run without a desktop session).
. "$(dirname "$0")/lib.sh"

IDLE_MIN="$(cfg idle_sleep_minutes)"
CHECK=60
BUSY_CPU_SEC=3   # CPU seconds per minute above which llama-server counts as busy

cpu_seconds() {  # total CPU time of llama-server processes, in seconds
  local total=0 t
  for t in $(ps -C llama-server -o times= 2>/dev/null); do total=$((total + t)); done
  echo "$total"
}
user_idle_min() {  # minutes since last user input; large if unknown (headless)
  if command -v xprintidle >/dev/null && [ -n "${DISPLAY:-}" ]; then
    echo $(( $(xprintidle) / 60000 ))
  else
    echo 999999
  fi
}

last_active=$(date +%s)
prev=$(cpu_seconds)
log "idle-sleep: suspend after $IDLE_MIN min without activity"
while true; do
  sleep "$CHECK"
  cur=$(cpu_seconds)
  if [ $((cur - prev)) -ge "$BUSY_CPU_SEC" ]; then last_active=$(date +%s); fi
  prev=$cur
  model_idle=$(( ($(date +%s) - last_active) / 60 ))
  if [ "$model_idle" -ge "$IDLE_MIN" ] && [ "$(user_idle_min)" -ge "$IDLE_MIN" ]; then
    log "suspending (model idle ${model_idle} min)"
    systemctl suspend || log "systemctl suspend failed"
    last_active=$(date +%s)
  fi
done
