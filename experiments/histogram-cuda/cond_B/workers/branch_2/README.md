# Worker Branch 2: histogram-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Eliminate the two-kernel (first-pass + accumulation) overhead by using warp-level privatization with shuffle-based reduction to produce a single-pass result in histogram_smem_atomics.h. Steps: (1) Keep per-block smem partial histograms as before. (2) After the __syncthreads() barrier, instead of writing to d_part_hist and launching a second kernel, use atomicAdd directly from shared memory into the global d_hist array (one atomicAdd per bin per block). This eliminates the second-pass kernel launch latency and the cudaMalloc/Free of d_part_hist (which currently allocates 256*1024*4 = 1MB per call). The d_part_hist allocation/free is inside run_smem_atomics and measured in the timed region — removing it saves significant overhead. (3) In histogram_compare.cu adjust run_smem_atomics accordingly: remove NUM_PARTS, d_part_hist allocation, and the accum kernel launch. Initialize d_hist to zero before the kernel (cudaMemset). Correctness risk: global atomicAdd from 256 blocks contending on 768 bins may be slower than smem-then-accum for large grids; keep grid small (e.g., 8x8=64 blocks) to limit contention. Performance risk: if many blocks finish simultaneously, global atomic pressure on 768 bins from 64 blocks is manageable (~64 atomics/bin total).

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
