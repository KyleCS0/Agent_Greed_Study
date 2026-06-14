# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Replaced 300 separate kernel launches with a single persistent cooperative kernel using cudaLaunchCooperativeKernel and grid.sync(). Used compact indexing (total_threads = size/2) where each thread handles exactly one swap pair. Grid-stride loop handles the case where max concurrent blocks < size/BLOCK_SIZE.
- Status: correct
- Speedup: 1.37032
- Profile backend: ncu
- What I learned: Cooperative kernel achieves 100% occupancy (up from 80.2%), load bandwidth doubled to 2403 GB/s. 21.2% barrier stalls from grid.sync(). 78.4% load efficiency. Removing 300 kernel launch overheads gives ~1.37x speedup.
- Best speedup so far: 1.37032
- Next step: Try to reduce barrier stalls or improve memory access patterns.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Switched to original indexing pattern (size threads, half do nothing) instead of compact indexing.
- Status: correct
- Speedup: 0.91508
- Profile backend: ncu
- What I learned: Original indexing with inactive threads is slower - barrier stalls rise to 28.4%, load bandwidth drops to 1576 GB/s. Compact indexing from attempt 1 is better.
- Best speedup so far: 1.37032
- Next step: Revert to attempt 1's compact indexing.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Reverted to attempt 1's compact indexing approach (clean rewrite).
- Status: correct
- Speedup: 1.37081
- Profile backend: ncu
- What I learned: Confirmed attempt 1 approach is correct baseline. 1.37x speedup stable.
- Best speedup so far: 1.37081
- Next step: Try to reduce barrier stalls by using __syncthreads for intra-block stages and only grid.sync() for inter-block stages.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Clean restore of attempt 3's code (same as attempt 3 - confirming baseline).
- Status: correct
- Speedup: 1.36967
- Profile backend: ncu
- What I learned: Consistent ~1.37x speedup from cooperative kernel approach.
- Best speedup so far: 1.37081
- Next step: Try bit-shift optimization to replace integer division in index computation.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Replaced integer division with bit shifts for seq_num and local_i computation (seq_num = i >> h_len_log2, local_i = i & (h_len - 1)).
- Status: correct
- Speedup: 1.43824
- Profile backend: ncu
- What I learned: Bit shifts reduce instruction count, improving throughput. Load bandwidth went up to 2544 GB/s. Barrier stalls dropped from 21.2% to 17.2%.
- Best speedup so far: 1.43824
- Next step: Further optimize bit operations for odd and direction computation.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added bit-shift for two_power division (odd = seq_num >> two_power_log2) and modulo (odd & 1 instead of odd % 2).
- Status: correct
- Speedup: 1.44876
- Profile backend: ncu
- What I learned: Additional bit operations provide small improvement. All divisions now replaced with shifts.
- Best speedup so far: 1.44876
- Next step: Try __launch_bounds__ to control register usage.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Added __launch_bounds__(BLOCK_SIZE, 2) to kernel.
- Status: correct
- Speedup: 1.4484
- Profile backend: ncu
- What I learned: __launch_bounds__ with min_blocks_per_sm=2 didn't improve speedup significantly. Essentially same as attempt 6.
- Best speedup so far: 1.44876
- Next step: Task complete - 7 successful iterations achieved.

## Attempt 8

- Counted iteration: no (iteration_limit hit)
- Successful iteration number: N/A
- Change: Removed __launch_bounds__, tried branchless swap with min/max.
- Status: iteration_limit
- Speedup: null
- Profile backend: N/A
- What I learned: Ran out of allowed iterations. Task was already complete after attempt 7.
- Best speedup so far: 1.44876
- Next step: Task complete.
