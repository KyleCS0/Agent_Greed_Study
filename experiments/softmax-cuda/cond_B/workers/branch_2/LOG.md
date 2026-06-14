# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Implement shared memory caching per the assigned plan. Cache the entire slice in shared memory with float4 vectorized global loads/stores. Reduces global reads from 3 passes to 1. Dynamic smem size = (BLOCK_SIZE/32)*sliceSize*sizeof(float) = 25088 bytes/block.
- Status: correct
- Speedup: 1.502728
- Profile backend: ncu
- What I learned: Shared memory caching drops median from 5.288ms (planner) to 4.557ms. However, profiler shows 973K smem load bank conflicts and 778K store bank conflicts. The float4 warp-stride-32 pattern in smem causes 4-way conflicts (threads 0,8,16,24 share bank 0). Occupancy dropped from 74.3% to 32.7% due to smem usage.
- Best speedup so far: 1.502728
- Next step: Fix smem bank conflicts by using scalar (float) smem accesses instead of float4, which gives stride-1 bank access pattern with no conflicts.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Replace float4 smem accesses with scalar (float) loads/stores to eliminate bank conflicts. Use reciprocal multiplication (1.0f/sum) instead of division in Pass 3. Register count dropped from 32 to 20.
- Status: correct
- Speedup: 1.503778
- Profile backend: ncu
- What I learned: Bank conflicts actually INCREASED (1.98M load vs 973K before) - compiler auto-vectorized the scalar loops into float4 internally, producing same conflict pattern. Timing is essentially the same (4.554 vs 4.557 ms). Memory stall rate went up to 86.5% (worse). Occupancy similar (32.3%).
- Best speedup so far: 1.503778
- Next step: Reduce BLOCK_SIZE to allow more blocks/SM and increase occupancy. Try BLOCK_SIZE=64 (2 warps/block, ~6272 bytes smem) which could allow ~15 blocks per SM (62% occupancy) vs current 2 blocks (32%).

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Try BLOCK_SIZE=64 (from 256) to increase occupancy via more blocks per SM.
- Status: correct
- Speedup: 1.36918
- Profile backend: ncu
- What I learned: Smaller block size hurts performance significantly. Only 2 warps per block reduces intra-block latency hiding. Reverting to BLOCK_SIZE=256.
- Best speedup so far: 1.503778 (attempt 2)
- Next step: Revert to BLOCK_SIZE=256. Try BLOCK_SIZE=128 as a middle ground, or try __ldg() cache hints on global loads.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Use stride-33 smem layout (32 elements + 1 float padding per row) to eliminate bank conflicts. Bank of ws[k*33+t] = (k*33+t)%32 = (k+t)%32, all 32 threads hit distinct banks per iteration. smem size increases from 25088 to 26400 bytes.
- Status: correct
- Speedup: 1.50223
- Profile backend: ncu
- What I learned: Zero bank conflicts via stride-33 layout does not yield meaningful speedup over approach with conflicts. Performance is essentially the same (1.502 vs 1.504). The bank conflicts in smem are not the limiting factor. Memory latency from global reads is the true bottleneck.
- Best speedup so far: 1.503778 (attempt 2)
- Next step: Revert to attempt 2 code (simple scalar, no stride-33). Add __restrict__ to kernel params to help compiler alias analysis and potentially generate better load/store instructions.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Reverted stride-33 back to simple scalar smem (sliceSize stride) from attempt 2. Added __restrict__ qualifier to src and dest kernel parameters for better compiler alias analysis.
- Status: correct
- Speedup: 1.50084
- Profile backend: ncu
- What I learned: __restrict__ makes no measurable difference — compiler already treats const float* as read-only. All scalar variants give ~1.503x speedup. The 1.5x ceiling seems hard to break without a fundamentally different approach.
- Best speedup so far: 1.503778 (attempt 2)
- Next step: Try cudaFuncSetAttribute to maximize smem carveout on sm_86 Ampere GPU (100KB smem vs 48KB default), potentially fitting 3-4 blocks per SM and improving occupancy from 32% to 50%+.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added cudaFuncSetAttribute(softMax2, cudaFuncAttributePreferredSharedMemoryCarveout, cudaSharedmemCarveoutMaxShared) to request maximum smem allocation on the SM, reducing L1 pressure and allowing more blocks per SM.
- Status: correct
- Speedup: 1.5117
- Profile backend: ncu
- What I learned: Max smem carveout gave a new best speedup (1.5117). Load bandwidth increased slightly (454.4 vs 452.9 GB/s). Occupancy remained ~31% suggesting the carveout didn't increase block count, but L1→smem rebalancing improved effective memory throughput.
- Best speedup so far: 1.5117 (attempt 6)
- Next step: Try #pragma unroll on all three warp-strided loops to improve ILP and allow the compiler to better schedule memory operations (hide latency).

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Added `#pragma unroll 4` to all three warp-strided loops (Pass 1, 2, 3) to encourage ILP through instruction unrolling.
- Status: correct
- Speedup: 1.46337
- Profile backend: ncu
- What I learned: #pragma unroll 4 hurt performance. Unrolling likely increased register pressure (more live values in flight), reducing occupancy or causing register spills. The compiler's default scheduling without unrolling is better here.
- Best speedup so far: 1.5117 (attempt 6, scalar smem + __restrict__ + max smem carveout)
- Next step: 7 successful iterations complete. Best implementation: attempt 6 source code.
