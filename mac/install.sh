#!/usr/bin/env bash
# Installation cote Mac (ou Linux) : omp + OpenCode branches sur le LLM du PC via Tailscale,
# et commandes pcstatus / pcwake / pcstop / ompw / ocw.
# N'ECRASE RIEN : un fichier deja present est laisse tel quel (un message indique quoi fusionner).
#
# Usage :  ./install.sh <PC_HOST> <NAS_HOST> <fichier-cle>
#   PC_HOST    : nom ou IP Tailscale du PC     (ex. mon-pc ou 100.x.y.z)
#   NAS_HOST   : nom ou IP Tailscale du NAS    (ex. mon-nas)
#   fichier-cle: copie de pc/secrets/llama-api-key.txt du PC
set -euo pipefail

PC_HOST="${1:?PC_HOST manquant}"; NAS_HOST="${2:?NAS_HOST manquant}"; KEY_FILE="${3:?fichier-cle manquant}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OC="$HOME/.config/opencode"; OMP="$HOME/.omp/agent"
mkdir -p "$OC" "$OMP"

install_file() {  # $1 = source, $2 = destination
  if [ -e "$2" ]; then
    echo "  deja present, NON modifie : $2  -> fusionne a la main depuis $1"
  else
    sed -e "s/PC_HOST/$PC_HOST/g" -e "s/NAS_HOST/$NAS_HOST/g" "$1" > "$2"
    echo "  installe : $2"
  fi
}

echo "1) Cle du modele"
if [ -e "$OC/llama-key" ]; then echo "  deja presente : $OC/llama-key"; else cp "$KEY_FILE" "$OC/llama-key"; chmod 600 "$OC/llama-key"; echo "  installee : $OC/llama-key"; fi

echo "2) OpenCode"
install_file "$HERE/opencode/opencode.json" "$OC/opencode.json"
install_file "$HERE/AGENTS.md" "$OC/AGENTS.md"

echo "3) omp"
install_file "$HERE/omp/models.yml" "$OMP/models.yml"
install_file "$HERE/omp/config.yml" "$OMP/config.yml"
install_file "$HERE/AGENTS.md" "$OMP/AGENTS.md"

echo "4) Commandes du shell (~/.zshrc)"
if grep -q 'PCWAKE_URL=' "$HOME/.zshrc" 2>/dev/null; then
  echo "  deja present dans ~/.zshrc, NON modifie -> compare avec $HERE/zshrc-ia.sh"
else
  cp "$HOME/.zshrc" "$HOME/.zshrc.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  sed -e "s/NAS_HOST/$NAS_HOST/g" "$HERE/zshrc-ia.sh" >> "$HOME/.zshrc"
  echo "  ajoute a ~/.zshrc (sauvegarde faite)"
fi

echo
echo "Termine. Ouvre un nouveau terminal, puis :"
echo "  pcstatus                                   # {\"pc_up\": ..., \"stack_up\": ...}"
echo "  omp -p --no-session \"Reply with exactly: OK\""
echo "  opencode models pc"
