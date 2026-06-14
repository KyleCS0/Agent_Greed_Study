# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: `typedef double Real` → `typedef float Real`; `sm_psi[4][BSIZE][BSIZE]` → `sm_psi[4][BSIZE][BSIZE+1]`
- Status: correct
- Speedup: 2.9274
- Profile backend: ncu
- What I learned: Float halved memory traffic and boosted occupancy 79.6%→96.7%. Padding +1 eliminated load bank conflicts (665K→0) but introduced store bank conflicts (0→735K). With float, each 16-element row spans exactly 16 banks; row 0 uses banks 0-15, row 1 uses banks 16-31 — no natural conflict. The +1 padding makes row stride 17 banks: row 1 wraps to bank 0, conflicting with row 0. Padding is counterproductive for float; removing it should fix store conflicts at no cost.
- Best speedup so far: 2.9274
- Next step: Remove BSIZE+1 padding back to BSIZE — float rows naturally avoid bank conflicts without padding.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Remove `BSIZE+1` padding → `BSIZE` (padding was counterproductive for float)
- Status: correct
- Speedup: 2.9274
- Profile backend: ncu
- What I learned: Removing padding eliminated all bank conflicts (load=0, store=0) and confirmed float 16-element rows are conflict-free. Speedup unchanged, but profile is cleaner. Dominant bottlenecks: barrier stalls 51.6%, memory/long-scoreboard 45.5%, global load efficiency 66%. The 66% efficiency comes from warps spanning two y-rows (tjj=0 and tjj=1), accessing z-elements 256 apart. To fix this, change to blocks(32, 8, 1) so a full 32-thread warp covers one y-row × 32 consecutive z-values → ~100% coalesced loads.
- Best speedup so far: 2.9274
- Next step: Decouple BSIZE into BSIZE_Y=8 and BSIZE_Z=32; blocks(BSIZE_Z, BSIZE_Y, 1) = (32, 8, 1). Same 256 threads/block and same 4KB shared memory, but each warp now accesses 32 contiguous z-elements → fix 66% load efficiency.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Decouple BSIZE into BSIZE_Y=8, BSIZE_Z=32; blocks(32,8,1). Same 256 threads/block, same 4KB shared memory.
- Status: correct
- Speedup: 4.6231
- Profile backend: ncu
- What I learned: Full 32-thread warps now cover 32 consecutive z-elements → global load efficiency improved 66%→80.9%, load bandwidth 578→773 GB/s. 0 bank conflicts preserved. Remaining bottlenecks: barrier stalls 49.9%, memory stalls 46.0%. There are 6 __syncthreads() per loop iteration; syncs 5 (after zcharge-read) and 6 (end-of-loop) are unnecessary: sync 5 protects nothing (xcharge only reads sm_psi[cii/nii], never sm_psi[3]); sync 6 protects nothing (next-iter writes to sm_psi[old_pii] which is never read in current-iter xcharge). Removing both cuts syncs from 6→4 per iteration.
- Best speedup so far: 4.6231
- Next step: Remove the two unnecessary __syncthreads() (sync 5 after zcharge-read, sync 6 at end of loop body) to reduce barrier stall rate.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Remove sync 5 (after zcharge read) and sync 6 (end of loop body) — 6→4 syncs/iteration
- Status: correct
- Speedup: 4.6076
- Profile backend: ncu
- What I learned: Barrier stalls dropped 49.9%→46.2% as expected, but memory stalls rose 46.0%→49.9% (no longer masked by barriers). Register count increased 39→40, slightly hurting occupancy (97.3%→96.6%). Net result: marginally worse (4.608 vs 4.623). Best source remains attempt 3 (with syncs). Memory stalls are now the harder bottleneck to crack; bandwidth is ~771-773 GB/s which may be near device peak.
- Best speedup so far: 4.6231 (attempt 3)
- Next step: Revert to attempt 3 source (restore syncs). Then try XTILE=16 to see if finer x-tiles help grid occupancy.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Restore 2 removed syncs (revert attempt 4 back to attempt 3 source)
- Status: correct
- Speedup: 4.6231
- Profile backend: ncu
- What I learned: Confirmed revert fully restores best speedup. Kernel is memory-bandwidth bound at ~771 GB/s. Remaining slack: global load efficiency 80.9% (below 85%). This 19% waste is caused by BSIZE_Z-2=30 not being a multiple of 32, so z-tile starts are misaligned to cache lines. Fixing alignment would require BSIZE_Z=34 (breaks warp structure) — not straightforward.
- Best speedup so far: 4.6231
- Next step: Try XTILE=24 (fewer x-blocks, more work per block) to reduce block launch overhead and see if larger tiles give the scheduler more latitude.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: XTILE 20→24 (bdimx 13→11 blocks in x, each block does 24 x-iterations vs 20)
- Status: correct
- Speedup: 4.7186
- Profile backend: ncu
- What I learned: Larger XTILE continues to improve performance — load bandwidth 773→790 GB/s, occupancy 97.3%→96.9% (essentially same), 0 bank conflicts, 39 regs/thread. Fewer larger blocks = better instruction cache reuse and scheduler efficiency. Stalls: barrier 48.1%, memory 47.7% (well-balanced). Trend suggests trying XTILE=32 for one more improvement.
- Best speedup so far: 4.7186
- Next step: Try XTILE=32 (bdimx=8) for the final iteration to see if trend continues.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: XTILE 24→32 (bdimx 11→8 blocks in x, each block does 32 x-iterations)
- Status: correct
- Speedup: 4.9846
- Profile backend: ncu
- What I learned: XTILE=32 pushed load bandwidth to 826.8 GB/s (up from 790), occupancy 97.3%, 0 bank conflicts, 39 regs/thread. Larger x-tiles reduce total block count (8×43×9=3096 blocks) → less block launch overhead and better instruction cache utilization. The trend from XTILE=20→24→32: 4.623→4.719→4.985. Diminishing returns likely set in around XTILE=40+ as register spill or excessive per-block runtime could hurt occupancy.
- Best speedup so far: 4.9846
- Next step: All 7 successful iterations complete. Final best: 4.9846x speedup at XTILE=32, BSIZE_Y=8, BSIZE_Z=32, typedef float Real.
