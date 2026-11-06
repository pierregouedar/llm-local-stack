#!/usr/bin/env bash
# Starts the agent (server/agent.py) in the background unless it is already running.
. "$(dirname "$0")/lib.sh"
secret agent-token.txt >/dev/null   # creates the token on first run
if pgrep -f "$SERVER_DIR/agent.py" >/dev/null; then echo "agent already running"; exit 0; fi
py="$(cfg python)"; case "$py" in ""|*.exe) py=python3 ;; esac
nohup "$py" -I "$SERVER_DIR/agent.py" >> "$LOGS/agent.out.log" 2>&1 < /dev/null &
echo "agent started"
