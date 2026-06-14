# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Changed block from (32,4) to (32,8), grid from (16,16) to (8,8). Replaced 2D col/row loop with linearized pixel loop with 4-pixel unrolling (stride-based). Added __launch_bounds__(256, 2). Added bounds check inside unrolled loop.
- Status: correct
- Speedup: 1.0754
- Profile backend: ncu
- What I learned: Global load efficiency jumped from 57% to 100% with the linearized access pattern. Occupancy held at ~16.7%. The 4-pixel unrolling improved coalescing significantly.
- Best speedup so far: 1.0754
- Next step: Try increasing unroll factor to 8 pixels per thread.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Increased unroll factor from 4 to 8 pixels per thread (stride * 8 outer loop, unroll 8 inner).
- Status: correct
- Speedup: 1.09079
- Profile backend: ncu
- What I learned: Going from 4 to 8 pixels per thread gave a small additional gain. More work per thread reduces loop overhead.
- Best speedup so far: 1.09079
- Next step: Try 16 pixels per thread.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Increased unroll factor from 8 to 16 pixels per thread.
- Status: correct
- Speedup: 1.09083
- Profile backend: ncu
- What I learned: Marginal improvement going from 8 to 16. Diminishing returns on unroll factor alone. Grid size may be the bigger lever.
- Best speedup so far: 1.09083
- Next step: Try 32 pixels per thread.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Increased unroll factor from 16 to 32 pixels per thread.
- Status: correct
- Speedup: 1.0892
- Profile backend: ncu
- What I learned: 32 pixels/thread is slightly worse than 16. The optimal unroll is around 16. Reverted back to 16 and try tuning grid size instead.
- Best speedup so far: 1.09083
- Next step: Keep 16-pixel unroll, try larger grid (16,8) = 128 blocks for more parallelism.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Reverted to 16-pixel unrolling; changed grid from (8,8)=64 blocks to (16,8)=128 blocks.
- Status: correct
- Speedup: 1.46435
- Profile backend: ncu
- What I learned: Major speedup by using more blocks (128 vs 64). More blocks allows more SM utilization. The accum second pass also becomes more parallelized. This is the biggest win so far.
- Best speedup so far: 1.46435
- Next step: Try grid(16,16)=256 blocks.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Changed grid from (16,8)=128 blocks to (16,16)=256 blocks with 16-pixel unrolling.
- Status: correct
- Speedup: 1.42955
- Profile backend: ncu
- What I learned: 256 blocks is slightly worse than 128 blocks. The smem atomic contention increases with more blocks sharing fewer pixels each, or the accum phase overhead grows. Best is grid(16,8)=128 blocks.
- Best speedup so far: 1.46435
- Next step: Lock in the best config grid(16,8) with 16-pixel unrolling and run final iteration to complete 7 successful runs.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Same as attempt 5 (grid(16,8), block(32,8), 16-pixel unrolling) - confirming best config.
- Status: correct
- Speedup: 1.46391
- Profile backend: ncu
- What I learned: Configuration is stable at ~1.464x speedup. Final best: block(32,8), grid(16,8), 16-pixel linearized unrolled loop with bounds checks, __launch_bounds__(256,2).
- Best speedup so far: 1.46435
- Next step: All 7 successful iterations complete.
