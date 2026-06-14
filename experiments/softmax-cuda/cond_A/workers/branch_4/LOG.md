# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Float4 vectorized loads + `#pragma unroll 4` in all three loops of `softMax2`. Added scalar fallback for sliceSize % 4 != 0.
- Status: correct
- Speedup: 1.5335
- Profile backend: ncu
- What I learned: Occupancy improved 74.1%→79.8%, load BW 1231→1346 GB/s, memory stalls 94.5%→88.1%. Short dependency stalls rose 1.2%→5.2% (float4 loads create longer dep chains). regs/thread 19→32.
- Best speedup so far: 1.5335
- Next step: Try `__ldg()` on float4 loads to use read-only cache path; may reduce memory latency stalls.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Added `__ldg()` on all float4 and scalar reads in `softMax2` to use read-only/texture cache path.
- Status: correct
- Speedup: 1.6128
- Profile backend: ncu
- What I learned: Memory stalls dropped 88.1%→77.5%. Short dep stalls rose 5.2%→8.2%. Occupancy 79.8%→80.4%. `__ldg()` clearly helps on sm_60 texture cache.
- Best speedup so far: 1.6128
- Next step: Precompute `inv_sum` (mult instead of div) and add `__restrict__` to reduce compiler conservatism.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Added `__restrict__` to src/dest pointers; precomputed `inv_sum` multiplier.
- Status: correct
- Speedup: 1.6131
- Profile backend: ncu
- What I learned: Negligible change from baseline of attempt 2 (1.6128). With `--use_fast_math`, compiler already does reciprocal-multiply for division. `__restrict__` gave no measurable benefit.
- Best speedup so far: 1.6131
- Next step: Try `#pragma unroll 8` to issue more independent loads and hide more latency.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Changed `#pragma unroll 4` → `#pragma unroll 8` in all loops.
- Status: correct
- Speedup: 1.4821
- Profile backend: ncu
- What I learned: Worse than unroll 4. Higher unroll factor increased register pressure and likely reduced occupancy. Reverted to unroll 4.
- Best speedup so far: 1.6131 (attempt 3)
- Next step: Try BLOCK_SIZE=128 (smaller blocks → more blocks per SM → better latency hiding).

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Changed BLOCK_SIZE 256→128.
- Status: correct
- Speedup: 1.5937
- Profile backend: ncu
- What I learned: Smaller block size is slightly worse. BLOCK_SIZE=256 appears optimal. Reverted.
- Best speedup so far: 1.6131 (attempt 3)
- Next step: Try online softmax (combined max+sum in 1 pass) to eliminate 1 read pass over data; then output pass = 2 total passes instead of 3.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Online softmax — combined max+sum into a single pass (2 total passes instead of 3). Warp reduce uses manual butterfly shuffle for (max,sum) pairs.
- Status: correct
- Speedup: 1.6194
- Profile backend: ncu
- What I learned: Load BW dropped 1341→893 GB/s (confirmed 1/3 fewer loads). Memory stalls 77.5%→66.4%. Short dep stalls 8.2%→7.7%. Occupancy 80.4%→81.2%. New best speedup.
- Best speedup so far: 1.6194
- Next step: Try `__stcs` streaming store for output to reduce cache pollution from write-only data.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Use `__stcs(&dst4[j], out)` (streaming cache store) for float4 output writes to avoid L1 cache pollution from write-only data.
- Status: correct
- Speedup: 1.6195
- Profile backend: ncu
- What I learned: No measurable change vs `__stcs`. On sm_60 (Pascal), global stores are already write-through so the cache hint makes no difference.
- Best speedup so far: 1.6195
- Next step: All 7 successful iterations complete.
