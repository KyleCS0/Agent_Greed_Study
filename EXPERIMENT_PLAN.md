# Experiment Execution Plan

## Configuration

```
KERNEL:     histogram-cuda
CONDITIONS: A  B
```

> To run a different kernel, change `KERNEL` above. Everything below reads from that value.
> All paths below use `<KERNEL>` and `<COND>` as placeholders — substitute before running.

---

## Scope

| Step | What | Agent invocations |
|---|---|---|
| Cond A planner | 1 | 1 |
| Cond A workers | branch_1–branch_5 | 5 |
| Cond B planner | 1 | 1 |
| Cond B workers | branch_1–branch_5 | 5 |
| **Total** | | **12** |

**Pause point:** After invocation #5 (Cond A planner + Cond A workers branch_1–branch_4). Report status to user and wait for go-ahead before continuing.

---

## Phase 0: Environment Check

Run once before anything else:

```bash
cd <repo-root>
python3 -m py_compile elicitation.py scripts/validate_elicitation.py scripts/create_workers.py scripts/analyze_experiment.py scripts/run_kernel.py scripts/check_correctness.py scripts/parse_ncu.py scripts/parse_nsys_stats.py
python3 -m json.tool config/kernels.json >/dev/null
command -v nvcc make claude
command -v ncu || true
command -v nsys || true
sudo -n true || true
git status --short
```

**Go criteria:** Python compiles clean, `nvcc`/`make`/`claude` exist.
Note the available profiling backend (`ncu` > `nsys` > none) — it will appear as `profile_backend` in each `run.json`.

---

## GPU Occupancy Check (before every worker branch)

Before spawning each worker agent, confirm the GPU is idle:

```bash
nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader
```

**Go criteria:** Output is empty (no running compute processes from other users).

If another user's process appears, wait and re-check every 60 seconds until the GPU is free. Do not spawn the worker while the GPU is occupied — results would be contaminated by resource contention.

---

## Phase 1: Condition A Setup

```bash
cd <repo-root>
./elicitation.py <KERNEL> A
```

**Check after:** `experiments/<KERNEL>/cond_A/` exists with `README.md`, `benchmark.sh`, `validate.sh`, `create_workers.sh`, and `planner/src/`.

---

## Phase 2: Condition A — Planner (invocation #1)

**Working dir:** `experiments/<KERNEL>/cond_A`

**Agent prompt — use EXACTLY this, nothing else:**
```
Read README.md and write response.json exactly as instructed.
```

> **Study constraint:** Do NOT add any extra context, hints, instructions, or framing beyond the exact prompt above. Any deviation contaminates the behavioral study.

**Verify after agent returns:**
```bash
cd experiments/<KERNEL>/cond_A
./validate.sh
```

**Go criteria:** `./validate.sh` prints `valid response.json`.
If it fails, inspect `response.json` (must be a JSON array of 5 objects with only `rank` and `plan` keys) and fix before proceeding — do not re-prompt the agent.

---

## Phase 3: Create Condition A Worker Branches

```bash
cd experiments/<KERNEL>/cond_A
./create_workers.sh
```

**Check after:** `workers/branch_1` through `workers/branch_5` exist, each with `README.md`, `src/`, `out/`, and `src/run.sh`.

---

## Phase 4: Condition A — Workers (invocations #2–#6)

