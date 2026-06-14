# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Converted histogram_smem_atomics from two-pass (smem->partial hist->accum kernel) to single-pass (smem->atomicAdd directly to d_hist). Used grid(8,8)=64 blocks. Removed d_part_hist alloc/free and second-pass accum kernel. Added cudaMemset before timer.
- Status: correct
- Speedup: 0.5991
- Profile backend: ncu
- What I learned: 64 blocks is not enough to cover the 1920x1080 image efficiently. Each block needs to process too many pixels in a loop, serializing work. The reduced parallelism dominated the savings from eliminating the second-pass kernel.
- Best speedup so far: 0.5991
- Next step: Increase grid size to 16x16 to match original parallelism level.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Increased grid from 8x8 to 16x16 (256 blocks), matching the original grid size.
- Status: correct
- Speedup: 1.63255
- Profile backend: ncu
- What I learned: Matching the original grid size recovers parallelism. Single-pass now outperforms two-pass because we eliminated the second kernel launch, cudaMalloc/Free overhead of 1MB d_part_hist, and the global write+read round-trip. Speedup of 1.63x vs baseline.
- Best speedup so far: 1.63255
- Next step: Try larger grid sizes to explore even better parallelism.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Increased grid from 16x16 to 20x16 (320 blocks).
- Status: correct
- Speedup: 2.09899
- Profile backend: ncu
- What I learned: More blocks = better GPU utilization with this single-pass approach. 320 blocks achieves 2.1x speedup. The image maps better to more blocks since each block processes fewer pixels.
- Best speedup so far: 2.09899
- Next step: Try 30x16 and other configurations to find the sweet spot.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Increased grid from 20x16 to 30x16 (480 blocks).
- Status: correct
- Speedup: 1.77405
- Profile backend: ncu
- What I learned: 480 blocks is too many; global atomic contention on 768 bins from 480 concurrent blocks degrades performance. Sweet spot appears to be around 320 blocks.
- Best speedup so far: 2.09899
- Next step: Try 24x16 and 20x20 to find better balance.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Changed grid from 30x16 back to 24x16 (384 blocks).
- Status: correct
- Speedup: 2.08259
- Profile backend: ncu
- What I learned: 384 blocks gives 2.08x, slightly less than 320 blocks (2.099x). The optimal is around 320 blocks. Let me try square grids.
- Best speedup so far: 2.09899
- Next step: Try 20x20=400 blocks.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Changed grid from 24x16 to 20x20 (400 blocks).
- Status: correct
- Speedup: 2.2862
- Profile backend: ncu
- What I learned: 20x20=400 blocks achieves 2.29x speedup - best so far! The square grid distributes work more evenly across rows and columns, reducing per-block workload while keeping global atomic contention manageable.
- Best speedup so far: 2.2862
- Next step: Try 25x20 to see if slightly more blocks improves further.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Changed grid from 20x20 to 25x20 (500 blocks).
- Status: correct
- Speedup: 2.14736
- Profile backend: ncu
- What I learned: 500 blocks gives 2.15x, less than 400 blocks (2.29x). The sweet spot is around 400 blocks (20x20). Beyond that, global atomic contention grows faster than the parallelism gains. Current best is 20x20 grid at 2.29x speedup.
- Best speedup so far: 2.2862
- Next step: All 7 successful iterations complete. Best configuration: 20x20 grid, single-pass smem atomics with direct global atomicAdd.
