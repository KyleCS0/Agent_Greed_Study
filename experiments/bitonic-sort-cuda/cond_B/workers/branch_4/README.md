# Worker Branch 4: bitonic-sort-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Improve global memory coalescing and load efficiency (currently 50%) by rewriting the index computation so that threads within a warp always access consecutive memory locations. The current kernel computes swapped_ele = i + h_len, which for large seq_len causes a thread accessing index i to pair with i+h_len that is far away and in a different cache line. Restructure the launch so that for each stage, threads are assigned to work on the low-half indices in a coalesced fashion: thread k handles element k and element k XOR (seq_len/2), which for power-of-two seq_len is equivalent but allows the grid to be partitioned so consecutive threads always load consecutive addresses in the low half. Concretely, rewrite the thread index as: int half_idx = blockDim.x * blockIdx.x + threadIdx.x; int block_in_seq = half_idx / h_len; int pos_in_half = half_idx % h_len; int i = block_in_seq * seq_len + pos_in_half; int j = i + h_len. This keeps threads in a warp addressing i values that differ by 1 (coalesced), improving the 50% load efficiency toward 100%. Launch size/(2*BLOCK_SIZE) blocks. Target bottleneck: 50% global load efficiency causing wasted memory bandwidth. Risk: the restructuring must keep the seq_num/two_power/increasing logic correct; test with small n first.

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
