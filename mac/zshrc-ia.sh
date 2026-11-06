# --- IA locale : reveil du PC via le NAS (a ajouter a ~/.zshrc) ---
# pcstatus : PC allume ? pile IA lancee ?   pcwake : reveille le PC ET lance la pile si besoin   pcstop : arrete la pile
# ompw / ocw : reveille le PC puis lance omp / OpenCode avec les memes arguments
export LLAMA_PC_KEY="$(cat ~/.config/opencode/llama-key 2>/dev/null)"
PCWAKE_URL="http://NAS_HOST:8199"   # NAS_HOST = nom ou IP Tailscale du NAS (remplace par install.sh)

pcstatus() { curl -fsS --max-time 10 "$PCWAKE_URL/status"; echo; }

pcwake() {
  echo "Reveil du PC et demarrage de la pile (jusqu'a ~4 min)..."
  curl -fsS --max-time 300 "$PCWAKE_URL/wake" || { echo; echo "Echec : NAS joignable ? Tailscale actif ?"; return 1; }
  echo
}

pcstop()  { curl -fsS --max-time 30 "$PCWAKE_URL/stop"; echo; }   # arrete la pile IA (libere la VRAM), l'agent reste pret
ompw() { pcwake && omp "$@"; }
ocw()  { pcwake && opencode "$@"; }
