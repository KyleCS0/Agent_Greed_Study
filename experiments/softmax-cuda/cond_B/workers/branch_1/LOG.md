# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Replaced 3-pass softMax2 with 2-pass online softmax + float4 vectorized loads/stores. Pass 1: single warp-strided loop reading float4 chunks with serial online-softmax updates (m, s). Warp-reduce max then rescale+reduce sum. Pass 2: float4 store loop writing expf(x-max_)/sum.
- Status: correct
- Speedup: 1.43702
- Profile backend: ncu
- What I learned: Online softmax cuts memory stalls from 94.4% to 82.9%. Load BW dropped from 1241 to 885 GB/s (1 fewer global read pass). Occupancy improved to 80.8%. Regs/thread increased from 19 to 32.
- Best speedup so far: 1.43702
- Next step: Reduce 7.2% short dependency stalls from serial online update chain. Try batch-processing float4 elements or __ldg hints.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Replaced serial 4-element online update with batch per-chunk: find local max of float4, update global m, add all 4 expf terms at once (to reduce serial dependency chain from 4 steps to 2 per float4).
- Status: correct
- Speedup: 1.38884
- Profile backend: ncu
- What I learned: Batch approach is slower than serial (1.389 vs 1.437). Possibly the compiler already handles the serial chain well, or the additional max/add operations add overhead. Reverted to serial approach.
- Best speedup so far: 1.43702
- Next step: Try __ldg read-only cache hint for both passes to improve memory access latency.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Added __ldg() read-only cache hint for src4 loads in both the online-softmax pass and the normalize pass. Reverted batch approach back to serial per-element update.
- Status: correct
- Speedup: 1.43845
- Profile backend: ncu
- What I learned: __ldg gives marginal improvement (1.4385 vs 1.437). Slightly better than attempt 1. Keeping __ldg.
- Best speedup so far: 1.43845
- Next step: Try __restrict__ on kernel parameters to help compiler alias analysis, and/or explicit inv_sum precompute.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Added `__restrict__` qualifier to src and dest parameters of softMax2 to help compiler alias analysis.
- Status: correct
- Speedup: 1.38829
- Profile backend: ncu
- What I learned: __restrict__ actually hurt performance (1.388 vs 1.438). Compiler may already assume non-aliasing for const src, or the hint changed code generation unfavorably. Reverted.
- Best speedup so far: 1.43845
- Next step: Try explicit reciprocal (__frcp_rn) to replace division by sum.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Added `float inv_sum = __frcp_rn(sum)` and replaced `/sum` with `* inv_sum` in normalize pass. Reverted __restrict__.
- Status: correct
- Speedup: 1.42135
- Profile backend: ncu
- What I learned: Explicit reciprocal is marginally worse than direct division (1.421 vs 1.438). --use_fast_math already converts division to reciprocal multiply. Reverted.
- Best speedup so far: 1.43845
- Next step: Try #pragma unroll on inner k-loop to reduce short dependency stalls.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added `#pragma unroll` on inner k-loop (k=0..3) in online softmax pass. Reverted inv_sum change, restored /sum.
- Status: correct
- Speedup: 1.40102
- Profile backend: ncu
- What I learned: Compiler already unrolls this fixed-size loop; pragma hint slightly degraded performance (1.401 vs 1.438). Reverted.
- Best speedup so far: 1.43845
- Next step: Cache loaded float4 values in registers during pass 1 to eliminate the second global read in the normalize pass, going from 2 read passes to 1.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Added `float4 cached[7]` register array to store pass-1 loaded values; normalize pass reads from cache instead of global memory, eliminating the second global read pass.
- Status: correct
- Speedup: 1.2813
- Profile backend: ncu
- What I learned: Register caching hurt performance significantly (1.281 vs 1.438 best). The `cached[7]` array (28 extra floats) increased register pressure, likely causing local memory spilling which is as slow as global memory. The occupancy drop from ~51 to ~32 warps/SM further reduced latency hiding. This approach is counterproductive for this kernel size.
- Best speedup so far: 1.43845 (attempt 3: online softmax + float4 + __ldg)
- Next step: All 7 successful iterations complete. Best result was attempt 3 at 1.4385x speedup.
