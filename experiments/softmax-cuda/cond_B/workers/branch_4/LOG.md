# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Implemented the assigned plan: added `extern __shared__ float exp_smem[]`, per-warp smem region `we = exp_smem + warp.meta_group_rank() * sliceSize`, pass 2 stores expf values to smem, pass 3 reads from smem (no global re-read, no re-expf). Launched with dynamic smem `(BLOCK_SIZE/32)*sliceSize*sizeof(float)` = 25,088 bytes.
- Status: correct
- Speedup: 1.51291
- Profile backend: ncu
- What I learned: Smem caching of exp values eliminates the 3rd global read pass and all expf calls in pass 3, giving ~1.51x speedup. Occupancy dropped from 74.3% to 32.9% due to smem usage. Bank conflicts appeared (1.47M load, 0.67M store). Still 92.5% memory-stall bound.
- Best speedup so far: 1.51291
- Next step: Try padding smem region per warp to reduce bank conflicts.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Padded per-warp smem stride to `(sliceSize+31)&~31 = 800` to align warp regions to 32-element boundaries and reduce bank conflicts.
- Status: correct
- Speedup: 1.50657
- Profile backend: ncu
- What I learned: Bank conflicts reduced from 1.47M to 1.0M (load), but speedup slightly worse (4.545 ms vs 4.526 ms median). Padding adds extra smem but the benefit of fewer conflicts doesn't outweigh the overhead. Reverted to no-padding for subsequent attempts.
- Best speedup so far: 1.51291
- Next step: Try __ldg read-only cache hints.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Reverted padding; added `__ldg()` intrinsic for all global src reads to use the read-only texture cache path.
- Status: correct
- Speedup: 1.51296
- Profile backend: ncu
- What I learned: `__ldg()` matches best speedup (1.513) with lower timing stddev (0.0034 vs 0.023). The compiler with `-O3 --use_fast_math` likely already optimizes const pointer loads similarly. Essentially tied with attempt 1.
- Best speedup so far: 1.51296
- Next step: Try float4 vectorized loads to reduce memory transaction count.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Used `float4` vectorized global loads in passes 1 and 2, iterating over n4=sliceSize/4 float4 elements per warp.
- Status: correct
- Speedup: 1.51148
- Profile backend: ncu
- What I learned: Float4 loads caused massive smem store bank conflicts (44M vs 0.7M) because the `we[j*4+k]` write pattern places 4-element groups at indices that alias the same 32 banks for every 8 threads. Speedup slightly worse. Reverted to scalar loads.
- Best speedup so far: 1.51296
- Next step: Try online softmax (no smem) to increase occupancy.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Replaced smem approach with online softmax: single global-read pass that computes (max, sum) pairs using the pairwise online update rule with warp shuffle, then a second pass writes normalized output. No smem used.
- Status: correct
- Speedup: 1.32649
- Profile backend: ncu
- What I learned: Online softmax is significantly slower despite zero smem (higher occupancy). The extra expf calls in the online pass (2 per element instead of 1) dominate because expf is expensive even when the kernel is memory-latency limited. Reverted to smem approach.
- Best speedup so far: 1.51296
- Next step: Revert to best source; try hoisting row base address pointer.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Reverted to smem+__ldg approach; hoisted `row_src = src + i*sliceSize` and `row_dst = dest + i*sliceSize` to reduce repeated multiply-add in loop bodies.
- Status: correct
- Speedup: 1.51335
- Profile backend: ncu
- What I learned: Pointer hoisting gives essentially the same speedup as best (1.513). The compiler likely already performed this optimization, so no measurable gain. Warp issue selected improved to 2.4%.
- Best speedup so far: 1.51335
- Next step: Add __restrict__ to kernel params as final attempt.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Added `__restrict__` qualifier to `src` and `dest` kernel parameters to eliminate any alias analysis overhead and allow better code generation.
- Status: correct
- Speedup: 1.50769
- Profile backend: ncu
- What I learned: `__restrict__` gave no significant improvement (1.508 vs 1.513 best, within noise). CUDA const pointers already imply no-alias for the compiler in most cases. The kernel remains memory-latency bound at ~92% stall. The smem exp-cache plan achieved consistent ~1.51x speedup across all variants.
- Best speedup so far: 1.51335 (attempt 6)
