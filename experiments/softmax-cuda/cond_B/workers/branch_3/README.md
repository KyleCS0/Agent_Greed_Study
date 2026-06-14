# Worker Branch 3: softmax-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Apply float4 vectorized loads and stores to all three passes of the existing softMax2 kernel. sliceSize=784=196*4 divides exactly by 4; input is allocated with aligned_alloc(1024), guaranteeing 16-byte (float4) alignment. Steps: (1) Add a `const float4* src4 = reinterpret_cast<const float4*>(src)` and `float4* dest4 = reinterpret_cast<float4*>(dest)` in the kernel. (2) Rewrite pass 1 (max reduction): loop `for (int j = warp.thread_rank(); j < sliceSize/4; j += warp.size())`, load `float4 v = src4[i*(sliceSize/4) + j]`, update max_ from all 4 components. (3) Rewrite pass 2 (exp+sum): same loop pattern, load float4, accumulate sum += expf(v.x-max_) + expf(v.y-max_) + expf(v.z-max_) + expf(v.w-max_). (4) Rewrite pass 3 (normalize write): same loop, load float4 from src4, compute output float4 with all 4 components divided by sum, store via dest4. Target bottleneck: memory transaction count—float4 loads reduce the number of issued load instructions by 4x, improving instruction-level throughput and memory controller efficiency. Each warp thread now covers 4 elements per loop iteration. Correctness risk: low—only requires sliceSize divisible by 4 (confirmed: 784/4=196) and proper alignment (confirmed). Performance risk: low; this is a pure mechanical transformation. Expected gain: 10–30% by reducing load overhead and improving warp issue efficiency (currently 0.9% warp issue selected rate is very low, indicating instruction bottleneck from many scalar loads).

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
