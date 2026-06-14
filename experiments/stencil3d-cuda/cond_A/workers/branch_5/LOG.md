# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Changed `#define XTILE 20` to `#define XTILE 32`
- Status: correct
- Speedup: 2.2817
- Profile backend: ncu
- What I learned: Occupancy jumped from 79.6% to 93.2%; registers stayed at 40/thread; barrier stalls slightly down (47.0%→46.6%); short-dep stalls down (17.3%→16.1%). Good improvement with no register spill.
- Best speedup so far: 2.2817
- Next step: Try XTILE=40 since registers are still 40 and there is headroom.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Changed `#define XTILE 32` to `#define XTILE 40`
- Status: correct
- Speedup: 2.2271
- Profile backend: ncu
- What I learned: XTILE=40 is worse than 32 (2.227 vs 2.282). The larger tile likely adds more per-iteration memory pressure than the L2 reuse gains. Registers stay at 40/thread.
- Best speedup so far: 2.2817 (XTILE=32)
- Next step: Revert to XTILE=32 (best). Try XTILE=36 to see if there's a sweet spot between 32 and 40.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Changed XTILE to 36 (between 32 and 40)
- Status: correct
- Speedup: 2.2732
- Profile backend: ncu
- What I learned: XTILE=36 occupancy drops to 78.4% and speedup is 2.273, worse than XTILE=32. The 256-cell grid divides more cleanly by 32 (8 blocks) than 36 (7.1 → 8 blocks with partial last block). XTILE=32 remains the sweet spot.
- Best speedup so far: 2.2817 (XTILE=32)
- Next step: Revert to XTILE=32 and try removing redundant __syncthreads() (sync5 after z-neighbor read and sync6 after x-face) to reduce barrier stalls from 46.6%.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: XTILE=32; removed sync after z-neighbor read and sync after x-face compute (2 of 6 syncs per iteration were redundant — no shared memory writes follow either)
- Status: correct
- Speedup: 2.3096
- Profile backend: ncu
- What I learned: Barrier stalls dropped 46.6%→43.3%, short-dep stalls 16.1%→15.1%. Registers still 40. Occupancy 92.7%. New best speedup 2.310.
- Best speedup so far: 2.3096 (XTILE=32, 4 syncs/iter)
- Next step: Try padding smem rows by 1 (sm_psi[4][BSIZE][BSIZE+1]) to eliminate ~660K load bank conflicts from y/z-neighbor column reads.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Added +1 smem z-padding: sm_psi[4][BSIZE][BSIZE] → sm_psi[4][BSIZE][BSIZE+1]
- Status: correct
- Speedup: 2.3086
- Profile backend: ncu
- What I learned: Bank conflict count unchanged (660404) — conflicts are structural (warp spans 2 rows; row stride = 32 banks so same-column elements land in same bank regardless of padding). Padding is neutral. Compiler reduced regs/thread from 40 to 39 with larger smem.
- Best speedup so far: 2.3096 (attempt 4: XTILE=32, 4 syncs, no padding)
- Next step: From current source, add `#pragma unroll 4` on the x-loop to reduce loop-overhead and improve instruction scheduling.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added `#pragma unroll 4` on the x-loop (XTILE=32 iterations unrolled by 4)
- Status: correct
- Speedup: 2.3184
- Profile backend: ncu
- What I learned: Registers jumped from 39 to 48 with unrolling, but occupancy held at 92.6%. Short-dep stalls dropped from 14.7% to 13.6%. Barrier stalls slightly up (43.3%→43.9%) but overall faster. New best.
- Best speedup so far: 2.3184 (XTILE=32, 4 syncs, BSIZE+1 padding, unroll 4)
- Next step: Try #pragma unroll 8 to see if more aggressive unrolling further reduces short-dep stalls without excessive register spill.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Changed `#pragma unroll 4` to `#pragma unroll 8` on the x-loop
- Status: correct
- Speedup: 2.3086
- Profile backend: ncu
- What I learned: Unroll 8 gives the same 48 regs and 92.7% occupancy as unroll 4, but slightly worse speedup (2.309 vs 2.318). The unroll-4 sweet spot provides the best balance of loop overhead reduction vs instruction scheduling. Unroll 8 may cause worse instruction cache pressure at the cost of loop overhead.
- Best speedup so far: 2.3184 (attempt 6: XTILE=32, 4 syncs, BSIZE+1 padding, unroll 4)
- Next step: 7 successful iterations complete. Best configuration is attempt 6.
