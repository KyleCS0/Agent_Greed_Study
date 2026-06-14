# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: BLOCK_SIZE=512, __launch_bounds__(512, 2), __ldg() on both global loads
- Status: correct
- Speedup: 0.948264
- Profile backend: ncu
- What I learned: BLOCK_SIZE=512 increased regs/thread from 16 to 18, reduced occupancy from 80.1% to 75.9%, and hurt performance despite more warps-per-SM. The register overhead negated the latency-hiding benefit.
- Best speedup so far: 0.948264
- Next step: Revert to BLOCK_SIZE=256; keep __ldg() and __launch_bounds__ but tune min_blocks

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: BLOCK_SIZE=256, __launch_bounds__(256, 4), __ldg() on both global loads
- Status: correct
- Speedup: 0.989722
- Profile backend: ncu
- What I learned: min_blocks=4 with __ldg() still slightly slower than baseline. The __ldg() path may not be helping much since loads are not truly read-only within a launch.
- Best speedup so far: 0.989722
- Next step: Try min_blocks=2 with __launch_bounds__(256, 2)

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: BLOCK_SIZE=256, __launch_bounds__(256, 2), __ldg() on both global loads
- Status: correct
- Speedup: 0.992442
- Profile backend: ncu
- What I learned: Slightly better with min_blocks=2 but still below baseline. __ldg() with __launch_bounds__ adds overhead or doesn't help.
- Best speedup so far: 0.992442
- Next step: Try BLOCK_SIZE=1024 as plan suggests

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: BLOCK_SIZE=1024, __launch_bounds__(1024, 2), __ldg() on both global loads
- Status: correct
- Speedup: 0.680460
- Profile backend: ncu
- What I learned: BLOCK_SIZE=1024 is much worse — significantly fewer blocks/SM, limiting parallelism. Large block sizes are not effective here.
- Best speedup so far: 0.992442
- Next step: Revert to BLOCK_SIZE=256, try __ldg() alone without __launch_bounds__

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: BLOCK_SIZE=256, no __launch_bounds__, __ldg() on both global loads
- Status: correct
- Speedup: 0.989915
- Profile backend: ncu
- What I learned: __ldg() alone slightly hurts performance. The stores happen in the same kernel launch, so __ldg() is technically unsafe (non-overlapping pairs, but same kernel launch reads stale cache).
- Best speedup so far: 0.992442
- Next step: Try __launch_bounds__(256, 2) only, no __ldg()

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: BLOCK_SIZE=256, __launch_bounds__(256, 2), original a[i]/a[swapped_ele] loads (no __ldg())
- Status: correct
- Speedup: 1.000790
- Profile backend: ncu
- What I learned: __launch_bounds__(256, 2) alone gives a small improvement by hinting the compiler to limit register pressure and allow 2+ concurrent blocks. Best result so far.
- Best speedup so far: 1.000790
- Next step: Try BLOCK_SIZE=512 without __ldg() to see if more warps help

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: BLOCK_SIZE=512, __launch_bounds__(512, 2), original loads (no __ldg())
- Status: correct
- Speedup: 0.957272
- Profile backend: ncu
- What I learned: BLOCK_SIZE=512 without __ldg() is still worse due to register increase and lower occupancy. BLOCK_SIZE=256 with __launch_bounds__(256,2) is optimal.
- Best speedup so far: 1.000790 (attempt 6)
- Next step: All 7 successful iterations complete. Reverted source to best configuration (attempt 6).
