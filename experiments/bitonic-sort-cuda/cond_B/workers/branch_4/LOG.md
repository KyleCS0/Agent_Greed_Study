# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Restructured kernel index computation for coalesced memory access. Changed `i = blockDim.x * blockIdx.x + threadIdx.x` to use `half_idx`, `block_in_seq = half_idx / h_len`, `pos_in_half = half_idx % h_len`, `i = block_in_seq * seq_len + pos_in_half`, `j = i + h_len`. Launched `size/(2*BLOCK_SIZE)` blocks instead of `size/BLOCK_SIZE`. This ensures consecutive threads access consecutive `i` values (coalesced) and consecutive `j` values (coalesced).
- Status: correct
- Speedup: 1.40939
- Profile backend: ncu
- What I learned: The coalesced index restructuring significantly improved runtime from ~13.2ms to ~9.4ms (1.41x). Load efficiency per profiler snapshot still shows 50% (likely measured on a small-stage kernel call where h_len < 32), but total throughput improved. Memory stalls increased to 81.9% indicating still memory-latency bound.
- Best speedup so far: 1.40939
- Next step: Try shared memory optimization for small stages to reduce global memory round-trips and kernel launch overhead.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Added shared memory kernel `bitonic_sort_smem` that handles all stages from SMEM_STAGE_MAX (8) down to 0 in a single kernel call per step, using 2*BLOCK_SIZE=512 elements of shared memory per block. Large stages (seq_len > 2*BLOCK_SIZE) still use the coalesced global memory kernel. This reduces kernel launch overhead and eliminates global memory round-trips for the smaller stages.
- Status: correct
- Speedup: 1.69874
- Profile backend: ncu
- What I learned: Shared memory optimization brought runtime from ~9.4ms to ~7.8ms (1.70x overall speedup). Global load efficiency reached 100% on the smem kernel. However, significant shared memory bank conflicts appeared (524288 load, 518906 store) and the smem kernel uses 39 registers/thread. Bank conflicts are now the bottleneck to address.
- Best speedup so far: 1.69874
- Next step: Fix shared memory bank conflicts using padding (add 1 element padding per 32-element bank row) to improve smem bandwidth.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Added padding to shared memory indices using SMEM_IDX(x) = x + x/32 to eliminate bank conflicts in smem kernel. Allocated (2*BLOCK_SIZE + 2*BLOCK_SIZE/32) smem elements.
- Status: correct
- Speedup: 1.62526
- Profile backend: ncu
- What I learned: Padding eliminated bank conflicts (0 conflicts), but the extra index computation overhead (division and addition per access) made it slower (8.13ms vs 7.78ms for attempt 2). The bank conflicts in attempt 2 were actually less costly than the padding overhead. Best version remains attempt 2 (1.699x).
- Best speedup so far: 1.69874
- Next step: Revert to attempt 2 code, then try using larger smem tile (BLOCK_SIZE_SMEM=512) to cover more stages per smem kernel launch and further reduce global memory kernel calls.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Increased smem block size to BLOCK_SIZE_SMEM=512 (2*BLOCK_SIZE_SMEM=1024 elements), extending SMEM_STAGE_MAX to 9. This covers one more stage in shared memory per step.
- Status: correct
- Speedup: 1.62002
- Profile backend: ncu
- What I learned: Larger smem block (512 threads, 1024 elements) was slower (8.13ms vs 7.78ms). Barrier stalls increased to 12.2% with 512-thread blocks, and bank conflicts also increased. The 256-thread / 512-element configuration of attempt 2 remains the best. Reverting to attempt 2 code.
- Best speedup so far: 1.69874
- Next step: Try using __syncwarp() for intra-warp stages (h_len <= 32) to reduce synchronization overhead.

## Attempt 5

- Counted iteration: no
- Successful iteration number: N/A
- Change: Used __syncwarp() for h_len <= 32 stages and __syncthreads() for larger stages in the smem kernel.
- Status: correctness_fail
- Speedup: null
- Profile backend: ncu
- What I learned: __syncwarp() is NOT sufficient even for h_len<=32 because stage N-1 reads data written by different warps in stage N. For example, stage 5 (h_len=32) reads data written by different warps in stage 6 (h_len=64). Cross-warp dependencies span stage boundaries so __syncthreads() is always required.
- Best speedup so far: 1.69874
- Next step: Revert to attempt 2 code. Try reducing register pressure in smem kernel (currently 39 regs/thread) using pragmas to improve SM occupancy.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 5
- Change: Added `__launch_bounds__(256, 4)` to smem kernel to hint max 256 threads and min 4 blocks per SM. This guides compiler instruction scheduling and register allocation.
- Status: correct
- Speedup: 1.70132
- Profile backend: ncu
- What I learned: launch_bounds slightly improved performance (7.767ms vs 7.779ms). Interestingly, register count increased from 39 to 48, but occupancy dropped from 92% to 76%. The compiler traded occupancy for better instruction scheduling. Bank conflicts slightly increased too but overall runtime improved.
- Best speedup so far: 1.70132
- Next step: Try vectorized loads (int2/int4) for global memory load/store in smem kernel to improve memory throughput.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added `__launch_bounds__(256, 8)` to the global memory kernel. (Combined with smem kernel's `__launch_bounds__(256, 4)` from attempt 6.)
- Status: correct
- Speedup: 1.70152
- Profile backend: ncu
- What I learned: launch_bounds on global memory kernel gave a ptxas warning (out of range for minBlocksPerSM) but still compiled correctly. Speedup marginally better than attempt 6 (1.7015 vs 1.7013). Reverting launch_bounds on global kernel due to warning.
- Best speedup so far: 1.70152
- Next step: Try branchless compare-swap using min/max to avoid branch divergence.

## Attempt 8

- Counted iteration: yes
- Successful iteration number: 7
- Change: Applied branchless compare-and-swap using min/max (always writes both values) to both kernels, plus removed `__launch_bounds__` from global memory kernel.
- Status: correct
- Speedup: 1.02073
- Profile backend: ncu
- What I learned: Branchless swap that always writes is much worse because it doubles store transactions (always writing both a[i] and a[j] even when no swap needed). The conditional write is essential to avoid redundant stores. Reverted to conditional swap. Best speedup remains 1.70152 from attempt 7.
- Best speedup so far: 1.70152
- Next step: Run one more attempt with best code (attempt 6 config: smem kernel with launch_bounds(256,4), global kernel without launch_bounds, conditional swap).
