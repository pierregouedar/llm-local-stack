# Mon cas d'usage

## Le besoin
- **Un agent de code** (omp, OpenCode) pour mes projets perso : JS/TS, Rust, Python.
- **Utilisable à distance**, depuis mon Mac au travail, comme un assistant cloud, mais **sur mon propre matériel** : pas de quota, code qui reste chez moi.
- Le PC ne doit pas tourner H24 : **réveil à la demande**, mise en veille quand il ne sert pas.

## Les contraintes
- **Windows obligatoire** sur le PC (jeux avec anti-cheat noyau, Game Pass) : pas de Linux, **pas de WSL**.
- **Rien à acheter** : on optimise le matériel existant.
- **Pas de tâche planifiée ni de service Windows** : je veux garder la main sur ce qui tourne.
- La qualité passe avant la vitesse : pas de compression sous Q4, pas de cache KV sous q8, échantillonnage recommandé par l'éditeur.

## Le matériel
| Machine | Rôle | Détail |
|---|---|---|
| PC | calcul | RTX 3080 **10 Go**, Ryzen 7 3800X (Zen 2, 8 c/16 t), 32 Go DDR4-3600 dual channel, NVMe Gen3 1 To + SSD SATA 1 To, 2 écrans |
| NAS | réveil, toujours allumé | mini-PC Linux + Docker (CasaOS), Tailscale |
| Mac | poste de travail | omp, OpenCode, Tailscale |

**Le vrai défi** : faire tourner un modèle de code sérieux (35B) avec **10 Go de VRAM**.

## Le parcours (résumé)
1. **Départ** : Qwen3.6-35B-A3B en IQ4_XS, réglages automatiques : ~32-37 t/s.
2. **Choix du modèle** : un dense 27B plus « malin » sur le papier tombe à **3,5 t/s** (il ne tient pas en VRAM) ; un 8B tout en VRAM fait 90 t/s mais produit du code cassé sur un vrai projet. Un **MoE 35B-A3B** (3B actifs) avec tête **MTP** est le bon compromis → Qwen3.6 heretic, puis **Cyber-Tiel Coder** (Ornith 1.5, orienté code et agent).
3. **Format** : Q4_K au lieu d'IQ4 : +40 % de génération.
4. **Réglages manuels** (`--n-cpu-moe`, `-t 6`, `--load-mode none`) : ~63 t/s en génération avec MTP sur l'ancienne version de llama.cpp.
5. **Overclocking** : RAM, VRAM, GPU… aucun gain mesurable pour le LLM, et l'OC du cœur faisait planter le pilote en CUDA. Abandonné pour l'IA.
6. **Accès distant** : llama-swap (plusieurs modèles derrière une adresse, clé d'API) exposé **uniquement sur Tailscale** ; omp et OpenCode sur le Mac pointent dessus.
7. **Usage agent réel** : l'analyse des journaux a montré que l'agent passait 19 % de son temps à **relire** des prompts (requêtes annexes qui écrasaient le cache) → 2 emplacements, points de reprise, réflexion bornée : **−36 % de temps par requête**.
8. **Qualité** : un vrai projet piloté en agent a révélé que le modèle **inventait** les données qui lui manquaient (et des tests qui validaient ses inventions) → règles `AGENTS.md` explicites, vérifiées sur un test piège.
9. **Optimisation systématique** (une variable à la fois, mesures répétées) : le lanceur de départ **débordait de la VRAM** ; nouvelle version de llama.cpp, gros lots, pas de mmap → **prefill ×16** (178 → 2 949 t/s à 32k).
10. **Contexte** : variante **262k** pour les longues sessions (sans MTP, qui ne tient pas avec).
11. **Réveil à distance** : le NAS envoie un Wake-on-LAN, puis demande à un petit **agent** sur le PC de démarrer la pile si besoin. Mise en veille automatique après 30 min d'inactivité.

Détail chiffré de chaque étape : [BENCHMARKS.md](BENCHMARKS.md).

## Les choix et leurs compromis
| Choix | Gain | Ce qu'on accepte |
|---|---|---|
| MoE 35B-A3B plutôt que dense | utilisable (50 t/s) avec 10 Go | une partie sur CPU, génération bornée par la RAM |
| Experts sur CPU (`--n-cpu-moe`) | le modèle tient | réglage fin à refaire si la VRAM libre change |
| `-ub 4096` + `--load-mode none` | prefill ×2-3 | chargement 16-20 s |
| MTP | +5 à 20 % de génération | ~1,3 Go de VRAM, incompatible avec 262k |
| 262k de contexte | moins de compactions | génération ~40 → 32 t/s quand la conversation grossit |
| Réflexion bornée (4 000) | −36 % de temps par requête | un peu moins de réflexion sur les problèmes durs (non mesuré) |
| Version « abliterated » (Cyber-Tiel) | pas de refus | plus de risque d'assurance quand il invente → règles `AGENTS.md` |
| Pas de tâche ni de service | rien d'automatique « caché » sous Windows | après un redémarrage, cliquer sur `Demarrer IA.bat` |

## Ce que j'en retiens
- **Mesurer en conditions réelles** (serveur + vrai code) : llama-bench seul ne voit pas les débordements de VRAM, qui ont été la cause n°1 de lenteur.
- **Une fois les débordements évités, la nouvelle version de llama.cpp et deux options (`-ub`, `--load-mode`) font l'essentiel.** Le reste (threads, plan d'alimentation, OC) est marginal.
- **Pour un agent, la génération domine** (~85 % du temps) une fois le cache bien géré.
- **Un modèle local de cette taille code proprement mais a besoin d'un cadre** : vraies données, étapes vérifiables, tests sur données réelles, relecture.
- La prochaine marche est **matérielle** : plus de VRAM (tout le modèle sur le GPU).
