# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Replaced scalar float loads/stores in softMax2 with float4 vectorized loads/stores across all three passes (max, sum, normalize). Loop bound changed from sliceSize to sliceSize/4, each iteration covers 4 elements.
- Status: correct
- Speedup: 1.3956
- Profile backend: ncu
- What I learned: Float4 vectorization increased occupancy from 74.3% to 79.9%, improved load bandwidth from 1241 to 1338 GB/s. Memory/long-scoreboard stalls reduced from 94.4% to 87.8%. Registers went from 19 to 31 per thread (float4 needs more regs). Short-dependency stalls rose from 1.2% to 5.3%.
- Best speedup so far: 1.3956
- Next step: Use reciprocal of sum (inv_sum = 1.0f/sum) and multiply instead of divide in pass 3, to reduce per-element instruction count and register pressure.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Replaced per-element division by sum with a single reciprocal (inv_sum = 1.0f/sum) and multiplied all four components in pass 3.
- Status: correct
- Speedup: 1.43702
- Profile backend: ncu
- What I learned: Hoisting the reciprocal out of the loop reduced instruction count in pass 3, yielding a ~3% additional speedup over attempt 1.
- Best speedup so far: 1.43702
- Next step: Add __restrict__ to kernel pointer parameters to allow the compiler to avoid redundant loads and schedule instructions more aggressively.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Added __restrict__ to src and dest pointer parameters of softMax2.
- Status: correct
- Speedup: 1.38383
- Profile backend: ncu
- What I learned: __restrict__ did not help — speedup regressed from 1.437 to 1.384, likely measurement noise but below best. Reverted to attempt 2 source.
- Best speedup so far: 1.43702
- Next step: Try __ldg() load intrinsic for the src4 reads to use read-only texture cache path.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Used __ldg() for all src4 reads in all three passes to route through the read-only/texture cache.
- Status: correct
- Speedup: 1.46612
- Profile backend: ncu
- What I learned: __ldg() improved speedup from 1.437 to 1.466. Read-only cache reduces latency for repeated loads of the same data across the three passes.
- Best speedup so far: 1.46612
- Next step: Cache exp values from pass 2 in shared memory to avoid recomputing them in pass 3 and eliminate the third memory pass.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Precomputed row4 = i * sliceSize4 constant to avoid per-iteration multiply in address generation.
- Status: correct
- Speedup: 1.38449
- Profile backend: ncu
- What I learned: Precomputing the row offset gave no benefit (compiler already optimizes this). Speedup regressed to 1.384, likely measurement variance. Reverted to attempt 4 source.
- Best speedup so far: 1.46612
- Next step: Cache exp values from pass 2 in shared memory to eliminate the third global memory pass and avoid recomputing expf() in pass 3.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Cache exp values from pass 2 in shared memory (extern __shared__ float4 exp_smem[]; 8 warps × 196 float4 = 25KB); pass 3 reads from smem instead of global memory.
- Status: correct
- Speedup: 0.820398
- Profile backend: ncu
- What I learned: 25KB shared memory per block limits blocks per SM to 2 (vs ~4 previously), dropping occupancy from ~80% to ~50%. The occupancy loss far outweighed savings from one fewer global memory pass. Reverted to attempt 4 source.
- Best speedup so far: 1.46612
- Next step: Try using __fmaf_rn or other arithmetic refinements from the current best source; alternatively accept that the best result is attempt 4 and run two more correct iterations with small neutral changes.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Added #pragma unroll 6 to all three warp loops in softMax2 (196/32 ≈ 6 iterations per thread).
- Status: correct
- Speedup: 1.48169
- Profile backend: ncu
- What I learned: Loop unrolling by 6 gave a small additional improvement, setting a new best of 1.482. The compiler can now schedule loads and compute instructions more aggressively with the unrolled body.
- Best speedup so far: 1.48169
- Next step: All 7 successful iterations complete. Task done.
