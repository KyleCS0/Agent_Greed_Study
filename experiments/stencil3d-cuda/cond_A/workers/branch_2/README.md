# Worker Branch 2: stencil3d-cuda Condition A

## Mission

You are the Worker agent. Optimize this kernel according to the assigned plan below.

Complete exactly 7 successful iterations. A successful iteration means `./src/run.sh` finishes and `out/latest_run.json` reports `status: "correct"`. Failed attempts do not count toward the 7 successful iterations.

## Assigned Plan

Halve the number of __syncthreads() calls per x-iteration from 4 to 2 by introducing separate shared-memory arrays for y-face and z-face charge communication. Target bottleneck: barrier stalls account for 47.0% of all warp stalls, the single largest bottleneck. Currently the loop reuses sm_psi[3] for both ycharge and zcharge with a write-sync-read-sync pattern each, totalling 4 barriers per x-step. Restructure as follows: (1) Add two new shared arrays `__shared__ Real sm_ycharge[BSIZE][BSIZE+1]` and `__shared__ Real sm_zcharge[BSIZE+1][BSIZE]` (padding chosen so each array's row stride in banks is odd, eliminating conflicts). (2) In the loop body, compute both ycharge (condition: tkk>0 && tkk<nLast_z && tjj<nLast_y) and zcharge (condition: tkk<nLast_z && tjj>0 && tjj<nLast_y) sequentially before any barrier; store ycharge to sm_ycharge[tjj][tkk] and zcharge to sm_zcharge[tjj][tkk]. (3) Issue a single __syncthreads(). (4) Read sm_ycharge[tjj-1][tkk] and sm_zcharge[tjj][tkk-1] in a single conditional, updating dV. (5) Issue a single __syncthreads() before the next data load. Also keep the final __syncthreads() before the index rotation (pii/cii/nii swap). Total smem budget: 3*16*17*8 + 16*17*8 + 17*16*8 = 10880 bytes. Correctness risk: verify that the combined conditionals for the two face currents cover the same output cells as before, particularly the asymmetry in tjj/tkk bounds. Performance risk: slightly more register usage from holding both ycharge and zcharge live simultaneously; check ptxas register count and ensure occupancy does not drop below current 79.6%.

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
