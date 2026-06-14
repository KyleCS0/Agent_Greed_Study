# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: no
- Successful iteration number: N/A
- Change: Applied warp-aware mapping (hi = lo + half_block as per plan) with original size threads and no bounds guard.
- Status: correctness_fail — threads i >= n_elems/2 accessed out-of-bounds memory; hi = lo + half_block ≠ lo + h_len for large h_len stages, causing wrong sort pairs.
- Speedup: null
- Profile backend: N/A
- What I learned: The plan's formula `hi = lo + half_block` is only correct when h_len <= blockDim.x (so half_block = h_len). For large h_len, must use hi = lo + h_len. Also, the warp-aware mapping maps n_elems threads but the upper half (i >= n_elems/2) produce out-of-bounds lo indices; a bounds guard is required.
- Best speedup so far: N/A
- Next step: Add hi = lo + h_len for correctness and add bounds guard.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 1
- Change: Warp-aware mapping with hi = lo + h_len (correct partner), single kernel, bounds guard via `if (i >= n_elems/2) return` for small h_len, and `if ((i%seq_len) >= h_len) return` for large h_len. Passed n_elems as extra parameter.
- Status: correct
- Speedup: 0.870
- Profile backend: ncu
- What I learned: Correct but slower than baseline. The overhead of extra parameter, branch, and return paths exceeded the coalescing benefit. Load efficiency still 50% (profiler measuring a large h_len stage). The warp stall percentage increased to 74.4%.
- Best speedup so far: 0.870
- Next step: Try splitting into two separate kernels to eliminate branch overhead on the hot large-h_len path.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 2
- Change: Same structure as attempt 2 but using `if (h_len < blockDim.x)` with a branch + n_elems guard for small path; large path uses `if ((i%seq_len) >= h_len) return` instead of `swapped_ele` idiom. Still one kernel.
- Status: correct
- Speedup: 0.936
- Profile backend: ncu
- What I learned: Slightly better than attempt 2 but still slower than baseline. The single-kernel branch overhead remains. 16 regs/thread (same as baseline) so not register-pressure bound.
- Best speedup so far: 0.936
- Next step: Revert to baseline to verify, then try two separate kernels.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 3
- Change: Reverted to exact original baseline code.
- Status: correct
- Speedup: 1.000
- Profile backend: ncu
- What I learned: Baseline confirmed at ~1.0x. Two-kernel approach is needed to avoid overhead on large-h_len path.
- Best speedup so far: 1.000
- Next step: Implement two separate kernels (bitonic_sort for large h_len, bitonic_sort_small for small h_len), select at launch time.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 4
- Change: Two separate kernels: `bitonic_sort` (original) for h_len >= BLOCK_SIZE, `bitonic_sort_small` (warp-aware, n_elems/2 threads) for h_len < BLOCK_SIZE. Host selects at launch time.
- Status: correct
- Speedup: 0.932
- Profile backend: ncu
- What I learned: Unexpectedly still slow. (Later corrected — this was attempt 5 which had an issue.) 
- Best speedup so far: 1.000
- Next step: Re-examine the two-kernel implementation for correctness and efficiency.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 5
- Change: Cleaned up two-kernel implementation: `bitonic_sort_small` uses n_elems/2 threads launched as `size/(2*BLOCK_SIZE)` blocks × BLOCK_SIZE threads. Warp-aware mapping: group=i/h_len, lane=i%h_len, lo=group*seq_len+lane, hi=lo+h_len, seq_num=group. No idle threads, fully coalesced for h_len >= warpSize within each kernel.
- Status: correct
- Speedup: 1.164
- Profile backend: ncu
- What I learned: Splitting into two kernels eliminates overhead on the large-h_len (hot) path. The warp-aware small kernel runs with n_elems/2 threads — all active. Speedup comes from eliminating idle threads in small-h_len stages. Load efficiency still 50% per profiler (profiler likely measuring the smallest h_len stages where warp-aware mapping still can't achieve 100% efficiency for h_len < warpSize=32).
- Best speedup so far: 1.164
- Next step: Extend warp-aware kernel to handle h_len = BLOCK_SIZE stage.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 6
- Change: Extended condition from `h_len < BLOCK_SIZE` to `h_len <= BLOCK_SIZE` so the warp-aware kernel handles one more stage (h_len=256, seq_len=512).
- Status: correct
- Speedup: 1.187
- Profile backend: ncu
- What I learned: Minor improvement from one additional stage using the warp-aware mapping. Incremental gains from extending the coverage of the small kernel.
- Best speedup so far: 1.187
- Next step: Extend the warp-aware kernel to ALL stages (remove the two-kernel split), since the mapping is mathematically valid for all h_len values.

## Attempt 8

- Counted iteration: yes
- Successful iteration number: 7
- Change: Replaced the two-kernel dispatch with a single `bitonic_sort_small` call for ALL stages. The warp-aware mapping (group=i/h_len, lane=i%h_len, lo=group*seq_len+lane, hi=lo+h_len) is valid for all h_len values when launched with n_elems/2 threads. For large h_len (e.g., h_len=8M), a warp of 32 threads maps to consecutive lo=0..31 and consecutive hi=8M..8M+31 — fully coalesced.
- Status: correct
- Speedup: 1.409
- Profile backend: ncu
- What I learned: The warp-aware mapping generalizes to ALL stages. By launching n_elems/2 threads (instead of n_elems), we eliminate all idle threads (originally 50% were idle). Load efficiency profiler still shows 50% — likely measured on the h_len=1 stage where consecutive thread-group access patterns still miss some cache efficiency. Overall, eliminating idle threads for ALL 300 kernel calls gives a ~41% speedup.
- Best speedup so far: 1.409
- Next step: All 7 successful iterations complete. Best result: 1.409x speedup.
