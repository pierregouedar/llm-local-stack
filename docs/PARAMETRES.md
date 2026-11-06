# Adapter les paramètres à ta machine

Les valeurs du dépôt sont mesurées pour **RTX 3080 10 Go + Ryzen 7 3800X + 32 Go DDR4** (voir [BENCHMARKS.md](BENCHMARKS.md)).
Sur une autre machine, la méthode reste la même ; seules quelques valeurs changent.

## Ce qui se transpose tel quel
| Réglage | Pourquoi c'est général |
|---|---|
| `--load-mode none` | dès que des experts sont sur CPU, le mmap ralentit le prefill |
| `-b / -ub 4096` | idem : de gros lots amortissent la copie des experts vers le GPU (si la VRAM le permet) |
| `-ctk / -ctv q8_0` | même vitesse que f16, moins de VRAM, qualité préservée |
| `-fa on` | flash attention |
| `-np 2` + `--checkpoint-min-step 2048` | usage agent : la session principale garde son cache |
| `--reasoning-budget` | borne la réflexion : réponses plus courtes, agent plus rapide |
| `CUDA_MODULE_LOADING=EAGER` | évite les échecs d'initialisation CUDA au démarrage |
| Formats `Q4_K_*` plutôt que `IQ4_*` | quand une partie tourne sur CPU |
| Modèles sur NVMe | chargement ×3,5 plus rapide |

## Ce qu'il faut remesurer
### 1. `--n-cpu-moe` (le plus important)
Le plus petit N qui laisse **~400-500 Mo de VRAM libre au pic**, avec tes applis habituelles ouvertes.
1. Démarre avec une valeur sûre (ex. 40 sur 10 Go ; moins sur 12-16 Go, ~0 sur 24 Go pour un 35B-A3B en Q4).
2. Mesure le **serveur réel** sur un vrai prompt de la taille de ton usage (32k, 64k) :
   ```powershell
   .\bench\bench.ps1 -Label essai-ncmoe34 -SkipBench -PromptSizes 32768 -Runs 1 -CodeDir C:\code\projet `
     -ServerArgs "-ngl 99 --n-cpu-moe 34 -c 131072 -np 2 -fa on -ctk q8_0 -ctv q8_0 -b 4096 -ub 4096 -t 6 --load-mode none"
   ```
3. Descends de 1-2 tant que la VRAM max (colonne `vram_max_mib`) reste sous `VRAM totale − 500 Mo` **et** que le prefill ne s'effondre pas (signe de débordement : prefill divisé par 3 ou plus).
4. Avec le MTP, compte ~1,3 Go de plus (≈ 3-4 couches d'experts en plus sur CPU).

### 2. `-t` (threads)
Teste `-t` = nombre de cœurs physiques, puis −1, −2. Sur un CPU limité par la RAM, moins de threads fait souvent mieux. Évite le SMT (16 threads sur 8 cœurs = −12 % ici).

### 3. `-ub`
4096 si la VRAM le permet, sinon 2048 (mesurer : 512 → 4096 = ×7 de prefill ici).

### 4. MTP
- Seulement si le modèle a une tête MTP (`nextn` dans les métadonnées GGUF ; un nom « MTP » ne suffit pas).
- `--spec-draft-n-max` 2 ou 3 ; `--spec-draft-p-min` 0.
- Cache et lot du MTP réduits pour la VRAM : `-ctkd q8_0 -ctvd q8_0 --spec-draft-n-ubatch 512`.

### 5. Contexte
- Agent « une session par tâche » : 64k par conversation suffit souvent.
- Longues sessions : `-c 262144 -np 2 --kv-unified` (contexte partagé), au prix de quelques couches d'experts en plus sur CPU.

## Si tu as plus de VRAM
Un 35B-A3B en Q4 (~20 Go) **entièrement en VRAM** (24 Go et plus) supprime le goulot RAM : la génération devrait plus que doubler (non mesuré ici). Avec 16 Go, `--n-cpu-moe` peut descendre nettement.

## Diagnostic rapide
| Symptôme | Cause | Action |
|---|---|---|
| Prefill ou génération divisés par 3+ | débordement de VRAM | `--n-cpu-moe` +1/+2, fermer les applis GPU |
| `CUDA error: shared object initialization failed` | chargement CUDA à la demande | `CUDA_MODULE_LOADING=EAGER` |
| « context type MTP requested but model doesn't contain MTP layers » | pas de tête MTP | retirer `--spec-type draft-mtp` |
| Plantages du pilote GPU (nvlddmkm) sous CUDA | OC GPU instable | retirer l'OC du cœur (les benchs 3D ne suffisent pas à le valider) |
