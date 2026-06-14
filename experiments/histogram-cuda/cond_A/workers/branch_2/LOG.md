# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Added `__launch_bounds__(128, 4)` to `histogram_smem_atomics` kernel to hint compiler to reduce register usage and increase occupancy.
- Status: correct
- Speedup: 0.9982
- Profile backend: ncu
- What I learned: The `__launch_bounds__(128, 4)` hint did not reduce register count (still 30/thread). Compiler already below any meaningful cap. Occupancy unchanged at 16.5%. The GPU is an RTX 4090 (128 SMs), but code compiled for sm_60. With 256 blocks on 128 SMs, only ~2 blocks/SM = low occupancy per SM.
- Best speedup so far: 0.9982
- Next step: Try `__launch_bounds__(128, 6)` to push harder.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Changed launch bounds to `__launch_bounds__(128, 6)`.
- Status: correct
- Speedup: 0.9984
- Profile backend: ncu
- What I learned: Still no register reduction. The real bottleneck is that with 256 blocks on 128 SMs, there are only 2 blocks/SM. The fix is more threads per block, not launch bounds tuning.
- Best speedup so far: 0.9984
- Next step: Revert launch_bounds and try larger thread block (32x8=256 threads).

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Kept launch_bounds(128,6), increased grid from 16x16 to 32x32 (1024 blocks total).
- Status: correct
- Speedup: 0.6057
- Profile backend: ncu
- What I learned: More blocks slows things down because the accumulation kernel has to sum 1024 partial histograms instead of 256, adding significant overhead. Grid expansion is not the right approach.
- Best speedup so far: 0.9984
- Next step: Revert grid to 16x16 and increase block size from 128 to 256 threads (32x8).

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Removed launch_bounds, reverted grid to 16x16, changed block from 32x4 (128 threads) to 32x8 (256 threads).
- Status: correct
- Speedup: 1.2980
- Profile backend: ncu
- What I learned: Doubling threads per block to 256 increases warps/block and allows better latency hiding within each block on the RTX 4090. Significant improvement.
- Best speedup so far: 1.2980
- Next step: Try even larger block of 512 threads (32x16) to further increase occupancy.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Changed block from 32x8 (256 threads) to 32x16 (512 threads).
- Status: correct
- Speedup: 1.5208
- Profile backend: ncu
- What I learned: 512 threads/block gives 1.52x speedup. With 256 blocks on 128 SMs = 2 blocks/SM x 512 threads = 1024 threads = 32 warps per SM = ~50% theoretical occupancy on sm_89. Much better latency hiding.
- Best speedup so far: 1.5208
- Next step: Try 1024 threads/block (32x32) to see if even more warps helps.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Changed block from 32x16 (512 threads) to 32x32 (1024 threads).
- Status: correct
- Speedup: 1.5184
- Profile backend: ncu
- What I learned: 1024 threads/block is marginally worse than 512 threads/block. Fewer blocks can be resident per SM. 512-thread config remains best.
- Best speedup so far: 1.5208 (attempt 5, block 32x16)
- Next step: Stay with 32x16 block and try increasing accum kernel block size to 256 for faster second pass.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Reverted block to 32x16 (512 threads), increased accumulation kernel block size (block2) from 128 to 256.
- Status: correct
- Speedup: 1.5014
- Profile backend: ncu
- What I learned: Larger accumulation block (256) is slightly slower. The second-pass accumulation is not the bottleneck. Best configuration remains block(32,16)/grid(16,16) with block2=128, giving 1.52x speedup.
- Best speedup so far: 1.5208 (attempt 5)
- Next step: N/A - 7 successful iterations complete.
