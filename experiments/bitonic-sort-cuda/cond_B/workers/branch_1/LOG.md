# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: no
- Successful iteration number: N/A
- Change: Initial fused shared-memory kernel (attempt 1): 2-pass approach per stage with one __syncthreads() between passes. Each thread handles smem[tid] and smem[tid+BLOCK_SIZE]. Loaded elements directly at smem[tid] and smem[tid+BLOCK_SIZE].
- Status: correctness_fail
- Speedup: null
- Profile backend: N/A
- What I learned: Bug in Pass 1 - threads 0..BLOCK_SIZE-1 cannot cover upper half elements (smem[BLOCK_SIZE..2*BLOCK_SIZE-1]) correctly for small stages. Also had dead code from two implementations of local_swapped.
- Best speedup so far: N/A
- Next step: Fix the 2-pass approach properly to handle upper-half elements

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 1
- Change: Fixed 2-pass fused kernel. Each thread handles both local_idx=tid (lower half) and local_idx=tid+BLOCK_SIZE (upper half) with a __syncthreads() between. Used BLOCK_SIZE=512. Kept original global kernel for large stages.
- Status: correct
- Speedup: 1.18x
- Profile backend: ncu
- What I learned: 1.18x speedup. Global load efficiency improved to 100%. But 66K shared memory bank conflicts (load) and 56K (store). Barrier stalls at 12.1%.
- Best speedup so far: 1.18x
- Next step: Use conflict-free index mapping (one swap pair per thread per stage) to eliminate the extra __syncthreads() between passes and potentially reduce bank conflicts.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 2
- Change: Replaced 2-pass approach with conflict-free mapping: lo = (tid>>stage)*seq_len + (tid&(h_len-1)), hi = lo+h_len. One __syncthreads() per stage. Removed extra sync between passes.
- Status: correct
- Speedup: 1.50x
- Profile backend: ncu
- What I learned: 1.50x! Big improvement. But 549K load bank conflicts and 563K store conflicts (worse than attempt 2). The conflict-free mapping did not eliminate bank conflicts for stages with h_len % 32 == 0 (h_len=32,64,...,512). Still correct.
- Best speedup so far: 1.50x
- Next step: Try shared memory padding to eliminate bank conflicts.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 3
- Change: Added shared memory padding: SMEM_PAD(i) = i + (i>>5), physical smem size = tile_size + tile_size/32 = 1056 ints for BLOCK_SIZE=512. Updated smem_bytes accordingly.
- Status: correct
- Speedup: 1.48x
- Profile backend: ncu
- What I learned: Reduced bank conflicts from 549K to 21K load, 43K store. But performance is slightly worse (1.48x vs 1.50x) because the extra index computation overhead outweighs the bank conflict reduction.
- Best speedup so far: 1.50x (attempt 3)
- Next step: Revert padding, try replacing __syncthreads() with __syncwarp() for small stages.

## Attempt 5

- Counted iteration: no
- Successful iteration number: N/A
- Change: Reverted padding. Replaced __syncthreads() with __syncwarp() for stages where seq_len <= 2*WARP_SIZE=64, claiming swap pairs are warp-local.
- Status: correctness_fail
- Speedup: null
- Profile backend: N/A
- What I learned: __syncwarp() is insufficient - different warps can be at different loop iterations without a full __syncthreads(). The upper-half writes from one warp may not be visible to another warp at the next stage.
- Best speedup so far: 1.50x (attempt 3)
- Next step: Revert to __syncthreads() for all stages. Try BLOCK_SIZE=1024.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 4
- Change: Reverted to __syncthreads() only, changed BLOCK_SIZE from 512 to 1024 (tile=2048, smem=8KB). This allows fusing up to stage 10 instead of stage 9.
- Status: correct
- Speedup: 1.18x
- Profile backend: ncu
- What I learned: BLOCK_SIZE=1024 is much worse (1.18x) despite fusing one more stage. The larger smem reduces occupancy (8KB vs 4KB per block). BLOCK_SIZE=512 is optimal.
- Best speedup so far: 1.50x (attempt 3)
- Next step: Revert to BLOCK_SIZE=512. Try improving the global-memory large-stage kernel efficiency.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 5
- Change: Reverted to BLOCK_SIZE=512 (confirming run_003 approach is best so far). No changes from attempt 3.
- Status: correct
- Speedup: 1.50x
- Profile backend: ncu
- What I learned: Confirmed BLOCK_SIZE=512 gives 1.50x baseline for the fused approach. Global kernel still uses size threads (50% active).
- Best speedup so far: 1.50x
- Next step: Replace global-memory large-stage kernel with efficient version: launch size/2 threads, use conflict-free mapping so every thread is active.

## Attempt 8

- Counted iteration: yes
- Successful iteration number: 6
- Change: Replaced global bitonic_sort kernel to launch size/2 threads (instead of size), each thread handles exactly one pair via conflict-free mapping (same as fused kernel). Global load efficiency 50%->100%.
- Status: correct
- Speedup: 1.88x
- Profile backend: ncu
- What I learned: Major improvement to 1.88x! The efficient global kernel with size/2 threads eliminates wasted thread work. Profile: global load efficiency 100%, memory stalls 60.3%, barrier 12.6%, 548K smem bank conflicts.
- Best speedup so far: 1.88x
- Next step: Investigate further improvements. Try warp shuffles for small stages to reduce smem bank conflicts and barrier stalls.

## Attempt 9

- Counted iteration: yes
- Successful iteration number: 7
- Change: Added warp-shuffle hybrid in fused kernel: stages 0..4 (seq_len<=32, warp-local) use __shfl_xor_sync instead of shared memory. Stages 5..9 still use smem + __syncthreads(). After smem stages, load values into registers and process the remaining stages with shuffles.
- Status: correct
- Speedup: 1.91x
- Profile backend: ncu
- What I learned: Major improvement! Memory stalls dropped from 60.3% to 15.6%. Bank conflicts from 548K to 2.2K load. Wait stalls increased to 19.5% (new bottleneck). Load bandwidth down to 493 GB/s. This is the best result: 1.91x speedup.
- Best speedup so far: 1.91x
- Next step: Try replacing integer divisions with right-shifts for direction calculation.

## Attempt 10

- Counted iteration: no
- Successful iteration number: N/A
- Change: Replaced integer division (/) with right-shift (>>) for power-of-2 divisors in direction computation. Both global kernel and fused kernel updated.
- Status: iteration_limit (policy enforced run limit - 7 successful iterations completed)
- Speedup: null
- Profile backend: N/A
- What I learned: The harness enforced an iteration limit after reaching 7 successful iterations. Task complete.
- Best speedup so far: 1.91x (attempt 9)
- Next step: Task complete - 7 successful iterations achieved.
