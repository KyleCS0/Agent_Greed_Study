# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Implement ILP with ITEMS_PER_THREAD=4 using flat pair index approach. Each thread computes `j = base + k`, then derives seq_num and offset via integer division by h_len. Grid = size/(2*ITEMS_PER_THREAD*BLOCK_SIZE). Used __ldg() loads.
- Status: correct
- Speedup: 0.9762
- Profile backend: ncu
- What I learned: Simple consecutive ITEMS_PER_THREAD approach with per-item division by h_len causes slowdown due to integer division overhead and possibly cache/occupancy changes.
- Best speedup so far: 0.9762
- Next step: Switch to grid-stride layout where each thread's k-th item is spaced stride apart (better memory coalescing per k-iteration).

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Switch to ITEMS_PER_THREAD=8 (same flat-pair approach). Grid = size/(2*8*BLOCK_SIZE).
- Status: correct
- Speedup: 0.4008
- Profile backend: ncu
- What I learned: IPT=8 with consecutive indexing is much worse — likely register spilling or the integer divisions for 8 items compounds overhead severely.
- Best speedup so far: 0.9762
- Next step: Use grid-stride approach (j = tid + k*stride) so memory accesses are coalesced per iteration.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Grid-stride approach with ITEMS_PER_THREAD=4. Thread handles j=tid, tid+stride, tid+2*stride, tid+3*stride pairs. Preload all values then write back. Uses __ldg(). BLOCK_SIZE=256.
- Status: correct
- Speedup: 1.5185
- Profile backend: ncu
- What I learned: Grid-stride gives major speedup. Memory stalls dropped from 58.8% to 40.6%. Registers increased to 32. Load efficiency still 50%.
- Best speedup so far: 1.5185
- Next step: Try ITEMS_PER_THREAD=8 to increase ILP further.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: ITEMS_PER_THREAD=8 with grid-stride approach.
- Status: correct
- Speedup: 1.4969
- Profile backend: ncu
- What I learned: IPT=8 slightly worse than IPT=4, likely due to register pressure (more regs = lower occupancy).
- Best speedup so far: 1.5185
- Next step: Try BLOCK_SIZE=512 with IPT=4.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: BLOCK_SIZE=512, ITEMS_PER_THREAD=4.
- Status: correct
- Speedup: 1.5064
- Profile backend: ncu
- What I learned: BLOCK_SIZE=512 slightly worse than 256; default 256 is better.
- Best speedup so far: 1.5185
- Next step: Add specialized path for seq_len=2 to improve load efficiency.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added seq_len==2 special case that loads pairs (a[2p], a[2p+1]) consecutively, avoiding the general division path. BLOCK_SIZE=256, ITEMS_PER_THREAD=4.
- Status: correct
- Speedup: 1.5292
- Profile backend: ncu
- What I learned: Small improvement over attempt 3. Load efficiency still 50% (measured on a specific kernel pass). Memory stalls at 42.7%.
- Best speedup so far: 1.5292
- Next step: Try BLOCK_SIZE=128 with ITEMS_PER_THREAD=8 to change occupancy tradeoff.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: BLOCK_SIZE=128, ITEMS_PER_THREAD=8.
- Status: correct
- Speedup: 1.5055
- Profile backend: ncu
- What I learned: This combination is worse than BLOCK_SIZE=256/ITEMS=4. Best remains attempt 6.
- Best speedup so far: 1.5292
- Next step: 7 successful iterations complete. Best result is 1.529x speedup with grid-stride ITEMS_PER_THREAD=4, BLOCK_SIZE=256, seq_len=2 special case.
