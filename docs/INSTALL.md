# Installation

Trois machines reliées par **Tailscale** : le **PC** (GPU, fait tourner le modèle), le **NAS** (toujours allumé, réveille le PC) et le **poste client** (Mac ou Linux, avec omp / OpenCode). Le NAS est optionnel : sans lui, tout marche tant que le PC est allumé.

## 1. PC (Windows)

### Logiciels
| Élément | Où le trouver |
|---|---|
| llama.cpp (release Windows CUDA, ex. `llama-bXXXXX-bin-win-cuda-12.4-x64.zip` + `cudart-llama-bin-win-cuda-12.4-x64.zip`, extraits dans le même dossier) | https://github.com/ggml-org/llama.cpp/releases |
| llama-swap (`llama-swap_<version>_windows_amd64.zip`) | https://github.com/mostlygeek/llama-swap/releases |
| Modèle(s) GGUF, sur un NVMe de préférence | ex. https://huggingface.co/peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP (`UD-Q4_K_S`) |
| Python 3 (pour l'agent) | https://www.python.org |
| Tailscale | https://tailscale.com |
| OpenCode (optionnel : projets sur le PC pilotés à distance) | https://opencode.ai |

### Configuration
1. Cloner ce dépôt sur le PC.
2. Copier `pc\stack.example.json` en **`pc\stack.json`** et renseigner les chemins (`llama_server`, `llama_swap`, `models_dir`, `pythonw`, éventuellement `opencode`).
3. Si tes fichiers de modèle ont d'autres noms, adapter `pc\llama-swap\llama-swap.template.yaml` (et `--n-cpu-moe` selon ta VRAM : [PARAMETRES.md](PARAMETRES.md)).
4. Double-cliquer **`pc\Demarrer IA.bat`**. Au premier lancement, les secrets sont créés dans `pc\secrets\` :
   - `llama-api-key.txt` : clé d'API de llama-swap (à copier sur le poste client) ;
   - `agent-token.txt` : jeton de l'agent (à mettre dans le `.env` du NAS) ;
   - `opencode-password.txt` : seulement si `opencode` est configuré.
5. Vérifier : `curl http://<ip-tailscale-du-pc>:8080/v1/models -H "Authorization: Bearer <clé>"`.

`pc\Arreter IA.bat` arrête la pile (l'agent reste prêt). Après un **redémarrage** du PC, relancer `Demarrer IA.bat` (pas de démarrage automatique, par choix).

### Wake-on-LAN (pour le réveil par le NAS)
- Gestionnaire de périphériques → carte réseau → **Gestion de l'alimentation** : « Autoriser ce périphérique à sortir l'ordinateur du mode veille » + « Paquet magique uniquement » ; onglet **Avancé** : « Wake on Magic Packet » activé.
- Le réveil marche depuis la **veille**. Depuis un PC éteint : BIOS (ErP désactivé, réveil PCI-E) et démarrage rapide de Windows désactivé.

## 2. NAS (Docker, optionnel)
```bash
mkdir -p /opt/pc-wake && cd /opt/pc-wake
# copier nas/pc-wake/docker-compose.yml et nas/pc-wake/.env.example ici
cp .env.example .env && nano .env      # PC_MAC, BROADCAST, PC_IP, AGENT_TOKEN
chmod 600 .env
docker compose up -d
curl http://localhost:8199/status       # {"pc_up": true, "stack_up": true}
```
`network_mode: host` est indispensable (le paquet de réveil doit sortir sur le réseau local). Le NAS doit être dans le même tailnet que le PC.

## 3. Poste client (Mac / Linux)
Copier `pc\secrets\llama-api-key.txt` du PC sur le Mac (ex. `~/llama-key.txt`), puis :
```bash
cd mac && ./install.sh <nom-tailscale-du-pc> <nom-tailscale-du-nas> ~/llama-key.txt
```
Le script **n'écrase rien** : s'il trouve une config existante (`~/.omp/agent/models.yml`, `~/.config/opencode/opencode.json`, `~/.zshrc`…), il la laisse et t'indique quoi fusionner.

Vérifier dans un nouveau terminal :
```bash
pcstatus
omp -p --no-session "Reply with exactly: OK"
opencode models pc
```

## Utilisation
| Commande (client) | Effet |
|---|---|
| `pcstatus` | PC joignable ? pile IA lancée ? |
| `pcwake` | réveille le PC et démarre la pile si besoin |
| `pcstop` | arrête la pile (libère la VRAM) |
| `ompw …` / `ocw …` | `pcwake` puis omp / OpenCode |
| `omp --model pc/cybertiel-mtp` | dev courant (génération la plus rapide) |
| `omp --model pc/cybertiel-262k` | longues sessions |

## Désinstaller
- PC : `Arreter IA.bat`, arrêter le processus `pythonw … ia-agent.py`, supprimer le dossier du dépôt.
- NAS : `docker compose down` dans son dossier.
- Client : retirer `~/.omp/agent/{models,config}.yml`, l'entrée `pc` d'OpenCode et le bloc ajouté à `~/.zshrc` (une sauvegarde `.zshrc.bak-<date>` a été faite).
