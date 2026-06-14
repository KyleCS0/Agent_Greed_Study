# Worker Branch 5: bitonic-sort-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Use __ldg() read-only cache intrinsics for the array reads and apply loop unrolling pragmas to reduce instruction overhead. Since the array is read and conditionally written, mark read accesses with __ldg(&a[i]) and __ldg(&a[swapped_ele]) to route loads through the 128-byte read-only (texture) cache path, which has separate bandwidth from L1/L2 and can improve effective cache hit rate for the access pattern. Add #pragma unroll to any inner loops and use __builtin_expect for the branch hint on the swap condition. Additionally, precompute seq_len as a power-of-two and use bitwise operations (i >> stage, i & (h_len-1)) instead of integer division to compute seq_num and h_len faster. Mark the kernel with __launch_bounds__(BLOCK_SIZE, 2) to hint the compiler to limit register use and increase occupancy beyond the current 80.2%. Target bottleneck: 15.9% wait stalls and 5.0% short-dependency stalls from instruction latency. Risk: __ldg() requires the pointer to be genuinely read-only for the duration of the kernel; since a[] is both read and written within the same kernel, using __ldg() may produce incorrect results if a thread reads a value already written by another thread in the same launch. Only apply __ldg() if analysis confirms no intra-kernel RAW hazards (in bitonic sort each kernel launch has no such hazards since each element pair is touched by exactly one thread). Correctness is safe per-launch.

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
