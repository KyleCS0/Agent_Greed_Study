# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Replaced two-pass (max scan + exp-sum) softMax2 with online softmax single-pass using (running_max, running_sum) state, plus custom two-field warp reduction via __shfl_xor_sync.
- Status: correct
- Speedup: 1.5153
- Profile backend: ncu
- What I learned: Load bandwidth dropped from 1231.5 to 837.7 GB/s (~32% reduction, matching the predicted ~33% savings from merging 2 read passes into 1). Still memory-latency limited (89% stall). Registers went from 19 to 32/thread. Occupancy 76.5%.
- Best speedup so far: 1.5153
- Next step: Try __ldg for read-only loads and __restrict__ to potentially improve cache utilization.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Added __restrict__ to src/dest pointers and __ldg() for all src reads to route through read-only (texture) cache on Pascal.
- Status: correct
- Speedup: 1.5892
- Profile backend: ncu
- What I learned: __ldg helps - speedup increased from 1.515 to 1.589. Read-only cache on Pascal (sm_60) gives measurable benefit.
- Best speedup so far: 1.5892
- Next step: Try loop unrolling in the scan loop to improve ILP and hide memory latency.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Precompute inv_sum = 1.0f/sum before output loop; add #pragma unroll 4 on output loop.
- Status: correct
- Speedup: 1.6204
- Profile backend: ncu
- What I learned: Using multiply by inv_sum + unrolled output loop improved speedup from 1.589 to 1.620. Small but consistent gain.
- Best speedup so far: 1.6204
- Next step: Try unrolling the scan loop or vectorized loads.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Added #pragma unroll 4 to scan loop.
- Status: correct
- Speedup: 1.5963
- Profile backend: ncu
- What I learned: Unrolling scan loop hurts slightly (1.596 vs 1.620 best). Likely increases register pressure. Reverted to Attempt 3 source.
- Best speedup so far: 1.6204
- Next step: Try vectorized float4 loads for input reads.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Use fmaf() to fuse multiply-add in scan loop and warp reduction combiner.
- Status: correct
- Speedup: 1.6190
- Profile backend: ncu
- What I learned: fmaf gives negligible difference vs plain sum*expf+expf (within noise of 1.620). Already equivalent with --use_fast_math.
- Best speedup so far: 1.6204
- Next step: Try BLOCK_SIZE=512 to process 16 adjacent slices per block for better L2 reuse.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Changed BLOCK_SIZE from 256 to 512.
- Status: correct
- Speedup: 1.5699
- Profile backend: ncu
- What I learned: BLOCK_SIZE=512 is worse (1.570 vs 1.620). Larger blocks reduce block count on SM and may hurt scheduling. Reverting to 256.
- Best speedup so far: 1.6204
- Next step: Revert to BLOCK_SIZE=256 and try __launch_bounds__ to make compiler occupancy target explicit.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Reverted BLOCK_SIZE to 256; added __launch_bounds__(256, 8) to softMax2 to make occupancy target explicit.
- Status: correct
- Speedup: 1.6134
- Profile backend: ncu
- What I learned: __launch_bounds__(256,8) gives 1.613, close to but slightly below best of 1.620. The constraint is already naturally satisfied, so the annotation has minimal effect.
- Best speedup so far: 1.6204
- Next step: N/A — 7 successful iterations complete.
