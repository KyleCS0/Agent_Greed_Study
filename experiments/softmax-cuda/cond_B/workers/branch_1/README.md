# Worker Branch 1: softmax-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Implement online (single-pass) softmax to eliminate one full global read pass, combined with float4 vectorized loads. Currently softMax2 makes 3 separate warp-strided passes over global memory (find max, compute exp+sum, normalize), causing 94.4% memory-latency stalls. Steps: (1) In softMax2, replace the first two passes with a single warp-strided online-softmax loop: for each float4 chunk (sliceSize=784=196*4, exact), load 4 floats at once via `reinterpret_cast<const float4*>(src)[i*196 + lane*step + chunk]`, then for each of the 4 values apply the online rescaling update: given new element x, let m_new = max(m_old, x), s_new = s_old * expf(m_old - m_new) + expf(x - m_new). After the loop, warp-reduce m and s using cg::reduce. (2) Replace the final normalize pass with a warp-strided float4 store loop writing expf(x - max_) / sum. (3) Update the main launch configuration accordingly (grids/blocks unchanged). Target bottleneck: the 3x global memory read passes for 600k*784 floats; reducing to 2 passes (one combined max+sum scan, one write-back) cuts global load traffic by ~33%. Correctness risk: the online rescaling formula for merging partial (max, sum) pairs across warp lanes must use the standard compensated-sum formula—test against CPU reference at tolerance 1e-3. Performance risk: online rescaling adds extra expf calls per element in pass 1, but these are cheap relative to global memory latency; net win is expected since memory stalls dominate at 94.4%.

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
