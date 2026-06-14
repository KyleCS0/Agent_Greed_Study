# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Switch softMax2 from warp-per-slice to block-per-slice parallelism. Each block (256 threads, 8 warps) handles one slice. Threads stride by BLOCK_SIZE through the slice. Two-level reduction: warp shuffle → smem[warp_id] → warp 0 reduces 8 partial values. Launch config changed to grids=numSlice, blocks=BLOCK_SIZE.
- Status: correct
- Speedup: 1.6763
- Profile backend: ncu
- What I learned: Occupancy jumped from 74.1% to 94.7%. Memory stalls dropped from 94.5% to 60.1%. Barrier stalls appeared at 26.0% (from __syncthreads() calls). Shared memory bank conflicts observed (45389 load, 53451 store). Load bandwidth increased to 1394.7 GB/s from 1231.5 GB/s.
- Best speedup so far: 1.6763
- Next step: Try float4 vectorized loads to reduce load instruction count and further hide memory latency. Also investigate bank conflicts in smem reduction.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Add float4 vectorized loads in all three passes (max, sum, output). Uses 4-wide loads to reduce instruction count.
- Status: correct
- Speedup: 1.6732
- Profile backend: ncu
- What I learned: Float4 reduced memory stalls (60.1% → 45.4%) but increased barrier stalls (26.0% → 41.6%). Register count went up to 36 (from 32), slightly reducing occupancy (94.7% → 93.3%). Net effect: essentially same speedup as attempt 1. The bank conflicts also increased.
- Best speedup so far: 1.6763 (attempt 1)
- Next step: Try online softmax to reduce global memory passes from 3 to 2.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Online softmax (single-pass max+sum) reduces global reads by 1/3. Merge operation: merge((m1,s1),(m2,s2)) = (max, s1*exp(m1-M)+s2*exp(m2-M)).
- Status: correct
- Speedup: 1.6762
- Profile backend: ncu
- What I learned: Load bandwidth dropped to 930 GB/s (2/3 of 1394, confirming 2/3 fewer reads). But speedup unchanged. Analysis: extra expf in merge operation offsets savings. Kernel is balanced between compute (expf) and memory latency; neither pass alone dominates. Best approach: eliminate expf calls, not just reads.
- Best speedup so far: 1.6763 (attempt 1)
- Next step: Cache exp values in dynamic shared memory. This eliminates one global read (pass 3 reads smem instead of DRAM) AND halves expf calls (compute expf once in pass 2, reuse in pass 3 from smem).

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Dynamic smem exp-cache. Pass 2 computes expf and stores to smem; pass 3 reads smem (no src global read, no expf). Eliminates one global read pass and halves expf calls. Dynamic smem = (NUM_WARPS + sliceSize) * sizeof(float).
- Status: correct
- Speedup: 1.6756
- Profile backend: ncu
- What I learned: Bank conflicts dropped to 0 (from 45k/53k). Occupancy slightly improved (95.8%). Load bandwidth 930 GB/s (2/3 of attempt 1, confirming one fewer global read). Memory stalls still 59.7%, barrier stalls 27.1%. Speedup unchanged — kernel is fundamentally memory-latency limited; eliminating expf and one read pass doesn't help because the bottleneck is DRAM/L2 latency, not compute or bandwidth.
- Best speedup so far: 1.6763 (attempt 1)
- Next step: Try BLOCK_SIZE=128 to double the number of concurrent blocks per SM (16 vs 8), potentially increasing SM-level memory-latency hiding.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: BLOCK_SIZE=128 (4 warps/block). Twice as many concurrent blocks per SM vs 256 (16 vs 8). Smem exp-cache kept.
- Status: correct
- Speedup: 1.6588
- Profile backend: ncu
- What I learned: Higher occupancy (98.5%) but memory stalls worsened (70.6% vs 60%). With smaller blocks, each thread processes more elements sequentially → longer latency chains. More concurrent blocks also increases L2 pressure → fewer cache hits. Net effect: slightly worse. BLOCK_SIZE=256 is the sweet spot.
- Best speedup so far: 1.6763 (attempt 1)
- Next step: Revert to best approach (attempt 1: 3-pass block-per-slice, BLOCK_SIZE=256). Try loop unrolling to reduce loop overhead in the main passes.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Revert to BLOCK_SIZE=256 3-pass block-per-slice (attempt 1 base). Add `#pragma unroll 4` to all main load loops.
- Status: correct
- Speedup: 1.6772
- Profile backend: ncu
- What I learned: Loop unrolling reduced registers from 32 to 20 (dramatic). FMA utilization doubled (4.2% → 8.1%). Occupancy improved (94.7% → 96.0%). New best speedup. With 20 regs/thread, register file is no longer limiting factor (thread count limits to 8 blocks/SM). Bank conflicts remain (44244/53287) from the static smem[8].
- Best speedup so far: 1.6772 (attempt 6)
- Next step: Combine unrolling with smem exp-cache to eliminate bank conflicts and further reduce memory stalls.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Combine `#pragma unroll 4` + smem exp-cache. Unrolling further reduces registers (20→18/thread). Exp-cache eliminates bank conflicts and halves expf calls.
- Status: correct
- Speedup: 1.6765
- Profile backend: ncu
- What I learned: Registers dropped to 18 (lowest yet), occupancy 96.6%. Bank conflicts 0. Load bandwidth 930 GB/s. Despite best individual metrics, speedup is slightly below attempt 6 (1.6772). The bank conflicts in attempt 6 don't hurt performance significantly — they're absorbed into the same latency window. The memory latency bottleneck (61% stalls) is the hard floor for this kernel on this GPU.
- Best speedup so far: 1.6772 (attempt 6: 3-pass + unroll 4)
- Next step: N/A — 7 successful iterations complete.
