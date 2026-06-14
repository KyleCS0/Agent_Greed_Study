# Worker Branch 5: softmax-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Tune launch configuration and add compiler unroll hints to improve warp issue efficiency and instruction-level parallelism. Steps: (1) Change BLOCK_SIZE from 256 to 512 (16 warps per block, 16 slices per block) so the grid shrinks from 75000 blocks to 37500, reducing launch overhead and improving SM utilization with more in-flight warps per SM. Update grids: `dim3 grids((numSlice + BLOCK_SIZE/32 - 1) / (BLOCK_SIZE/32))`. (2) Add `#pragma unroll 4` before each of the three warp-stride loops in softMax2 to let the compiler prefetch and overlap memory loads. (3) Add `__restrict__` to the src and dest pointer parameters so the compiler can assume no aliasing and generate better load/store scheduling. (4) In pass 1, replace the loop initializer `float max_ = src[i*sliceSize]` with `float max_ = -FLT_MAX` so initialization is uniform across all threads (avoids one redundant conditional load). (5) Ensure the kernel is compiled with `-arch=sm_86` (RTX 3080 Ti is Ampere sm_86) rather than the current sm_60, which enables Ampere-specific warp scheduling and async copy instructions. Target bottleneck: the 0.9% warp issue selected rate indicates the warp scheduler is mostly idle—larger blocks and unrolling give it more independent instructions to issue. Correctness risk: low; __restrict__ is only safe if src != dest (guaranteed by separate cudaMalloc calls). Performance risk: larger blocks may increase register pressure and reduce occupancy if registers exceed 65536 per SM; verify ptxas output stays near 19 regs/thread.

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
