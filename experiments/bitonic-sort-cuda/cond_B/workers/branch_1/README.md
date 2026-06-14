# Worker Branch 1: bitonic-sort-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Fuse multiple bitonic sort stages into a single kernel using shared memory. For each step, when all remaining stages of that step fit within a shared memory tile (i.e., the sequence length <= 2*BLOCK_SIZE), load a tile of elements into shared memory, perform all sub-stages entirely in shared memory with __syncthreads() between stages, then write back once. This eliminates repeated global memory round-trips for the inner stages and amortizes kernel launch overhead. Implementation: in ParallelBitonicSort, launch a single fused kernel for all stages within a step where seq_len <= 2*blockDim.x (these are the 'local' stages), processing a tile of 2*BLOCK_SIZE elements per block with dynamic shared memory. For stages with seq_len > 2*BLOCK_SIZE, keep the existing per-stage global kernel. Use __syncthreads() between each sub-stage within the fused kernel. The fused local kernel eliminates O(step) kernel launches per step and replaces O(step) global memory round-trips per tile with a single load/store pair. Target bottleneck: 58.8% memory stall and 50% load efficiency from repeated global accesses to the same data. Risk: shared memory size limit (48KB default on sm_89 = 12K ints per block); use BLOCK_SIZE=512 or 1024 with dynamic smem allocation. Correctness risk: must ensure __syncthreads() between every compare-swap stage within the fused kernel.

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