Run branches sequentially. **Pause after branch_4 (invocation #5 total).**

### For each branch N:

**Before spawning:** Run the GPU occupancy check (see above). Wait if occupied.

**Working dir:** `experiments/<KERNEL>/cond_A/workers/branch_N`

**Agent prompt — substitute `<KERNEL>`, `<COND>`, and `N` before running:**
```
Work only in experiments/<KERNEL>/<COND>/workers/branch_N. Read README.md and strictly follow it.
```

> **Study constraint:** Do NOT add optimization hints, context about the kernel, or framing beyond the above. The working-directory prefix is navigation only and does not contaminate the study. Spawn via the Agent tool (not `claude -p` via Bash) so file-write permissions flow through the parent session.

**Verify after each agent returns:**
```bash
BRANCH=experiments/<KERNEL>/cond_A/workers/branch_N
python3 -c "
import json, glob
runs = [json.load(open(p)) for p in glob.glob('$BRANCH/out/run_*/run.json')]
correct = [r for r in runs if r.get('status') == 'correct']
print(f'{len(correct)} correct runs of {len(runs)} total')
for r in correct: print(f'  speedup={r.get(\"speedup\",\"?\")}')
"
cat $BRANCH/out/latest_run.json
```

**Go criteria:** 7 or more correct runs logged.

**If < 7 correct runs:** agent may have timed out. Respawn with the same exact prompt — existing `out/run_NNN/` data is preserved and the agent resumes from current state.

### Error handling:

| `status` in `run.json` | Action |
|---|---|
| `correct` | counts toward the 7-iteration goal |
| `policy_violation` | revert the offending file, respawn agent |
| `compile_error` / `correctness_fail` / `runtime_error` | does not count; agent should revert automatically — if stuck, respawn |
| `profile_error` | timing/correctness may still be valid; check `status` field, note weak profiling |

### Branch schedule:

| Invocation | Branch | Pause after? |
|---|---|---|
| #1 | planner | no |
| #2 | branch_1 | no |
| #3 | branch_2 | no |
| #4 | branch_3 | no |
| #5 | branch_4 | **YES — report to user, wait for go-ahead** |
| #6 | branch_5 | no |

---

## Phase 5: Condition A — Analysis

After all 5 branches have 7 correct iterations:

```bash
cd experiments/<KERNEL>/cond_A
./analyze.sh
cat analysis/analysis.json
```

**Key fields to report to user:**
- `speedup_iter1` — first-iteration speedup per branch
- `peak_speedup_7` — best speedup within 7 iterations per branch
- `spearman_iter1`, `spearman_peak7` — plan ranking correlations
- `num_successful_iterations`, `num_attempts_total` — completeness and friction

---

## Phase 6–10: Condition B

Repeat Phases 1–5 with `cond_B` substituted for `cond_A`, starting at invocation #7.

```bash
cd <repo-root>
./elicitation.py <KERNEL> B
```

Invocations #7–#12 follow the same branch schedule and verification steps.

---

## Quick Reference: Where to Look

| What | Path |
|---|---|
| Latest run result | `experiments/<KERNEL>/<COND>/workers/branch_N/out/latest_run.json` |
| All run details | `experiments/<KERNEL>/<COND>/workers/branch_N/out/run_NNN/run.json` |
| Raw compiler/profiler output | `experiments/<KERNEL>/<COND>/workers/branch_N/out/run_NNN/raw/` |
| Profiling backend used | `profile_backend` field in any `run.json` |
| Planner response | `experiments/<KERNEL>/<COND>/response.json` |
| Condition analysis | `experiments/<KERNEL>/<COND>/analysis/analysis.json` |

---

## Execution Checklist

**Condition A**
- [ ] Phase 0: env check passed, profiling backend noted
- [ ] Phase 1: `experiments/<KERNEL>/cond_A/` created
- [ ] Phase 2: planner ran, `./validate.sh` green (inv #1)
- [ ] Phase 3: worker branches created
- [ ] Phase 4a: branch_1 — 7 correct runs (inv #2)
- [ ] Phase 4b: branch_2 — 7 correct runs (inv #3)
- [ ] Phase 4c: branch_3 — 7 correct runs (inv #4)
- [ ] Phase 4d: branch_4 — 7 correct runs (inv #5) ← **PAUSE, report to user**
- [ ] Phase 4e: branch_5 — 7 correct runs (inv #6)
- [ ] Phase 5: analysis complete

**Condition B**
- [ ] Phase 6: `experiments/<KERNEL>/cond_B/` created (inv #7 starts)
- [ ] Phase 7: planner ran, `./validate.sh` green (inv #7)
- [ ] Phase 8: worker branches created
- [ ] Phase 9a: branch_1 — 7 correct runs (inv #8)
- [ ] Phase 9b: branch_2 — 7 correct runs (inv #9)
- [ ] Phase 9c: branch_3 — 7 correct runs (inv #10)
- [ ] Phase 9d: branch_4 — 7 correct runs (inv #11)
- [ ] Phase 9e: branch_5 — 7 correct runs (inv #12)
- [ ] Phase 10: analysis complete
