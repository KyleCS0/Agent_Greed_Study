# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Restructured kernel to use separate `sm_ycharge[BSIZE][BSIZE+1]` and `sm_zcharge[BSIZE+1][BSIZE]` shared arrays instead of reusing `sm_psi[3]`. Changed `sm_psi` from `[4][BSIZE][BSIZE]` to `[3][BSIZE][BSIZE+1]` (removing unused 4th layer, adding row padding). Reduced syncs per iteration from 5 to 3 by computing both y and z face charges before a single sync, then reading both neighbors in one conditional.
- Status: correct
- Speedup: 2.14431
- Profile backend: ncu
- What I learned: Occupancy jumped from 79.6% to 95.2% (registers dropped 40→39). Barrier stalls dropped from 47.0% to 38.3%. Bank conflicts increased from 665K to 852K (fundamental to BSIZE=16 warp layout). Speedup slightly below planner's 2.183 despite better occupancy — bank conflicts offset the barrier reduction.
- Best speedup so far: 2.14431
- Next step: Try fixing sm_zcharge inner-dim padding to reduce bank conflicts.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Changed `sm_zcharge` from `[BSIZE+1][BSIZE]` to `[BSIZE][BSIZE+1]` to add padding to the inner (fast) dimension for better bank alignment.
- Status: correct
- Speedup: 2.14180
- Profile backend: ncu
- What I learned: Bank conflicts didn't improve (855K vs 852K). With BSIZE=16, a warp spans two rows — bank conflicts between the two halves are fundamental regardless of inner-dim padding. Registers went from 39 to 40. Speedup essentially the same (noise level).
- Best speedup so far: 2.14431
- Next step: Try software pipelining to overlap global sm_psi load with x-face computation.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Pipelined the sm_psi load: preloaded `psi(2)` in init section, then in the loop issued `sm_psi[pii] = psi(ii+2)` after sync B (overlapping with neighbor reads and x-face) instead of loading at loop start. Reduced from 3 syncs/iteration to 2.
- Status: correct
- Speedup: 2.12932
- Profile backend: ncu
- What I learned: Registers dropped to 32 (from 40), barrier stalls dropped to 31.8%, but bank conflicts rose to 982K and short-dep stalls rose to 17.4%. Overall slower (2.575ms vs 2.557ms). The compiler rescheduled code with fewer registers causing spills or other effects, and the interleaved preload writes increased bank conflicts.
- Best speedup so far: 2.14431
- Next step: Revert pipelining, try removing the rotation sync (sync C) which should be safe since x-face doesn't read sm_psi[pii].

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Removed pipelining (reverted to load-at-start), removed `sm_psi[pii]` preload in init, and eliminated the rotation sync (sync C). The x-face only reads V1/V2 (cii/nii slots), not V0 (pii), so the next iter's load into pii is safe without sync C.
- Status: correct
- Speedup: 2.13512
- Profile backend: ncu
- What I learned: Barrier stalls dropped to 31.8% (same as pipelining), but bank conflicts rose to 921K and short-dep stalls rose to 21.0%. Without sync C, different warps can be at different loop stages simultaneously, increasing cross-warp smem bank conflicts. Net result slightly slower. The rotation sync does help with bank conflict avoidance.
- Best speedup so far: 2.14431
- Next step: Add sync C back to restore best performance, then explore other optimizations.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Restored the rotation sync (`__syncthreads()` before the index rotation). This returns to the 3-sync-per-iteration structure from attempts 1/2, with sm_zcharge[BSIZE][BSIZE+1] padding.
- Status: correct
- Speedup: 2.14263
- Profile backend: ncu
- What I learned: Confirmed that 3 syncs per iteration with separate face arrays (sm_ycharge, sm_zcharge) is the sweet spot. This approach reduces barrier stalls from 47.0% (baseline) to ~38% while keeping bank conflicts and short-dep stalls in check.
- Best speedup so far: 2.14431
- Next step: Try XTILE increase or other optimizations for the remaining 2 iterations.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Increased `XTILE` from 20 to 24. This reduces the number of x-blocks from 13 to 11 for nx=256, giving each block 24 main-loop iterations (nLast_x=25) instead of 20 (nLast_x=21), amortizing init overhead over more work.
- Status: correct
- Speedup: 2.17321
- Profile backend: ncu
- What I learned: Speedup improved significantly (2.144→2.173). Bank conflicts dropped slightly (835K vs 855K). Memory stalls decreased (25.3% vs 26.0%). Larger XTILE improves cache reuse for sigma arrays across more x-iterations and reduces block-launch overhead. Approaches the planner's 2.183 speedup.
- Best speedup so far: 2.17321
- Next step: Try XTILE=32 which gives near-perfect load balance (31 vs 32 iterations for boundary vs regular blocks).

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Increased `XTILE` from 24 to 32. With nx=256, this gives bdimx=8 blocks, non-boundary blocks do 32 iterations and boundary block does 31 — nearly perfect load balance.
- Status: correct
- Speedup: 2.20378
- Profile backend: ncu
- What I learned: Speedup improved further to 2.204, exceeding the planner's 2.183 reference. Memory stalls dropped to 23.5% (from 25.3%), showing better sigma cache reuse with 32-iteration blocks. Bank conflicts 840K. The bound hint changed to "synchronization/barrier limited" (from "memory-latency limited"), showing the barrier bottleneck is now dominant. XTILE=32 is the best configuration found.
- Best speedup so far: 2.20378
- Next step: Task complete — 7 successful iterations achieved.
