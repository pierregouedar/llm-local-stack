#!/usr/bin/env bash
# Client setup (macOS or Linux): omp + OpenCode pointed at the LLM server over Tailscale,
# plus the pcstatus / pcwake / pcstop / ompw / ocw shell commands.
# NEVER OVERWRITES ANYTHING: an existing file is left untouched (a message says what to merge).
#
# Usage:  ./install.sh <SERVER_HOST> <WAKER_HOST> <key-file>
#   SERVER_HOST : Tailscale name or IP of the GPU server   (e.g. my-pc or 100.x.y.z)
#   WAKER_HOST  : Tailscale name or IP of the waker box     (e.g. my-nas; use "-" if you have none)
#   key-file    : copy of server/secrets/llama-api-key.txt from the server
set -euo pipefail

PC_HOST="${1:?SERVER_HOST missing}"; NAS_HOST="${2:?WAKER_HOST missing}"; KEY_FILE="${3:?key file missing}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OC="$HOME/.config/opencode"; OMP="$HOME/.omp/agent"
mkdir -p "$OC" "$OMP"

install_file() {  # $1 = source, $2 = destination
  if [ -e "$2" ]; then
    echo "  already exists, NOT modified: $2  -> merge by hand from $1"
  else
    sed -e "s/PC_HOST/$PC_HOST/g" -e "s/NAS_HOST/$NAS_HOST/g" "$1" > "$2"
    echo "  installed: $2"
  fi
}

echo "1) API key"
if [ -e "$OC/llama-key" ]; then echo "  already exists: $OC/llama-key"; else cp "$KEY_FILE" "$OC/llama-key"; chmod 600 "$OC/llama-key"; echo "  installed: $OC/llama-key"; fi

echo "2) OpenCode"
install_file "$HERE/opencode/opencode.json" "$OC/opencode.json"
install_file "$HERE/AGENTS.md" "$OC/AGENTS.md"

echo "3) omp"
install_file "$HERE/omp/models.yml" "$OMP/models.yml"
install_file "$HERE/omp/config.yml" "$OMP/config.yml"
install_file "$HERE/AGENTS.md" "$OMP/AGENTS.md"

case "${SHELL:-}" in *bash) RC="$HOME/.bashrc" ;; *) RC="$HOME/.zshrc" ;; esac
echo "4) Shell commands ($RC)"
if grep -q 'PCWAKE_URL=' "$RC" 2>/dev/null; then
  echo "  already in $RC, NOT modified -> compare with $HERE/shell.sh"
else
  cp "$RC" "$RC.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  sed -e "s/NAS_HOST/$NAS_HOST/g" "$HERE/shell.sh" >> "$RC"
  echo "  appended to $RC (backup made)"
fi

echo
echo "Done. Open a new terminal, then:"
[ "$NAS_HOST" != "-" ] && echo "  pcstatus                                   # {\"pc_up\": ..., \"stack_up\": ...}"
echo "  omp -p --no-session \"Reply with exactly: OK\""
echo "  opencode models pc"
