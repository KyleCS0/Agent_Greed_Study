# Worker Branch 1: histogram-cuda Condition A

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Fix uncoalesced global memory access in histogram_smem_atomics by swapping the loop order so threads walk across columns (coalesced) in the inner loop. Currently the kernel iterates 'col' in the outer loop and 'row' in the inner loop, meaning consecutive threads (differing in threadIdx.x) access pixels separated by 'width' elements in memory (in[row * width + col]). Swap to: outer loop over row (stride ny), inner loop over col (stride nx), so that when the warp reads 'in[row * width + col]' the 32 threads in a warp hit consecutive addresses (col, col+1, ..., col+31). This directly addresses the 57% global load efficiency. Apply the same fix to histogram_gmem_atomics. Be careful: the iteration range and strides (nx, ny) remain the same; only the loop nesting changes. Correctness risk: none if strides are kept. Performance risk: none; this is a pure latency/bandwidth improvement.

## Baseline Context

Before editing, read this Planner measurement context if it exists:

```text
baseline_context/planner_run.json
```

Use it to understand the starting timing, speedup, profile digest, static resources, and bottlenecks. It is reference context only; do not modify files under `baseline_context/`.

## Editable Files

You may edit only these files:

- `src/histogram_compare.cu`
- `src/histogram_smem_atomics.h`
- `src/histogram_gmem_atomics.h`

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
