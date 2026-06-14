# Worker Branch 5: stencil3d-cuda Condition A

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Increase XTILE from 20 to 32 (or 40) to amortize per-block startup overhead and improve sigma L2 cache reuse. Target bottleneck: short-dependency stalls (17.3%) and the fixed per-block cost of loading the initial two psi planes and computing the initial xcharge. With XTILE=20 the loop runs 20 iterations; each has 4 (or 2 after plan 2) barriers plus arithmetic. Increasing XTILE to 32 raises useful arithmetic-to-sync ratio by 60%. Additionally, the sigmaX/Y/Z arrays are accessed sequentially in x; a larger tile reuses more of the sigma entries already resident in L2 per block launch. Steps: (1) Change `#define XTILE 20` to `#define XTILE 32`. (2) Recompile and verify the boundary logic: nLast_x is correctly computed as `nx-2 - XTILE * blockIdx.x + 1` for the last block, so no code changes are needed beyond the define. (3) Check ptxas register count (currently 40/thread); if XTILE increase raises it to 48 or beyond, occupancy may drop. Try XTILE=32 first, then 40 if registers stay at 40. (4) Verify grid dimension bdimx = ceil((nx-2)/XTILE) still covers all interior cells for non-power-of-two grid sizes. Correctness risk: boundary iteration count must be validated; off-by-one in nLast_x for the last block in x is the main hazard. Performance risk: register spill if XTILE is set too large; if the extra nii load `psi(ii+1,...)` stresses the memory pipeline more than it gains from cache reuse, performance may plateau; benchmark both 32 and 40.

## Baseline Context

Before editing, read this Planner measurement context if it exists:

```text
baseline_context/planner_run.json
```

Use it to understand the starting timing, speedup, profile digest, static resources, and bottlenecks. It is reference context only; do not modify files under `baseline_context/`.

## Editable Files

You may edit only these files:

- `src/main.cu`

Do not edit any other file.

## Rules

1. Stay in this branch directory for the whole task. Do not `cd` to the repo root, parent condition directory, or any directory outside this branch.
2. Read and edit only files inside this branch directory: the editable source files listed above, `LOG.md`, `baseline_context/planner_run.json`, and public files under `out/`.
3. Treat `./src/run.sh` as a black-box evaluator. You may execute it, but do not inspect or modify `src/run.sh`, repo-level runner scripts, `.agent_greed_run.json`, or `.agent_greed_policy.json`.
4. Make one focused source-code change per attempt.
5. After every change, run this from the branch directory. Set the Bash/tool timeout to at least 10 minutes because profiling can exceed the default 2-minute timeout:

```bash
./src/run.sh
```

A completed run prints a final line like `wrote out/run_005/run.json status=correct speedup=1.0179`. If the command times out, do not assume success from a stale `out/latest_run.json`; verify that a new `out/run_NNN/run.json` was created for this attempt, or rerun with a longer timeout.

6. Read the latest public result file:

```text
out/latest_run.json
```

7. Append an entry to `LOG.md` after every attempt. Mark whether it counted as a successful iteration.
8. Track the best successful speedup so far. If a new successful run is worse, use it as information, then continue from the best-performing source unless you explicitly state why the worse source is required as a stepping stone.
9. If compile, correctness, runtime, policy, or profile status fails, revert to the previous correct source, log the failed attempt, and continue until you have 7 successful iterations.
10. Do not hardcode output, timing, correctness, or benchmark values.
11. Do not modify `README.md`, `.agent_greed_run.json`, `.agent_greed_policy.json`, existing `LOG.md` history, `baseline_context/`, `out/`, or any files outside the editable allowlist.

## Required Log Format

For each attempt, append:

```markdown
## Attempt N

- Counted iteration: yes/no
- Successful iteration number: N/A or 1-7
- Change:
- Status:
- Speedup:
- Profile backend:
- What I learned:
- Best speedup so far:
- Next step:
```
