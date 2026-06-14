# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Add +1 padding to shared memory (sm_psi[4][BSIZE][BSIZE+1]) to eliminate bank conflicts; increase XTILE from 20 to 32 to amortize barrier overhead
- Status: correct
- Speedup: 2.2713
- Profile backend: ncu
- What I learned: Occupancy improved dramatically from 79.6% to 93.0% (XTILE increase drives better thread utilization). Bank conflicts only slightly reduced (660K vs 666K) — the conflicts come primarily from sm_psi[3] scratchpad accesses, not the row-stride issue. Barrier stalls still 48.4%, memory stalls 26.3%.
- Best speedup so far: 2.2713
- Next step: Try __ldg() for sigma reads to reduce memory stalls, and unroll pragmas.

## Attempt 2

- Counted iteration: yes (status=correct counts)
- Successful iteration number: 2
- Change: Increase XTILE from 32 to 48
- Status: correct but worse
- Speedup: 2.1203
- Profile backend: ncu
- What I learned: XTILE=48 reduces block count (6 x-blocks vs 8) and hurt performance, likely due to less spatial reuse in L2 or increased register pressure. XTILE=32 is the sweet spot so far.
- Best speedup so far: 2.2713
- Next step: Revert to XTILE=32. Try __ldg() on sigma reads to target the 26.3% memory stall.

## Attempt 3

- Counted iteration: no (compile error)
- Successful iteration number: N/A
- Change: Applied __ldg() to sigma and psi macros
- Status: compile_error
- Speedup: null
- Profile backend: N/A
- What I learned: Macros are used both for address-taking (&(psi(...))) and value reads; __ldg() returns an rvalue, breaking address-taking. Need to separate address and read macros, or use a different approach.
- Best speedup so far: 2.2713
- Next step: Revert to working state. Try #pragma unroll on main loop to reduce loop overhead.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 3
- Change: Add `#pragma unroll 4` to main x-direction loop
- Status: correct
- Speedup: 2.2874
- Profile backend: ncu
- What I learned: Unrolling by 4 gives a small but real improvement (2.287 vs 2.271), likely from reduced loop overhead and better instruction scheduling. XTILE=32 iterations unroll cleanly by 4.
- Best speedup so far: 2.2874
- Next step: Try increasing cache preference to L1 (cudaFuncSetCacheConfig) or try larger unroll factor.

## Attempt 5

- Counted iteration: yes (status=correct counts)
- Successful iteration number: 4
- Change: Add cudaFuncSetCacheConfig(stencil3d, cudaFuncCachePreferL1)
- Status: correct but worse
- Speedup: 2.1285
- Profile backend: ncu
- What I learned: On Pascal (sm_60), L1 and shared memory share the same pool. Preferring L1 shrinks available shared memory and hurts the shared-memory-heavy kernel. Reverted.
- Best speedup so far: 2.2874
- Next step: Try a larger unroll factor (unroll 8) or try BSIZE=32.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 5
- Change: Increase #pragma unroll from 4 to 8
- Status: correct
- Speedup: 2.2932
- Profile backend: ncu
- What I learned: Unroll 8 slightly better than unroll 4 (2.293 vs 2.287). More loop body unrolling reduces overhead further and helps the compiler overlap memory accesses.
- Best speedup so far: 2.2932
- Next step: Try unroll 16 or try BSIZE=32 for larger tiles.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 6
- Change: Increase #pragma unroll from 8 to 16
- Status: correct
- Speedup: 2.2961
- Profile backend: ncu
- What I learned: Marginal improvement with unroll 16 (2.296 vs 2.293). Trend continues: higher unroll = slightly better.
- Best speedup so far: 2.2961
- Next step: Try unroll 32 (full unroll) since XTILE=32; then explore BSIZE=32.

## Attempt 8

- Counted iteration: yes (status=correct counts, 7th and final)
- Successful iteration number: 7
- Change: Increase #pragma unroll from 16 to 32 (full unroll)
- Status: correct but worse
- Speedup: 2.2685
- Profile backend: ncu
- What I learned: Full unroll hurts — register pressure from 32 copies of the loop body exceeds the benefit of eliminating loop overhead. Reverted to unroll 16.
- Best speedup so far: 2.2961
- Next step: Keep unroll 16. Try BSIZE=32 for larger tiles.

## Attempt 9

- Counted iteration: no (iteration_limit reached)
- Successful iteration number: N/A
- Change: Change BSIZE from 16 to 32
- Status: iteration_limit (7 successful runs already completed)
- Speedup: null
- Profile backend: N/A
- What I learned: Evaluator counts ALL correct runs (including worse-speedup ones) toward the 7-iteration limit. All 7 successful iterations were already recorded by run_008. Task complete.
- Best speedup so far: 2.2961 (run_007, unroll 16, XTILE=32, BSIZE+1 padding)
- Next step: N/A — task complete.
