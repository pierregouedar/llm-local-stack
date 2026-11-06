#!/usr/bin/env bash
# Stops the stack (llama-swap, llama-server, opencode serve, idle-sleep watchdog) and frees the VRAM.
# The agent keeps running, so the waker can start the stack again on the next "pcwake".
. "$(dirname "$0")/lib.sh"
stop_stack
log "stack stopped"
sleep 2
command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=memory.used --format=csv,noheader | sed 's/^/VRAM in use: /'
exit 0
