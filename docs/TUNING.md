# Tuning for your hardware

The repository values were measured on an **RTX 3080 10 GB + Ryzen 7 3800X + 32 GB DDR4** (see [BENCHMARKS.md](BENCHMARKS.md)).
On a different machine the method stays the same; only a few values change.

## What carries over as is
| Setting | Why it applies generally |
|---|---|
| `--load-mode none` | as soon as some experts are on the CPU, mmap slows down prefill |
| `-b / -ub 4096` | same reason: large batches amortize copying experts to the GPU (if VRAM allows) |
| `-ctk / -ctv q8_0` | same speed as f16, less VRAM, quality preserved |
| `-fa on` | flash attention |
| `-np 2` + `--checkpoint-min-step 2048` | agent use: the main session keeps its cache |
| `--reasoning-budget` | caps reasoning: shorter answers, faster agent |
| `CUDA_MODULE_LOADING=EAGER` | avoids CUDA initialization failures at startup |
| `Q4_K_*` formats rather than `IQ4_*` | when part of the model runs on the CPU |
| Models on NVMe | loading is 3.5x faster |

## What you need to re-measure
### 1. `--n-cpu-moe` (the most important)
The smallest N that leaves **~400-500 MB of VRAM free at peak**, with your usual applications open.
1. Start with a safe value (e.g. 40 on 10 GB; less on 12-16 GB, ~0 on 24 GB for a 35B-A3B in Q4).
2. Measure the **real server** on a real prompt the size of your workload (32k, 64k):
   ```powershell
   .\bench\bench.ps1 -Label try-ncmoe34 -SkipBench -PromptSizes 32768 -Runs 1 -CodeDir C:\code\some-repo `
     -ServerArgs "-ngl 99 --n-cpu-moe 34 -c 131072 -np 2 -fa on -ctk q8_0 -ctv q8_0 -b 4096 -ub 4096 -t 6 --load-mode none"
   ```
   `bench.ps1` is a PowerShell script for Windows. On Linux, start `llama-server` with the same arguments, send a prompt of that size and read the prompt/generation speeds in its log, with `nvidia-smi` for peak VRAM.
3. Lower it by 1-2 as long as peak VRAM (`vram_max_mib` column) stays below `total VRAM − 500 MB` **and** prefill does not collapse (sign of overflow: prefill divided by 3 or more).
4. With MTP, budget ~1.3 GB more (≈ 3-4 more expert layers on the CPU).

### 2. `-t` (threads)
Try `-t` = number of physical cores, then −1, −2. On a CPU bound by RAM bandwidth, fewer threads often do better. Avoid SMT (16 threads on 8 cores = −12% here).

### 3. `-ub`
4096 if VRAM allows, otherwise 2048 (measure it: 512 → 4096 = 7x prefill here).

### 4. MTP
- Only if the model has an MTP head (`nextn` in the GGUF metadata; an "MTP" name is not enough).
- `--spec-draft-n-max` 2 or 3; `--spec-draft-p-min` 0.
- Reduce the MTP cache and batch to save VRAM: `-ctkd q8_0 -ctvd q8_0 --spec-draft-n-ubatch 512`.

### 5. Context
- "One session per task" agent: 64k per conversation is often enough.
- Long sessions: `-c 262144 -np 2 --kv-unified` (shared context), at the cost of a few more expert layers on the CPU.

## If you have more VRAM
A 35B-A3B in Q4 (~20 GB) **fully in VRAM** (24 GB or more) removes the RAM bottleneck: generation should more than double (not measured here). With 16 GB, `--n-cpu-moe` can go down significantly.

## Quick diagnosis
| Symptom | Cause | Action |
|---|---|---|
| Prefill or generation divided by 3+ | VRAM overflow | `--n-cpu-moe` +1/+2, close GPU applications |
| `CUDA error: shared object initialization failed` | lazy CUDA module loading | `CUDA_MODULE_LOADING=EAGER` |
| "context type MTP requested but model doesn't contain MTP layers" | no MTP head | remove `--spec-type draft-mtp` |
| GPU driver crashes (nvlddmkm) under CUDA | unstable GPU overclock | remove the core overclock (3D benchmarks are not enough to validate it) |
