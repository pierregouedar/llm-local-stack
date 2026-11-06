# Use case

## The need
- **A coding agent** (omp, OpenCode) for my personal projects: JS/TS, Rust, Python.
- **Usable remotely**, from my Mac at work, like a cloud assistant, but **on my own hardware**: no quota, and the code stays at home.
- The PC must not run 24/7: **wake on demand**, sleep when it is not in use.

## The constraints
- **Windows is mandatory** on the PC (games with kernel anti-cheat, Game Pass): no Linux, **no WSL**.
- **Nothing to buy**: optimize the existing hardware.
- **No scheduled task or Windows service**: I want to stay in control of what runs.
- Quality comes before speed: no quantization below Q4, no KV cache below q8, sampling settings recommended by the model publisher.

## The hardware
| Machine | Role | Details |
|---|---|---|
| PC | compute | RTX 3080 **10 GB**, Ryzen 7 3800X (Zen 2, 8 c/16 t), 32 GB DDR4-3600 dual channel, NVMe Gen3 1 TB + SATA SSD 1 TB, 2 monitors |
| NAS | wake-up, always on | Linux mini-PC + Docker (CasaOS), Tailscale |
| Mac | workstation | omp, OpenCode, Tailscale |

**The real challenge**: running a serious coding model (35B) with **10 GB of VRAM**.

## The journey (summary)
1. **Starting point**: Qwen3.6-35B-A3B in IQ4_XS, automatic settings: ~32-37 tok/s.
2. **Choosing the model**: a dense 27B, "smarter" on paper, drops to **3.5 tok/s** (it does not fit in VRAM); an 8B fully in VRAM does 90 tok/s but produces broken code on a real project. A **MoE 35B-A3B** (3B active) with an **MTP** head is the right compromise → Qwen3.6 heretic, then **Cyber-Tiel Coder** (Ornith 1.5, geared toward coding and agents).
3. **Format**: Q4_K instead of IQ4: +40% generation.
4. **Manual tuning** (`--n-cpu-moe`, `-t 6`, `--load-mode none`): ~63 tok/s generation with MTP on the old llama.cpp version.
5. **Overclocking**: RAM, VRAM, GPU... no measurable gain for the LLM, and the core overclock crashed the driver under CUDA. Dropped for LLM workloads.
6. **Remote access**: llama-swap (several models behind one address, API key) exposed **only on Tailscale**; omp and OpenCode on the Mac point to it.
7. **Real agent usage**: log analysis showed the agent spent 19% of its time **re-reading** prompts (side requests overwriting the cache) → 2 slots, checkpoints, capped reasoning: **−36% time per request**.
8. **Quality**: a real project driven in agent mode revealed that the model **made up** the data it was missing (and tests that validated its inventions) → explicit `AGENTS.md` rules, verified on a trap test.
9. **Systematic optimization** (one variable at a time, repeated measurements): the original launcher **overflowed VRAM**; new llama.cpp version, large batches, no mmap → **16x prefill** (178 → 2,949 tok/s at 32k).
10. **Context**: a **262k** variant for long sessions (without MTP, which does not fit alongside it).
11. **Remote wake-up**: the NAS sends a Wake-on-LAN, then asks a small **agent** on the PC to start the stack if needed. Automatic sleep after 30 min of inactivity.

Detailed numbers for each step: [BENCHMARKS.md](BENCHMARKS.md).

## The choices and their trade-offs
| Choice | Gain | What I accept |
|---|---|---|
| MoE 35B-A3B rather than dense | usable (50 tok/s) with 10 GB | part of it on the CPU, generation bound by RAM |
| Experts on the CPU (`--n-cpu-moe`) | the model fits | fine-tuning to redo if free VRAM changes |
| `-ub 4096` + `--load-mode none` | 2-3x prefill | 16-20 s load time |
| MTP | +5 to 20% generation | ~1.3 GB of VRAM, incompatible with 262k |
| 262k context | fewer compactions | generation ~40 → 32 tok/s as the conversation grows |
| Capped reasoning (4,000) | −36% time per request | slightly less reasoning on hard problems (not measured) |
| "Abliterated" version (Cyber-Tiel) | no refusals | more risk of confident answers when it makes things up → `AGENTS.md` rules |
| No scheduled task or service | nothing automatic "hidden" in Windows | after a reboot, click `start.bat` |

## What I take away from it
- **Measure under real conditions** (server + real code): llama-bench alone does not see VRAM overflows, which were the number one cause of slowness.
- **Once overflows are avoided, the new llama.cpp version and two options (`-ub`, `--load-mode`) do most of the work.** The rest (threads, power plan, overclocking) is marginal.
- **For an agent, generation dominates** (~85% of the time) once the cache is managed properly.
- **A local model of this size writes clean code but needs a framework**: real data, verifiable steps, tests on real data, review.
- The next step is **hardware**: more VRAM (the whole model on the GPU).
