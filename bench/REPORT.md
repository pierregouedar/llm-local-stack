# Local AI setup optimization — report

## Summary (2026-11-05)

| Real-world conditions (llama-server, real code from a real Rust project) | Before (mission launcher, b12004) | **After (`start-ia.bat`, mode A)** | Gain |
|---|---|---|---|
| Prefill 8k | 214 tok/s | **2,879 tok/s** | ×13 |
| **Prefill 32k** | 178 tok/s | **2,835 tok/s** | **×16** |
| **Prefill 64k** | — (VRAM overflow) | **2,461 tok/s** (64k read in ~27 s) | — |
| Generation 8k | 20 tok/s | **44 tok/s** (48 in mode B) | ×2.2 |
| Generation 32k / 64k | — | 41.6 / 39.2 tok/s (45 / 44 in mode B) | — |
| Cache reuse (same conversation) | 2048 tokens re-read in 10-15 s | 20 tokens re-read in 0.25 s | — |

Where the gain comes from: (1) the old launcher **overflowed VRAM** (262k context + `-ub 2048` + 28 expert layers on CPU); (2) **llama.cpp b12128**: +51 to +67% prefill at 32-64k; (3) **`-ub 4096`**; (4) **`--load-mode none`**: +40%; (5) `-t 6`.
Rejected (measured, no gain): power plan, `-tb`, `--cache-reuse`, MTP at 262k, CUDA 13.4.

**Recommended next step**: measure in your real sessions whether prefill or generation is what limits you. Yesterday, with the cache in place, generation accounted for ~85% of the time → if that holds, switch to mode B (`start-ia.bat mtp`), and a future GPU purchase should target **memory bandwidth and VRAM** (whole model in VRAM = generation ×2 or more), not just compute.

## Phase 1 — Inventory (2026-11-05, read-only)

### GPU
| Item | Value |
|---|---|
| Card | RTX 3080 10 GB (10240 MiB) |
| Driver | 610.88 (CUDA UMD 13.3) |
| Idle VRAM | **1506 MiB** used with no model loaded |
| Idle temperature | 47 °C |
| Power limit | 370 W (= default value) |
| Max clocks | core 2115 MHz, memory 9501 MHz (nominal values shown; the Afterburner OC does not appear here) |

### Idle VRAM per process (Windows "GPU Process Memory" counters)
| Process | VRAM |
|---|---|
| dwm (Windows desktop, 2 monitors) | 1235 MiB |
| firefox | 509 MiB |
| chrome | 239 MiB |
| Discord | 126 MiB |
| Spotify | 70 MiB |
| other Electron app | 68 MiB |
| NVIDIA Overlay | 46 MiB |

Browsers + Discord + Spotify + overlay ≈ **1 GB recoverable** during AI sessions. dwm (desktop) is not.

