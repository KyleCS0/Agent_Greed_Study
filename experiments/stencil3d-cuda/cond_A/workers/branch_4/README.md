# Worker Branch 4: stencil3d-cuda Condition A

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Interleave the sigma array layout from direction-major to point-major to improve global load coalescing. Target bottleneck: global load efficiency is 80.5% (below the ~85% threshold), indicating wasted transactions. Each face-current calculation issues 3 sigma reads with direction as the outermost stride: `d_sigmaX[z + nz*(y + ny*(x + nx*dir))]` for dir=0,1,2. These three accesses are separated by nx*ny*nz doubles (= 256^3 = 16M doubles = 128 MB apart), causing three independent cache-line fetches per thread that cannot coalesce. Fix: change the sigma layout to direction-innermost: `sigma_packed[z + nz*(y + ny*(x + nx*3 + dir))]` so the 3 direction components for any (x,y,z) are contiguous in memory. Steps: (1) In main(), allocate d_sigma as before (9*vol doubles) but fill h_sigma with interleaved order: `h_sigma[(z + nz*(y + ny*x))*3 + dir] = value`. (2) Pass a single `d_sigma` pointer to the kernel and update the sigmaX/Y/Z macros to index as `d_sigma[(z + nz*(y + ny*(x + nx*3 + dir))) + OFFSET]` where OFFSET is 0, 3*vol, 6*vol respectively, or collapse all three into one macro family. (3) Alternatively, use a struct-of-arrays-to-array-of-structs transformation so each grid point stores its 9 sigma values contiguously. The 3 direction reads per face current then come from adjacent cache lines and can be served by 1-2 cache line fetches instead of 3 distant ones. Correctness risk: careful index arithmetic is needed; validate against a small known-output run before measuring. Performance risk: modest improvement expected (efficiency from 80.5% toward ~95%).

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
