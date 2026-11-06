# --- Local LLM: wake the GPU server through the waker (appended to ~/.zshrc or ~/.bashrc) ---
# pcstatus : server awake? stack running?    pcwake : wake the server AND start the stack if needed
# pcstop   : stop the stack (frees the VRAM; the agent stays ready)
# ompw / ocw : pcwake, then omp / OpenCode with the same arguments
export LLAMA_PC_KEY="$(cat ~/.config/opencode/llama-key 2>/dev/null)"
PCWAKE_URL="http://NAS_HOST:8199"   # waker address, written by install.sh

pcstatus() { curl -fsS --max-time 10 "$PCWAKE_URL/status"; echo; }

pcwake() {
  echo "Waking the server and starting the stack (up to ~4 min)..."
  curl -fsS --max-time 300 "$PCWAKE_URL/wake" || { echo; echo "Failed: is the waker reachable? Is Tailscale up?"; return 1; }
  echo
}

pcstop() { curl -fsS --max-time 30 "$PCWAKE_URL/stop"; echo; }
ompw()   { pcwake && omp "$@"; }
ocw()    { pcwake && opencode "$@"; }
