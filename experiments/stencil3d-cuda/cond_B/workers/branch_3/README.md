# Worker Branch 3: stencil3d-cuda Condition B

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Reduce __syncthreads() count from 4 to 2 per x-iteration using warp shuffle for y/z neighbor communication. Currently sm_psi[3] is used as a scratch buffer twice per loop: once for ycharge (needs sync before neighboring thread reads sm_psi[3][tjj-1][tkk]) and once for zcharge (needs sync before reading sm_psi[3][tjj][tkk-1]). Replace these two shared-memory roundtrips with warp-level shuffle: with blockDim = (BSIZE=16, BSIZE=16), each warp of 32 threads covers lanes (tjj, tkk) = {(even_row, 0..15), (odd_row, 0..15)}. For the y-direction exchange, use '__shfl_down_sync(0xffffffff, ycharge, BSIZE)' to send lane [tjj][tkk]'s ycharge down to lane [tjj+1][tkk] within the warp without any syncthreads; still write to shared memory only for inter-warp boundaries (one row per warp boundary). For z-direction, use '__shfl_down_sync(0xffffffff, zcharge, 1)' for intra-warp left-neighbor transfer; only shared memory needed at warp boundaries (tkk==0 threads). Guard all shuffles with proper lane masks. Carefully preserve the original boundary conditions (tjj>0, tkk>0 guards). This targets the dominant 47% barrier stall. High complexity—test correctness thoroughly with small sizes before scaling.

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
