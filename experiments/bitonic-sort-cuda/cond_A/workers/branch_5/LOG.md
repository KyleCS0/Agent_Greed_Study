# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Implemented async CUDA stream plan: cudaMallocHost for data_gpu, cudaMemcpyAsync H2D, kernels in stream, async D2H, return without sync. Start timer before kernels (after async H2D issued but before H2D complete). CPU sort overlaps D2H in main, then cudaStreamSynchronize before memcmp.
- Status: correct
- Speedup: 0.7841
- Profile backend: ncu
- What I learned: Timer was placed after issuing async H2D but before H2D completion, so timer included H2D latency (~3-4ms overhead). That's why measured time was ~16.85ms vs baseline ~13.21ms. Need to sync after H2D before starting timer.
- Best speedup so far: 0.7841 (but this is misleading due to timing issue)
- Next step: Fix timing: add cudaStreamSynchronize after H2D before starting the kernel timer.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Added cudaStreamSynchronize after H2D async copy and before start timer. This ensures timer measures only kernel execution time, matching baseline measurement approach. Async D2H still issued after kernel sync, overlapping with CPU BitonicSort in main.
- Status: correct
- Speedup: 1.0004
- Profile backend: ncu
- What I learned: The plan's overlap (D2H concurrent with CPU sort) reduces total wall-clock time but the harness measures the printed "Total kernel execution time" which is pure GPU kernel time. That time doesn't change (~13.21ms). So speedup ~1.0x. To improve measured speedup, need to actually reduce GPU kernel time.
- Best speedup so far: 1.0004
- Next step: Try to reduce GPU kernel time. Options: shared memory usage, loop unrolling, or register-level optimizations. The profile shows 50% global load efficiency and memory latency stalls - uncoalesced accesses are fundamental to the algorithm but could be improved with shared memory tiling.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Replaced pow(2, ...) with bit-shift operator (1 << ...) in ParallelBitonicSort for seq_len and two_power computation. Also changed size computation to use 1<<n.
- Status: correct
- Speedup: 1.00041
- Profile backend: ncu
- What I learned: Bit shifts vs pow() doesn't meaningfully change the measured GPU kernel time since the host-side computation of launch parameters is negligible compared to kernel execution. Speedup still ~1.0004.
- Best speedup so far: 1.0005 (attempt 5, with launch_bounds)
- Next step: Try __launch_bounds__ on kernel to optimize register usage and occupancy.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Increased BLOCK_SIZE from 256 to 512.
- Status: correct
- Speedup: 0.9582
- Profile backend: ncu
- What I learned: BLOCK_SIZE 512 is worse than 256. Larger blocks reduce occupancy on this GPU (sm_89). 256 is better.
- Best speedup so far: 1.00048 (attempt 5)
- Next step: Revert to 256, try __launch_bounds__ hint on kernel.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Reverted BLOCK_SIZE to 256 and added __launch_bounds__(256, 4) to bitonic_sort kernel to hint compiler for max 4 blocks/SM.
- Status: correct
- Speedup: 1.00048
- Profile backend: ncu
- What I learned: __launch_bounds__ provides marginal improvement. The GPU kernel time is very close to baseline; the bottleneck is memory latency (50% global load efficiency) which is intrinsic to the bitonic sort algorithm.
- Best speedup so far: 1.00048
- Next step: Add __restrict__ to the kernel pointer parameter to allow better compiler memory access optimization.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added __restrict__ qualifier to the int* parameter in bitonic_sort kernel.
- Status: correct
- Speedup: 1.00037
- Profile backend: ncu
- What I learned: __restrict__ didn't improve speedup measurably. All these micro-optimizations are within noise for this memory-latency-bound kernel.
- Best speedup so far: 1.00048 (attempt 5)
- Next step: Try cudaStreamNonBlocking flag to ensure stream doesn't synchronize with default stream.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Changed cudaStreamCreate to cudaStreamCreateWithFlags with cudaStreamNonBlocking flag for the sort stream.
- Status: correct
- Speedup: 1.00037
- Profile backend: ncu
- What I learned: The non-blocking stream flag makes no measurable difference for this workload. The plan's async overlap approach achieves correct sorting with ~1.0x speedup on the measured GPU kernel timing metric. The actual wall-clock benefit (D2H overlapping with CPU sort) is not captured in the timing measurement.
- Best speedup so far: 1.00048 (attempt 5)
- Next step: All 7 successful iterations complete.
