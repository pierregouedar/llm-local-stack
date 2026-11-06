# Optimisation du setup IA local — résultats

## Résumé (05/11/2026)

| Conditions réelles (llama-server, vrai code d'un vrai projet Rust) | Avant (lanceur de la mission, b12004) | **Après (`start-ia.bat`, mode A)** | Gain |
|---|---|---|---|
| Prefill 8k | 214 t/s | **2 879 t/s** | ×13 |
| **Prefill 32k** | 178 t/s | **2 835 t/s** | **×16** |
| **Prefill 64k** | — (débordement VRAM) | **2 461 t/s** (64k lus en ~27 s) | — |
| Génération 8k | 20 t/s | **44 t/s** (48 en mode B) | ×2,2 |
| Génération 32k / 64k | — | 41,6 / 39,2 t/s (45 / 44 en mode B) | — |
| Reprise du cache (même conversation) | 2048 tokens relus en 10-15 s | 20 tokens relus en 0,25 s | — |

D'où vient le gain : (1) l'ancien lanceur **débordait de la VRAM** (262k de contexte + `-ub 2048` + 28 couches d'experts sur CPU) ; (2) **llama.cpp b12128** : +51 à +67 % de prefill à 32-64k ; (3) **`-ub 4096`** ; (4) **`--load-mode none`** : +40 % ; (5) `-t 6`.
Rejetés (mesurés sans gain) : plan d'alimentation, `-tb`, `--cache-reuse`, MTP à 262k, CUDA 13.4.

**Prochaine étape recommandée** : mesurer dans tes vraies sessions si c'est le prefill ou la génération qui te limite. Hier, avec le cache en place, la génération pesait ~85 % du temps → si ça se confirme, passe en mode B (`start-ia.bat mtp`), et un futur achat de GPU devra viser la **bande passante mémoire et la VRAM** (tout le modèle en VRAM = génération ×2 ou plus), pas seulement le calcul.

## Phase 1 — État des lieux (05/11/2026, lecture seule)

### GPU
| Élément | Valeur |
|---|---|
| Carte | RTX 3080 10 Go (10240 Mio) |
| Pilote | 610.88 (CUDA UMD 13.3) |
| VRAM au repos | **1506 Mio** utilisés sans aucun modèle chargé |
| Température repos | 47 °C |
| Limite de puissance | 370 W (= valeur par défaut) |
| Horloges max | cœur 2115 MHz, mémoire 9501 MHz (valeurs nominales affichées ; l'OC Afterburner n'apparaît pas ici) |

### VRAM au repos par processus (compteurs Windows « GPU Process Memory »)
| Processus | VRAM |
|---|---|
| dwm (bureau Windows, 2 écrans) | 1235 Mio |
| firefox | 509 Mio |
| chrome | 239 Mio |
| Discord | 126 Mio |
| Spotify | 70 Mio |
| autre app Electron | 68 Mio |
| NVIDIA Overlay | 46 Mio |

Navigateurs + Discord + Spotify + overlay ≈ **1 Go récupérable** pendant les sessions IA. Le dwm (bureau) ne l'est pas.

### llama.cpp
| Élément | Valeur |
|---|---|
| Version | build **12004**, commit `3c809f443`, binaire officiel Windows **CUDA 12.4** (Clang 20) |
| Chemin | `<llama.cpp b12004>\` |
| Backend CPU | sélection dynamique (`ggml-cpu-*.dll`, Zen 2 → variante haswell/AVX2) |

### Modèles présents
| Fichier | Taille |
|---|---|
| `<modeles NVMe>\Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf` (NVMe) | 21,28 Go |
| `<modeles SATA>\Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf` (SATA, copie) | 21,28 Go |
| `<modeles SATA>\Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_S.gguf` | 20,43 Go |
| `<modeles SATA>\Qwen3.6-35B-A3B-UD-IQ4_XS.gguf` | 17,73 Go |
| `<modeles SATA>\TwIL-8B-Q4_K_M-balanced.gguf` | 5,35 Go |

⚠️ **`D:\models\Tiel-Coder-35B-A3B-UD-Q4_K_S.gguf` (cité dans la mission) n'existe pas.** Le modèle installé est **Cyber-Tiel** (variante « abliterated » de Tiel-Coder, avec tête MTP), le même Ornith 1.5 de base.

### Système
| Élément | Valeur |
|---|---|
| Plan d'alimentation | AMD Ryzen™ Balanced |
| HAGS | clé `HwSchMode` absente → réglage par défaut de Windows (non déterminable sans ouvrir les Paramètres) |
| Démarrage rapide | activé (`HiberbootEnabled=1`) |
| Wake-on-LAN | carte Realtek Gaming GbE déjà autorisée à réveiller le PC (`wake_armed`) |
| Exclusions Defender | illisibles sans droits administrateur |

### Pile IA actuelle (mise en place le 05/11)
- **llama-swap v270** (`<llama-swap>\`) devant llama-server, config `<pile>\llama-swap.yaml` : Cyber-Tiel en `-ncmoe 31 -c 131072 -np 2 -t 6 -ub 1024 -lm none -ctk/-ctv q8_0 --spec-type draft-mtp --reasoning-budget 4000 --checkpoint-min-step 2048`, écoute sur l'IP Tailscale `<IP Tailscale PC>:8080` avec clé d'API.
- **OpenCode v1.19.5** en serveur (`opencode serve`) sur `<IP Tailscale PC>:4096`, lancé à la main par `<pile>\start-ai.ps1` (pas de service ni de tâche planifiée). Config : `~\.config\opencode\` (`opencode.json`, `AGENTS.md`, `llama-key`).
- **État au moment du relevé : aucun processus llama-swap / llama-server / opencode actif** (arrêtés, pas de redémarrage du PC depuis le 04/11 21:03).
- Le lanceur `.bat` décrit dans la mission (`-c 262144 -t 8 -ub 2048 --cache-reuse 256`, 127.0.0.1) **n'existe pas sur le disque** ; les lanceurs présents sont `lancer-cybertiel.bat` / `lancer-heretic.bat` (Bureau et `<ancien dossier>`).
- **omp v18.14.0** déjà téléchargé (`<pile>\bin\omp-v18.14.0\omp.exe`, 30/10), non installé dans le PATH. `~/.omp` ne contient que `logs`, `natives`, `run`.

## Phase 2 — Référence (paramètres du lanceur de la mission, llama.cpp b12004 CUDA 12.4)

Modèle : `<modeles NVMe>\Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf` (le Tiel-Coder de la mission n'existe pas sur le disque).
Paramètres : `-ngl 99 --n-cpu-moe 28 --jinja -c 262144 -fa on -ctk q8_0 -ctv q8_0 -t 8 -b 2048 -ub 2048 -np 1 --cache-reuse 256` (pas de MTP dans ce lanceur).
Banc : `bench\bench.ps1`. Médianes ; llama-bench `-r 3`, serveur 2 passes.

| Test | Contexte | Prefill (t/s) | Génération (t/s) | Pic VRAM |
|---|---|---|---|---|
| llama-bench | 0 | 813 | 50,9 | 9944 Mio |
| llama-bench | 16k | 928 | 51,5 | 9944 Mio |
| llama-bench | 32k | 891 | 49,3 | 9944 Mio |
| llama-bench | 64k | 814 | 43,9 | 9944 Mio |
| **llama-server, vrai code** | **8k** | **214** | **20,1** | 9927 Mio |
| **llama-server, vrai code** | **32k** | **178** | — (réponse vide) | 9927 Mio |

**Constat** : en conditions réelles, ce lanceur **déborde de la VRAM** (262k de contexte réservé + `-ub 2048` + seulement 28 couches d'experts sur CPU). Le pilote bascule sur la RAM système : le prefill s'effondre à ~200 t/s (4 à 9× moins que llama-bench, qui ne réserve que le contexte du test) et la génération à ~20 t/s.
Réutilisation du cache : la 2e requête qui reprend le même début relit encore **2048 tokens** (10-15 s) au lieu de ~0.

## Phase 3 — llama.cpp à jour (b12128, 05/11/2026)

Téléchargé avec ton accord, empreintes SHA256 vérifiées, installé à part : `<llama.cpp>\b12128-cuda12.4\` et `<llama.cpp>\b12128-cuda13.4\`. Mêmes paramètres que la référence.

| Prefill llama-bench (t/s) | b12004 | b12128 CUDA 12.4 | b12128 CUDA 13.4 |
|---|---|---|---|
| 0 | 813 | 777 | 1366 |
| 16k | 928 | **1554** | 1444 |
| 32k | 891 | **1485 (+67 %)** | 1456 |
| 64k | 814 | **1230 (+51 %)** | 1211 |

| Génération llama-bench (t/s) | b12004 | b12128 12.4 | b12128 13.4 |
|---|---|---|---|
| 0 / 16k / 32k / 64k | 50,9 / 51,5 / 49,3 / 43,9 | 51,1 / 49,2 / 47,7 / 43,7 | 51,3 / 49,3 / 47,6 / 43,0 |

Serveur réel (toujours en débordement VRAM avec ces paramètres) : prefill 8k 229-237 t/s, 32k 190-193 t/s ; génération 8k ~20 t/s.

Vérification de la sortie : b12128 CUDA 12.4 écrit une fonction `median()` correcte (4 tests sur 4).

**Retenu : b12128 CUDA 12.4** (prefill +51 à +67 % à 32-64k, génération inchangée ; CUDA 13.4 équivalent, légèrement en dessous à 16-64k).

## Phase 4 — Balayage des paramètres (b12128 CUDA 12.4, mesures serveur sur vrai code, 1 passe)

Une variable à la fois. « Déborde » = la VRAM atteint ~9,9-10 Go et le pilote bascule sur la RAM système (prefill qui s'effondre).

### `--n-cpu-moe` × `-c` × `-ub` (prefill 32k)
| -c | --n-cpu-moe | -ub | VRAM max | Prefill 32k | Génération |
|---|---|---|---|---|---|
| 262k | 30 | 2048 | 10001 ❌ | 214 | 45,3 |
| 262k | 32 | 2048 | 9930 ⚠️ | 756 | 43,2 |
| 262k | 34 | 2048 | 9914 | 1154 | 42,2 |
| 262k | 35 | 2048 | 9537 | 1128 | 41,9 |
| 262k | 34 | 1024 | 9469 | 682 | 41,2 |
| 262k | 36 | 4096 | 9935 ⚠️ | 1040 | 39,4 |
| 262k | **38** | **4096** | 9533 | **1634** | 38,9 |
| 262k | 40 | 4096 | 8540 | 1588 | 37,2 |
| 131k | 30 | 512 | 9090 | 429 | 44,4 |
| 131k | 30 | 1024 | 9242 | 755 | — |
| 131k | 30 | 2048 | 9616 | 1293 | 45,2 |
| 131k | 30 | 4096 | 9932 ⚠️ | 1121 | 44,6 |
| 131k | **32** | **4096** | 9600 | **1777** | 42,6 |
| 131k | 33 | 4096 | 9142 | 1755 | — |

→ Avec des experts sur le CPU, **un grand `-ub` (4096) accélère fortement le prefill** (les poids des experts sont copiés une fois par lot). Retenu : `-ub 4096`, puis le plus petit `--n-cpu-moe` qui laisse ~500-700 Mo de marge.

### Threads (base 262k / 38 / 4096)
| Réglage | Prefill 32k | Génération |
|---|---|---|
| -t 8 | 1629 | 38,7 |
| **-t 6** | 1604 | **39,5** |
| -t 7 | 1605 | 39,3 |
| -t 16 | 1629 | 34,7 |
| -t 6 -tb 8 | 1610 | 39,5 |
| -t 6 -tb 16 | 1570 | 38,9 |
→ Retenu **-t 6** (génération limitée par la bande passante RAM) ; `-tb` sans effet → non retenu.

### MTP (`--spec-type draft-mtp`)
- À 262k (`--n-cpu-moe` 38-41) : **déborde dans tous les cas**, même avec cache du MTP en q8 (`-ctkd/-ctvd q8_0`) et `--spec-draft-n-ubatch 512` → **rejeté à 262k**.
- À 131k, `--n-cpu-moe 34` : encore à la limite (9,94-9,99 Go).
- À 131k, `--n-cpu-moe 36` (9,2 Go) : MTP 2 = génération **46,1 t/s** à 8k et 32k (vs 44,5 / 42,7 sans MTP à `--n-cpu-moe 32`), prefill un peu plus bas. Acceptation 65-72 %. MTP 1 : 46,3 / 41,9.
- Le MTP coûte ~1,3 Go de VRAM de plus que sans MTP à réglage égal.

### `--cache-reuse` et chargement (base 131k / 32 / 4096)
| Réglage | Prefill 8k | Prefill 32k | Génération 8k / 32k | Chargement |
|---|---|---|---|---|
| --cache-reuse 0 | 1356 | 2086 | 44,5 / 42,7 | 6 s |
| --cache-reuse 256 | 1311 | 2035 | 46,0 / 41,7 | 6 s |
| --cache-reuse 512 | 1181 | 2027 | 44,6 / 42,5 | 6 s |
| --load-mode mmap | 1251 | 1973 | 45,7 / 42,8 | 8 s |
| **--load-mode none** | **2850** | **2837** | 44,4 / 42,2 | 16 s |
→ **`--load-mode none` : +40 % de prefill à 32k** (llama.cpp le conseille lui-même quand des experts sont sur le CPU). `--cache-reuse` sans effet sur ce modèle hybride (la reprise passe par des points de reprise tous les `-ub` tokens) → retiré.

### Rejeté / non testé
- **KV cache f16** : non testé, il prendrait de la VRAM et forcerait à remonter `--n-cpu-moe` (règle de la mission).
- **`--mlock`** : remplacé par `--load-mode` dans cette version ; `mlock` non testé (verrouille ~20 Go de RAM, risqué avec 32 Go).
- **`--spec-draft-p-min`** : non balayé, le MTP n'étant rentable qu'à 131k avec marge ; à faire si le finaliste B est retenu.

## Phase 4 — Finalistes (b12128 CUDA 12.4, `--load-mode none`, `-ub 4096`, `-t 6`, médiane de 2 passes, vrai code)

| Config | Prefill 8k | **Prefill 32k** | **Prefill 64k** | Gén. 8k | Gén. 32k | Gén. 64k | VRAM max | Chargement |
|---|---|---|---|---|---|---|---|---|
| Référence (lanceur mission, b12004) | 214 | 178 | — | 20,1 | — | — | 9927 | — |
| **A — 131k, --n-cpu-moe 32** | **2879** | **2835** | **2461** | 44,1 | 41,6 | 39,2 | 9665 | 17 s |
| B — 131k, --n-cpu-moe 36, MTP 2 | 2243 | 2292 | 2029 | **47,6** | **44,9** | **43,7** | 9240 | 18 s |
| C — 262k, --n-cpu-moe 38 | 2265 | 2388 | 2119 | 41,3 | 38,3 | 35,7 | 9669 | 18 s |

llama-bench (prefill 2048 / génération 128, médiane de 3) :
| Config | pp 0 / 16k / 32k / 64k | tg 0 / 16k / 32k / 64k |
|---|---|---|
| Référence | 813 / 928 / 891 / 814 | 50,9 / 51,5 / 49,3 / 43,9 |
| A | 2473 / 2188 / 1999 / 1681 | 48,4 / 46,0 / 44,5 / 40,6 |
| B (sans MTP dans llama-bench) | 1975 / 1852 / 1654 / 1510 | 44,7 / 43,0 / 41,2 / 38,5 |
| C | 1968 / 1779 / 1684 / 1466 | 43,0 / 41,6 / 39,8 / 36,9 |

**Retenu : A** (priorité de la mission = prefill à 32k/64k) → `<dossier IA>\start-ia.bat` (mode `prefill` par défaut). **B** disponible (`start-ia.bat mtp`) : meilleur choix si la génération compte plus (dans les sessions OpenCode réelles du 05/11, la génération représentait ~85 % du temps une fois le cache en place). **C** rejeté : 262k de contexte rarement utiles avec « une session par tâche », génération la plus lente.

Gains A vs référence (conditions réelles) : **prefill ×13 à 8k, ×16 à 32k** ; génération ×2,2 à 8k. Lire 64k tokens de contexte : ~27 s.

Cache entre deux requêtes successives (format chat, même début) : vérifié sur `start-ia` — 2e requête de 4106 tokens : **20 tokens relus en 0,25 s**. Avec un début identique mais une fin différente, le modèle hybride reprend au dernier point de reprise : jusqu'à `-ub` (4096) tokens relus, 1,4-2,5 s.

Point d'attention : b12128 a échoué 3 fois sur ~40 démarrages avec `CUDA error: shared object initialization failed` (juste après l'arrêt d'un autre serveur). Aucune erreur du pilote ; le 2e essai passe. `start-ia.ps1` réessaie automatiquement (3 essais).

## Report dans llama-swap (accès Tailscale depuis le Mac) — 05/11 au soir

Réglages A et B reportés dans `llama-swap.yaml` (2 emplacements `-np 2` gardés pour OpenCode). Mesures via llama-swap sur Tailscale (vrai code, 30k tokens) :
| Modèle | Prefill 30k | Génération | 2e requête | VRAM |
|---|---|---|---|---|
| `cybertiel` (A) | 2696-2739 t/s | 42-43 t/s | 20 tokens relus en 0,27 s | 9,8 Go |
| `heretic` (MTP, `-ncmoe 34`, 13k tokens) | 2200 t/s | 47 t/s | — | 9,3 Go |

**Échecs de démarrage « CUDA error: shared object initialization failed » : cause trouvée.** Ils touchaient surtout les configs avec MTP (`heretic` 3/3, `cybertiel-mtp` 2/3 en changeant de modèle), **y compris avec l'ancienne b12004** (4/4 échecs) → pas un bug de b12128, ni un manque de VRAM (échoue aussi avec 3 Go libres). Le pilote charge le code des fonctions CUDA à la demande, et ce chargement échoue au moment où llama.cpp interroge les fonctions du contexte MTP. `GGML_CUDA_PDL=0` : sans effet. **`CUDA_MODULE_LOADING=EAGER` : 4/4 démarrages OK en direct, 7/7 changements de modèle OK via llama-swap**, même vitesse, ~+400 Mo de VRAM, chargement ~19-22 s. Appliqué dans `llama-swap.yaml` et `start-ia.ps1`.

## Compléments du 05/11 au soir (2 passes, médianes, config de production : `-np 2`, `CUDA_MODULE_LOADING=EAGER`)

### 262k de contexte (écart corrigé : la mission prévoyait 262 144)
`-c 262144 -np 2 --kv-unified --n-cpu-moe 38` (cache partagé : une conversation peut monter à ~250k) :
| Contexte | Prefill | Génération | VRAM max |
|---|---|---|---|
| 32k | 2440 | 40,0 | 9813 Mio |
| 64k | 2178 | 36,4 | 9813 Mio |
| 128k | 1879 | 31,7 | 9813 Mio |
Marge ~430 Mio (comme `cybertiel`) → `--n-cpu-moe` 39/40 non testés. Ajouté à llama-swap : **`cybertiel-262k`**. Test via llama-swap : conversation de 97 072 tokens OK (1982 t/s, 34,7 t/s), requête annexe sur l'autre emplacement sans perte de cache (20 tokens relus en 0,31 s).

### Seuil du MTP (`--spec-draft-p-min`, config `cybertiel-mtp`)
| p-min | Gén. 8k / 32k | Acceptation | Prefill 8k / 32k |
|---|---|---|---|
| **0 (retenu)** | **50,7 / 50,0** | 67-71 % | 2414 / 2381 |
| 0,4 | 48,7 / 47,0 | 77 % | 2424 / 2414 |
| 0,6 | 45,8 / 44,3 | 82-87 % | 2425 / 2425 |
| 0,8 | 42,6 / 43,0 | 93 % | 2402 / 2411 |
→ Un seuil plus haut accepte mieux mais propose moins : plus lent. 0,5 et 0,7 non testés (tendance nette).

### Contre-vérification (config `cybertiel` de production)
| Variante | Prefill 8k / 32k | Gén. 8k / 32k | VRAM |
|---|---|---|---|
| **Base : `-ub 4096`, `--load-mode none`, `-t 6`** | **3015 / 2949** | 49,0 / 46,6 | 9363 |
| `-ub 2048` | 2125 / 2085 (−30 %) | 49,8 / 46,7 | 8751 |
| `--load-mode mmap` | 1336 / 2174 (−56 % / −26 %) | 48,5 / 46,2 | 9363 |
→ Les deux choix sont confirmés en 2 passes. `-t 8` non refait (écarté nettement en 1 passe : −2 %).

### Bilan des modèles en production (llama-swap)
| Modèle | Prefill 32k | Génération 32k | Contexte / conversation | Usage |
|---|---|---|---|---|
| `cybertiel` | ~2950 | ~47 | 64k | contexte lu le plus vite |
| `cybertiel-mtp` | ~2380 | **~50** | 64k | **dev courant** |
| `cybertiel-262k` | ~2440 | ~40 | **~250k** | longues sessions |
| `heretic` | ~2200 (13k) | ~47 | 64k | général |

## Phase 5 — Windows

### Plan d'alimentation (config A, 2 passes, plan restauré ensuite)
| Plan | Prefill 8k | Prefill 32k | Gén. 8k | Gén. 32k |
|---|---|---|---|---|
| AMD Ryzen Balanced (actuel) | 2846 | 2829 | 44,6 | 42,7 |
| AMD Ryzen High Performance | 2850 | 2822 | 44,3 | 41,5 |
| Performances optimales | 2845 | 2840 | 45,4 | 42,7 |
→ **Aucun gain mesurable** (< 2 %, dans le bruit) → **rejeté**, `start-ia` / `stop-ia` ne touchent pas au plan.

### VRAM des applications (non modifié — à valider par toi)
Au repos avec tes applis ouvertes : ~1,5 Go utilisés (dwm 1,2 Go, Firefox 0,5 Go, Chrome 0,24 Go, Discord 0,13 Go, Spotify 0,07 Go, overlay NVIDIA 0,05 Go). Fermer navigateurs + Discord + Spotify + overlay pendant une session libère ~1 Go, assez pour passer `--n-cpu-moe` de 32 à ~30 (non mesuré). Liste des applis à fermer : voir `A-DECIDER.md`.

### HAGS, Defender
Non testés (redémarrage / droits administrateur) : voir `A-DECIDER.md`.

## Phase 6 — ik_llama.cpp
Aucun binaire Windows officiel (seule release : `t0002`, juillet 2025, sans fichier ; dépôt actif). Il faudrait le compiler (Visual Studio Build Tools + CUDA Toolkit, plusieurs Go) → **non fait, à décider**. Un dépôt tiers proposant des binaires (8 étoiles, origine non vérifiable) a été écarté.

### Outils
| Outil | Version |
|---|---|
| git | 2.56.0 |
| Python | 3.13.7 |
| Rust | cargo / rustc 1.99.1 (`%USERPROFILE%\.cargo\bin`, hors PATH) |
| Node.js / npm / bun | absents |
