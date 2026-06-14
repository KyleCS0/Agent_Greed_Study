# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: No change; ran original code to establish baseline
- Status: correct
- Speedup: 1.482493
- Profile backend: ncu
- What I learned: Original unmodified code already achieves 1.48x speedup. Previous 3 failed runs (run_001–003) were from a prior session with unknown changes. Starting fresh from clean original.
- Best speedup so far: 1.482493
- Next step: Apply plan step 1 — change BLOCK_SIZE from 256 to 512

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Changed BLOCK_SIZE from 256 to 512 (16 warps/block, grid halves from 75000 to 37500 blocks)
- Status: correct
- Speedup: 1.552905
- Profile backend: ncu
- What I learned: BLOCK_SIZE=512 improved from 1.48x to 1.55x. More warps per SM improves scheduler utilization.
- Best speedup so far: 1.552905
- Next step: Apply plan step 2 — add `#pragma unroll 4` before each warp-stride loop in softMax2

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Added `#pragma unroll 4` before each of the 3 warp-stride loops in softMax2
- Status: correct
- Speedup: 1.544327
- Profile backend: ncu
- What I learned: Unroll hints gave a slight regression (1.553 -> 1.544), likely within noise. Keeping for ILP benefit.
- Best speedup so far: 1.552905 (attempt 2)
- Next step: Apply plan step 3 — add `__restrict__` to softMax2 pointer parameters

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Added `__restrict__` to src and dest pointer parameters in softMax2
- Status: correct
- Speedup: 1.541683
- Profile backend: ncu
- What I learned: __restrict__ minimal impact (1.544 -> 1.542), all plan steps applied. Best is still BLOCK_SIZE=512.
- Best speedup so far: 1.552905 (attempt 2)
- Next step: Apply plan step 4 — replace `float max_ = src[i*sliceSize]` with `float max_ = -FLT_MAX` in softMax2

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Replaced `float max_ = src[i*sliceSize]` with `float max_ = -FLT_MAX` (uniform initialization); added `#include <cfloat>`
- Status: correct
- Speedup: 1.543886
- Profile backend: ncu
- What I learned: -FLT_MAX init no significant impact. All plan steps applied. Best remains 1.553x at BLOCK_SIZE=512.
- Best speedup so far: 1.552905 (attempt 2)
- Next step: Try `__ldg()` for src reads to hint texture/L1 cache path for memory-latency-bound kernel

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added `__ldg()` for all src reads in softMax2 to use read-only texture cache path
- Status: correct
- Speedup: 1.548847
- Profile backend: ncu
- What I learned: __ldg slightly improves vs raw pointer but still below attempt 2. Differences are within noise (2.4% stddev).
- Best speedup so far: 1.552905 (attempt 2)
- Next step: Precompute slice base offset `i * sliceSize` to reduce arithmetic in inner loops

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Precomputed `int base = i * sliceSize` and used `src[base + j]` / `dest[base + j]` throughout, eliminating repeated multiplications in inner loops
- Status: correct
- Speedup: 1.550709
- Profile backend: ncu
- What I learned: Precomputing base offset gives a slight improvement vs attempt 6. Final best is attempt 2 (1.553x, BLOCK_SIZE=512 alone). All plan steps applied incrementally; differences mostly within noise band (~2.4% stddev).
- Best speedup so far: 1.552905 (attempt 2)
- Next step: All 7 successful iterations complete.
