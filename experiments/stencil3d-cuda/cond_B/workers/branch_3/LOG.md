# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Replaced 3 of 6 per-loop __syncthreads() with warp shuffles. y-direction: odd-tjj rows write to sm_psi[3]; odd-tjj sinks use __shfl_up_sync(..., BSIZE) intra-warp; even-tjj sinks read cross-warp from sm_psi[3]. z-direction: fully eliminated shared mem; use __shfl_up_sync(..., 1) for all tkk>0. Reduced from 6 syncs/iter to 3 syncs/iter.
- Status: correct
- Speedup: 2.1914
- Profile backend: ncu
- What I learned: Occupancy improved 79.6%→94.9% (regs 40→48); barrier stall 47%→43%; memory stall 27.8%→33%. Speedup gain modest (~0.01). Barrier still dominant.
- Best speedup so far: 2.1914
- Next step: Eliminate one more sync via preloading: write psi(ii+2) into the pii slot at end of iteration so Sync 1 (top-of-loop psi load fence) is merged into the end-of-iteration sync.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Preload psi(ii+2) into the pii slot (no longer read after Sync A) before Sync B, merging the former top-of-loop Sync 1 into Sync B. Reduced from 3 to 2 syncs per loop iteration.
- Status: correct
- Speedup: 2.2020
- Profile backend: ncu
- What I learned: Barrier stall 43.1%→38.8%; registers stayed 40; occupancy 94.8%; memory stall 38.4%. Barrier and memory now roughly equal. Good structural improvement.
- Best speedup so far: 2.2020
- Next step: Reorder z-face computation before y-face so sigmaZ reads are issued earlier (before Sync A), helping hide latency.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Moved z-face computation before y-face so sigmaZ reads start earlier, then z-subtraction via shuffle right after Sync A before y-subtraction.
- Status: correct
- Speedup: 2.2011
- Profile backend: ncu
- What I learned: No meaningful change (within noise). Compiler scheduling likely already handles this reordering internally.
- Best speedup so far: 2.2020 (attempt 2)
- Next step: Try XTILE=28 to see if larger x-tile helps amortize fixed costs or improves instruction scheduling.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: XTILE 20→28 (larger x-tile per block, fewer total blocks, more work per block).
- Status: correct
- Speedup: 2.2136
- Profile backend: ncu
- What I learned: Slightly better (2.214 vs 2.202). Barrier 39%, memory 39.6%, occupancy 94.8%, regs 40 — profile unchanged but actual time improved slightly.
- Best speedup so far: 2.2136
- Next step: Try XTILE=32 to see if the trend continues.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: XTILE 28→32.
- Status: correct
- Speedup: 2.2980
- Profile backend: ncu
- What I learned: Big jump from 2.214→2.298. Occupancy 93.4%, barrier 38.4%, memory 39.1%, regs 40 unchanged. Larger x-tiles significantly reduce effective kernel overhead.
- Best speedup so far: 2.2980
- Next step: Try XTILE=40 to see if trend continues.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: XTILE 32→40.
- Status: correct
- Speedup: 2.2545
- Profile backend: ncu
- What I learned: XTILE=40 is worse than 32 (2.255 vs 2.298). XTILE=32 is the sweet spot — 40 likely causes under-utilization (fewer blocks, not enough waves to saturate the GPU).
- Best speedup so far: 2.2980 (attempt 5, XTILE=32)
- Next step: Revert to XTILE=32 (best source) for final iteration 7.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: XTILE 40→32 (reverting to best-performing source).
- Status: correct
- Speedup: 2.2970
- Profile backend: ncu
- What I learned: Confirms XTILE=32 is the sweet spot. Final best speedup 2.297 vs planner baseline 2.179.
- Best speedup so far: 2.2980 (attempt 5)
- Next step: All 7 successful iterations complete.
