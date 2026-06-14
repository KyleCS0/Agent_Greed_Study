# Worker Branch 2: softmax-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Cache the entire slice in shared memory to reduce global memory reads from 3 passes to 1 pass. Steps: (1) Change the softMax2 kernel signature to accept dynamic shared memory: declare `extern __shared__ float smem[]` and assign each warp a contiguous 784-float region via `float* ws = smem + warp.meta_group_rank() * sliceSize`. (2) Pass 1 (global→smem): warp-strided float4 loads copy the slice into ws[], simultaneously finding the warp-local max. Warp-reduce for final max_. (3) Pass 2 (smem only): warp-strided loop over ws[] computing expf(ws[j] - max_) in-place and accumulating sum. Warp-reduce for final sum. (4) Pass 3 (smem→global): warp-strided float4 stores write ws[j]/sum to dest. (5) Update the kernel launch to pass dynamic smem size: `softMax2<<<grids, blocks, (BLOCK_SIZE/32)*sliceSize*sizeof(float)>>>`. For BLOCK_SIZE=256 and sliceSize=784: 8*784*4=25,088 bytes per block, well within RTX 3080 Ti's default 48 KB. Target bottleneck: global memory latency on 3 read passes; this plan reduces to 1 global read pass + 1 write pass, cutting load traffic by 3x. Correctness risk: shared memory indexing must be warp-local (offset by meta_group_rank()*sliceSize); verify no bank conflicts on stride-1 access pattern. Performance risk: reduced occupancy from 25 KB smem per block (~2 concurrent blocks per SM vs current higher occupancy)—net outcome depends on whether memory-latency hiding from ILP outweighs occupancy loss, but given 94.4% memory-stall rate the bandwidth reduction should dominate.

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
