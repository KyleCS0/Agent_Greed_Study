# Worker Branch 1: softmax-cuda Condition A

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Cache the entire input slice in shared memory and reuse exp values to eliminate redundant global reads and transcendental calls. Currently softMax2 performs 3 global read passes per element (max scan, exp+sum, output) and calls expf(src[i*sliceSize+j]-max_) twice per element. Steps: (1) At kernel launch, pass dynamic smem of (BLOCK_SIZE/32)*sliceSize*sizeof(float) bytes per block. (2) In the first warp loop, each thread loads its strided elements from global mem into smem[warp_id*sliceSize + j] while scanning for local max. (3) Warp-reduce max via cg::reduce. (4) Second loop reads from smem, computes expf(val-max_), writes back to smem (overwriting input), accumulates sum. (5) Warp-reduce sum. (6) Third loop reads smem exp values and writes exp[j]/sum to global dest. Net effect: global reads drop from 3x to 1x sliceSize, expf calls halved, output pass reads from smem instead of global mem. Target bottleneck: 94.5% memory stall and redundant transcendental ops. Smem layout must be warp_id*sliceSize+j to avoid inter-warp aliasing; within-warp accesses have no bank conflicts since warp.thread_rank() strides by warp.size(). Risk: if sliceSize*8*4 > 48KB (i.e., sliceSize > 1536) smem overflows per block; add a static_assert or runtime guard and fall back for oversized slices.

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