### llama.cpp
| Item | Value |
|---|---|
| Version | build **12004**, commit `3c809f443`, official Windows **CUDA 12.4** binary (Clang 20) |
| Path | `<llama.cpp b12004>\` |
| CPU backend | dynamic selection (`ggml-cpu-*.dll`, Zen 2 → haswell/AVX2 variant) |

### Models present
| File | Size |
|---|---|
| `<NVMe models>\Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf` (NVMe) | 21.28 GB |
| `<SATA models>\Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf` (SATA, copy) | 21.28 GB |
| `<SATA models>\Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-Q4_K_S.gguf` | 20.43 GB |
| `<SATA models>\Qwen3.6-35B-A3B-UD-IQ4_XS.gguf` | 17.73 GB |
| `<SATA models>\TwIL-8B-Q4_K_M-balanced.gguf` | 5.35 GB |

⚠️ **`D:\models\Tiel-Coder-35B-A3B-UD-Q4_K_S.gguf` (named in the mission) does not exist.** The installed model is **Cyber-Tiel** (an "abliterated" variant of Tiel-Coder, with an MTP head), same Ornith 1.5 base.

### System
| Item | Value |
|---|---|
| Power plan | AMD Ryzen™ Balanced |
| HAGS | `HwSchMode` key absent → Windows default setting (cannot be determined without opening Settings) |
| Fast startup | enabled (`HiberbootEnabled=1`) |
| Wake-on-LAN | Realtek Gaming GbE adapter already allowed to wake the PC (`wake_armed`) |
| Defender exclusions | unreadable without administrator rights |

### Current AI stack (set up on 11/05)
- **llama-swap v270** (`<llama-swap>\`) in front of llama-server, config `<stack>\llama-swap.yaml`: Cyber-Tiel with `-ncmoe 31 -c 131072 -np 2 -t 6 -ub 1024 -lm none -ctk/-ctv q8_0 --spec-type draft-mtp --reasoning-budget 4000 --checkpoint-min-step 2048`, listening on the Tailscale IP `<PC Tailscale IP>:8080` with an API key.
- **OpenCode v1.19.5** in server mode (`opencode serve`) on `<PC Tailscale IP>:4096`, started by hand via `<stack>\start-ai.ps1` (no service or scheduled task). Config: `~\.config\opencode\` (`opencode.json`, `AGENTS.md`, `llama-key`).
- **State at the time of the survey: no llama-swap / llama-server / opencode process running** (stopped, no PC reboot since 11/04 21:03).
- The `.bat` launcher described in the mission (`-c 262144 -t 8 -ub 2048 --cache-reuse 256`, 127.0.0.1) **does not exist on disk**; the launchers present are `lancer-cybertiel.bat` / `lancer-heretic.bat` (Desktop and `<old folder>`).
- **omp v18.14.0** already downloaded (`<stack>\bin\omp-v18.14.0\omp.exe`, 10/30), not installed in the PATH. `~/.omp` only contains `logs`, `natives`, `run`.

## Phase 2 — Baseline (mission launcher parameters, llama.cpp b12004 CUDA 12.4)

Model: `<NVMe models>\Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_S.gguf` (the mission's Tiel-Coder does not exist on disk).
Parameters: `-ngl 99 --n-cpu-moe 28 --jinja -c 262144 -fa on -ctk q8_0 -ctv q8_0 -t 8 -b 2048 -ub 2048 -np 1 --cache-reuse 256` (no MTP in this launcher).
Bench: `bench\bench.ps1`. Medians; llama-bench `-r 3`, server 2 passes.

| Test | Context | Prefill (tok/s) | Generation (tok/s) | Peak VRAM |
|---|---|---|---|---|
| llama-bench | 0 | 813 | 50.9 | 9944 MiB |
| llama-bench | 16k | 928 | 51.5 | 9944 MiB |
| llama-bench | 32k | 891 | 49.3 | 9944 MiB |
| llama-bench | 64k | 814 | 43.9 | 9944 MiB |
| **llama-server, real code** | **8k** | **214** | **20.1** | 9927 MiB |
| **llama-server, real code** | **32k** | **178** | — (empty response) | 9927 MiB |

**Finding**: under real conditions, this launcher **overflows VRAM** (262k of reserved context + `-ub 2048` + only 28 expert layers on CPU). The driver falls back to system RAM: prefill collapses to ~200 tok/s (4 to 9× less than llama-bench, which only reserves the test's context) and generation to ~20 tok/s.
Cache reuse: the 2nd request sharing the same prefix still re-reads **2048 tokens** (10-15 s) instead of ~0.

## Phase 3 — Updated llama.cpp (b12128, 2026-11-05)

Downloaded with your approval, SHA256 hashes verified, installed separately: `<llama.cpp>\b12128-cuda12.4\` and `<llama.cpp>\b12128-cuda13.4\`. Same parameters as the baseline.

| llama-bench prefill (tok/s) | b12004 | b12128 CUDA 12.4 | b12128 CUDA 13.4 |
|---|---|---|---|
| 0 | 813 | 777 | 1366 |
| 16k | 928 | **1554** | 1444 |
| 32k | 891 | **1485 (+67%)** | 1456 |
| 64k | 814 | **1230 (+51%)** | 1211 |

| llama-bench generation (tok/s) | b12004 | b12128 12.4 | b12128 13.4 |
|---|---|---|---|
| 0 / 16k / 32k / 64k | 50.9 / 51.5 / 49.3 / 43.9 | 51.1 / 49.2 / 47.7 / 43.7 | 51.3 / 49.3 / 47.6 / 43.0 |

Real server (still overflowing VRAM with these parameters): prefill 8k 229-237 tok/s, 32k 190-193 tok/s; generation 8k ~20 tok/s.

Output check: b12128 CUDA 12.4 writes a correct `median()` function (4 tests out of 4).

**Selected: b12128 CUDA 12.4** (prefill +51 to +67% at 32-64k, generation unchanged; CUDA 13.4 equivalent, slightly lower at 16-64k).

## Phase 4 — Parameter sweep (b12128 CUDA 12.4, server measurements on real code, 1 pass)

One variable at a time. "Overflows" = VRAM reaches ~9.9-10 GB and the driver falls back to system RAM (prefill collapses).

### `--n-cpu-moe` × `-c` × `-ub` (prefill 32k)
| -c | --n-cpu-moe | -ub | Max VRAM | Prefill 32k | Generation |
|---|---|---|---|---|---|
| 262k | 30 | 2048 | 10001 ❌ | 214 | 45.3 |
| 262k | 32 | 2048 | 9930 ⚠️ | 756 | 43.2 |
| 262k | 34 | 2048 | 9914 | 1154 | 42.2 |
| 262k | 35 | 2048 | 9537 | 1128 | 41.9 |
| 262k | 34 | 1024 | 9469 | 682 | 41.2 |
| 262k | 36 | 4096 | 9935 ⚠️ | 1040 | 39.4 |
| 262k | **38** | **4096** | 9533 | **1634** | 38.9 |
| 262k | 40 | 4096 | 8540 | 1588 | 37.2 |
| 131k | 30 | 512 | 9090 | 429 | 44.4 |
| 131k | 30 | 1024 | 9242 | 755 | — |
| 131k | 30 | 2048 | 9616 | 1293 | 45.2 |
| 131k | 30 | 4096 | 9932 ⚠️ | 1121 | 44.6 |
| 131k | **32** | **4096** | 9600 | **1777** | 42.6 |
| 131k | 33 | 4096 | 9142 | 1755 | — |

→ With experts on the CPU, **a large `-ub` (4096) greatly speeds up prefill** (expert weights are copied once per batch). Selected: `-ub 4096`, then the smallest `--n-cpu-moe` that leaves ~500-700 MB of headroom.

### Threads (base 262k / 38 / 4096)
| Setting | Prefill 32k | Generation |
|---|---|---|
| -t 8 | 1629 | 38.7 |
| **-t 6** | 1604 | **39.5** |
| -t 7 | 1605 | 39.3 |
| -t 16 | 1629 | 34.7 |
| -t 6 -tb 8 | 1610 | 39.5 |
| -t 6 -tb 16 | 1570 | 38.9 |
→ Selected **-t 6** (generation limited by RAM bandwidth); `-tb` has no effect → not kept.

### MTP (`--spec-type draft-mtp`)
- At 262k (`--n-cpu-moe` 38-41): **overflows in every case**, even with the MTP cache in q8 (`-ctkd/-ctvd q8_0`) and `--spec-draft-n-ubatch 512` → **rejected at 262k**.
- At 131k, `--n-cpu-moe 34`: still at the limit (9.94-9.99 GB).
- At 131k, `--n-cpu-moe 36` (9.2 GB): MTP 2 = generation **46.1 tok/s** at 8k and 32k (vs 44.5 / 42.7 without MTP at `--n-cpu-moe 32`), prefill slightly lower. Acceptance 65-72%. MTP 1: 46.3 / 41.9.
- MTP costs ~1.3 GB more VRAM than no MTP at the same setting.

### `--cache-reuse` and loading (base 131k / 32 / 4096)
| Setting | Prefill 8k | Prefill 32k | Generation 8k / 32k | Load time |
|---|---|---|---|---|
| --cache-reuse 0 | 1356 | 2086 | 44.5 / 42.7 | 6 s |
| --cache-reuse 256 | 1311 | 2035 | 46.0 / 41.7 | 6 s |
| --cache-reuse 512 | 1181 | 2027 | 44.6 / 42.5 | 6 s |
| --load-mode mmap | 1251 | 1973 | 45.7 / 42.8 | 8 s |
| **--load-mode none** | **2850** | **2837** | 44.4 / 42.2 | 16 s |
→ **`--load-mode none`: +40% prefill at 32k** (llama.cpp itself recommends it when experts are on the CPU). `--cache-reuse` has no effect on this hybrid model (resumption goes through checkpoints every `-ub` tokens) → removed.

### Rejected / not tested
- **f16 KV cache**: not tested, it would take VRAM and force `--n-cpu-moe` up (mission rule).
- **`--mlock`**: replaced by `--load-mode` in this version; `mlock` not tested (locks ~20 GB of RAM, risky with 32 GB).
- **`--spec-draft-p-min`**: not swept, since MTP only pays off at 131k with headroom; to do if finalist B is selected.

## Phase 4 — Finalists (b12128 CUDA 12.4, `--load-mode none`, `-ub 4096`, `-t 6`, median of 2 passes, real code)

| Config | Prefill 8k | **Prefill 32k** | **Prefill 64k** | Gen. 8k | Gen. 32k | Gen. 64k | Max VRAM | Load time |
|---|---|---|---|---|---|---|---|---|
| Baseline (mission launcher, b12004) | 214 | 178 | — | 20.1 | — | — | 9927 | — |
| **A — 131k, --n-cpu-moe 32** | **2879** | **2835** | **2461** | 44.1 | 41.6 | 39.2 | 9665 | 17 s |
| B — 131k, --n-cpu-moe 36, MTP 2 | 2243 | 2292 | 2029 | **47.6** | **44.9** | **43.7** | 9240 | 18 s |
| C — 262k, --n-cpu-moe 38 | 2265 | 2388 | 2119 | 41.3 | 38.3 | 35.7 | 9669 | 18 s |

llama-bench (prefill 2048 / generation 128, median of 3):
| Config | pp 0 / 16k / 32k / 64k | tg 0 / 16k / 32k / 64k |
|---|---|---|
| Baseline | 813 / 928 / 891 / 814 | 50.9 / 51.5 / 49.3 / 43.9 |
| A | 2473 / 2188 / 1999 / 1681 | 48.4 / 46.0 / 44.5 / 40.6 |
| B (no MTP in llama-bench) | 1975 / 1852 / 1654 / 1510 | 44.7 / 43.0 / 41.2 / 38.5 |
| C | 1968 / 1779 / 1684 / 1466 | 43.0 / 41.6 / 39.8 / 36.9 |

**Selected: A** (mission priority = prefill at 32k/64k) → `<AI folder>\start-ia.bat` (`prefill` mode by default). **B** available (`start-ia.bat mtp`): best choice if generation matters more (in the real OpenCode sessions of 11/05, generation accounted for ~85% of the time once the cache was in place). **C** rejected: 262k of context is rarely useful with "one session per task", and it has the slowest generation.

Gains of A vs baseline (real conditions): **prefill ×13 at 8k, ×16 at 32k**; generation ×2.2 at 8k. Reading 64k tokens of context: ~27 s.

Cache between two successive requests (chat format, same prefix): verified on `start-ia` — 2nd request of 4106 tokens: **20 tokens re-read in 0.25 s**. With an identical prefix but a different ending, the hybrid model resumes from the last checkpoint: up to `-ub` (4096) tokens re-read, 1.4-2.5 s.

Caveat: b12128 failed 3 times out of ~40 starts with `CUDA error: shared object initialization failed` (right after another server was stopped). No driver error; the 2nd attempt succeeds. `start-ia.ps1` retries automatically (3 attempts).

## Carried over to llama-swap (Tailscale access from the Mac) — evening of 11/05

Settings A and B carried over to `llama-swap.yaml` (2 `-np 2` slots kept for OpenCode). Measurements through llama-swap over Tailscale (real code, 30k tokens):
| Model | Prefill 30k | Generation | 2nd request | VRAM |
|---|---|---|---|---|
| `cybertiel` (A) | 2696-2739 tok/s | 42-43 tok/s | 20 tokens re-read in 0.27 s | 9.8 GB |
| `heretic` (MTP, `-ncmoe 34`, 13k tokens) | 2200 tok/s | 47 tok/s | — | 9.3 GB |

**"CUDA error: shared object initialization failed" start failures: cause found.** They mostly affected configs with MTP (`heretic` 3/3, `cybertiel-mtp` 2/3 when switching models), **including with the old b12004** (4/4 failures) → not a b12128 bug, nor a lack of VRAM (also fails with 3 GB free). The driver loads CUDA function code on demand, and that loading fails at the moment llama.cpp queries the functions of the MTP context. `GGML_CUDA_PDL=0`: no effect. **`CUDA_MODULE_LOADING=EAGER`: 4/4 direct starts OK, 7/7 model switches OK through llama-swap**, same speed, ~+400 MB of VRAM, load time ~19-22 s. Applied in `llama-swap.yaml` and `start-ia.ps1`.

## Additions from the evening of 11/05 (2 passes, medians, production config: `-np 2`, `CUDA_MODULE_LOADING=EAGER`)

### 262k context (discrepancy fixed: the mission called for 262,144)
`-c 262144 -np 2 --kv-unified --n-cpu-moe 38` (shared cache: one conversation can grow to ~250k):
| Context | Prefill | Generation | Max VRAM |
|---|---|---|---|
| 32k | 2440 | 40.0 | 9813 MiB |
| 64k | 2178 | 36.4 | 9813 MiB |
| 128k | 1879 | 31.7 | 9813 MiB |
Headroom ~430 MiB (same as `cybertiel`) → `--n-cpu-moe` 39/40 not tested. Added to llama-swap: **`cybertiel-262k`**. Test through llama-swap: 97,072-token conversation OK (1982 tok/s, 34.7 tok/s), side request on the other slot without cache loss (20 tokens re-read in 0.31 s).

### MTP threshold (`--spec-draft-p-min`, `cybertiel-mtp` config)
| p-min | Gen. 8k / 32k | Acceptance | Prefill 8k / 32k |
|---|---|---|---|
| **0 (selected)** | **50.7 / 50.0** | 67-71% | 2414 / 2381 |
| 0.4 | 48.7 / 47.0 | 77% | 2424 / 2414 |
| 0.6 | 45.8 / 44.3 | 82-87% | 2425 / 2425 |
| 0.8 | 42.6 / 43.0 | 93% | 2402 / 2411 |
→ A higher threshold accepts more but drafts less: slower. 0.5 and 0.7 not tested (clear trend).

### Cross-check (production `cybertiel` config)
| Variant | Prefill 8k / 32k | Gen. 8k / 32k | VRAM |
|---|---|---|---|
| **Base: `-ub 4096`, `--load-mode none`, `-t 6`** | **3015 / 2949** | 49.0 / 46.6 | 9363 |
| `-ub 2048` | 2125 / 2085 (−30%) | 49.8 / 46.7 | 8751 |
| `--load-mode mmap` | 1336 / 2174 (−56% / −26%) | 48.5 / 46.2 | 9363 |
→ Both choices confirmed over 2 passes. `-t 8` not redone (clearly ruled out in 1 pass: −2%).

### Production models summary (llama-swap)
| Model | Prefill 32k | Generation 32k | Context / conversation | Use |
|---|---|---|---|---|
| `cybertiel` | ~2950 | ~47 | 64k | fastest context reading |
| `cybertiel-mtp` | ~2380 | **~50** | 64k | **everyday dev** |
| `cybertiel-262k` | ~2440 | ~40 | **~250k** | long sessions |
| `heretic` | ~2200 (13k) | ~47 | 64k | general |

## Phase 5 — Windows

### Power plan (config A, 2 passes, plan restored afterwards)
| Plan | Prefill 8k | Prefill 32k | Gen. 8k | Gen. 32k |
|---|---|---|---|---|
| AMD Ryzen Balanced (current) | 2846 | 2829 | 44.6 | 42.7 |
| AMD Ryzen High Performance | 2850 | 2822 | 44.3 | 41.5 |
| Ultimate Performance | 2845 | 2840 | 45.4 | 42.7 |
→ **No measurable gain** (< 2%, within noise) → **rejected**, `start-ia` / `stop-ia` do not touch the power plan.

### Application VRAM (not changed — for you to approve)
At idle with your apps open: ~1.5 GB used (dwm 1.2 GB, Firefox 0.5 GB, Chrome 0.24 GB, Discord 0.13 GB, Spotify 0.07 GB, NVIDIA overlay 0.05 GB). Closing browsers + Discord + Spotify + overlay during a session frees ~1 GB, enough to lower `--n-cpu-moe` from 32 to ~30 (not measured). List of apps to close: see `A-DECIDER.md`.

### HAGS, Defender
Not tested (reboot / administrator rights): see `A-DECIDER.md`.

## Phase 6 — ik_llama.cpp
No official Windows binary (only release: `t0002`, July 2025, with no files; repository active). It would have to be compiled (Visual Studio Build Tools + CUDA Toolkit, several GB) → **not done, to be decided**. A third-party repository offering binaries (8 stars, unverifiable origin) was ruled out.

### Tools
| Tool | Version |
|---|---|
| git | 2.56.0 |
| Python | 3.13.7 |
| Rust | cargo / rustc 1.99.1 (`%USERPROFILE%\.cargo\bin`, not in PATH) |
| Node.js / npm / bun | not installed |
