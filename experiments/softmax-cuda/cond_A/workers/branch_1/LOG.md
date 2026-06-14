# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Implemented shared-memory caching per plan: load global→smem in pass 1, read smem for exp in pass 2 (writing exp back to smem), read smem in pass 3. Fallback kernel for sliceSize > 1536. Launch with dynamic smem = WARPS_PER_BLOCK * sliceSize * 4 bytes.
- Status: correct
- Speedup: 1.36024
- Profile backend: ncu
- What I learned: Smem reduced global loads from 3× to 1× and halved expf, but occupancy dropped from 74.1% to 30.7% due to smem usage limiting resident blocks per SM. Also observed 2M smem bank conflicts (source unclear). Net effect: worse than planner's 1.48x.
- Best speedup so far: 1.36024
- Next step: Abandon smem approach (occupancy cost too high). Eliminate double expf differently: write exp to dest in pass 2, normalize dest in pass 3 (L2-hot read), keeping zero smem so occupancy is preserved.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Reverted to no-smem, but added dest-as-buffer approach: pass 1 reads src for max; pass 2 reads src, computes expf once, writes to dest; pass 3 reads dest (L2-hot), normalizes in place. This halves expf calls and reduces src reads from 3× to 2×, while maintaining high occupancy.
- Status: correct
- Speedup: 1.63383
- Profile backend: ncu
- What I learned: dest-as-buffer strategy works well. Occupancy rose to 78.2% (up from 74.1% baseline). Load bandwidth 1360 GB/s, store bandwidth 903 GB/s (doubled due to 2 dest writes). Memory stall 95% — still latency-limited. Key win: L2-cached dest reads in pass 3 and halved expf.
- Best speedup so far: 1.63383
- Next step: Try further reducing global memory traffic. Options: (1) vectorized float4 loads/stores, (2) fix redundant src[0] initialization, (3) loop unrolling.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Float4 vectorized loads/stores when sliceSize % 4 == 0 (scalar fallback otherwise). Reduces global memory instructions by 4×. Checks alignment requirement (sliceSize % 4 → all slice offsets are 16-byte aligned).
- Status: correct
- Speedup: 1.65268
- Profile backend: ncu
- What I learned: Float4 dramatically improved occupancy (86.0% from 78.2%) and dropped memory stall from 95% to 71.3%. Short-dependency stall 9.1% (expf). 28 registers. Store bandwidth doubled but overall kernel is faster because 4× fewer memory instructions allow better latency hiding. Best approach so far.
- Best speedup so far: 1.65268
- Next step: Try adding __ldg() for src reads and #pragma unroll to further reduce stalls.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Added `#pragma unroll 4` to all float4 loops and `__ldg(&src4[j])` for read-only src loads in both pass 1 and pass 2.
- Status: correct
- Speedup: 1.65263
- Profile backend: ncu
- What I learned: Memory stall dropped from 71.3% to 60.4% and occupancy reached 87.7%, but registers jumped from 28 to 37. Net speedup essentially unchanged (noise). The __ldg + unroll did help pipeline but extra register pressure neutralized it.
- Best speedup so far: 1.65268 (attempt 3)
- Next step: Try register-caching src values to reduce global passes from 5 to 2 (1 src read + 1 dest write) for small sliceSize.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Added register-cache path: for sliceSize <= 512 (vc_per_thread <= 4 float4), load src into float4 re[4] array, compute max and exp in-registers, write single dest pass. Fallback to dest-buffer for larger sliceSize.
- Status: correct
- Speedup: 1.65243
- Profile backend: ncu
- What I learned: Bandwidth unchanged (1378/919 GB/s) → register cache path NOT taken → sliceSize > 512. Extended threshold needed.
- Best speedup so far: 1.65268 (attempt 3)
- Next step: Extend register cache to sliceSize <= 1024 (float4 re[8]).

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Extended register-cache threshold to vc <= warp.size() * 8 (sliceSize <= 1024). Used float4 re[8] array with #pragma unroll over k=0..7.
- Status: correct
- Speedup: 1.64294
- Profile backend: ncu
- What I learned: Register cache now triggered (bandwidth dropped from 1378 to 454 GB/s, confirming sliceSize is in (512, 1024]). But registers jumped to 48, occupancy dropped to 68.5%, and SFU became the bottleneck (short-dependency 25.4% vs 10.4%). The memory-traffic reduction was offset by occupancy loss and SFU contention. Slower than attempt 3.
- Best speedup so far: 1.65268 (attempt 3)
- Next step: Revert to attempt 3 code (float4 dest-buffer, 28 regs, 86% occupancy) for final iteration 7.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Reverted to attempt 3 code (float4 vectorized dest-buffer, no register cache, no unrolling). 28 regs, same algorithm as attempt 3.
- Status: correct
- Speedup: 1.48481 (median 4.611ms — system noise: runs 1-2 were 5.3ms/6.25ms, runs 3-4 were 4.14ms as expected)
- Profile backend: ncu
- What I learned: Profile confirms correct code (28 regs, 85.9% occupancy, 71.6% memory stall, 1377 GB/s) matching attempt 3 exactly. Speedup lower due to noisy runs 1-2 skewing the median. Underlying performance is still ~4.14ms. System noise is a real variance factor.
- Best speedup so far: 1.65268 (attempt 3)
- Next step: 7 successful iterations complete. Mission accomplished.
