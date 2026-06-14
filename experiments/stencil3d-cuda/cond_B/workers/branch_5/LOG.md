# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: no
- Successful iteration number: N/A
- Change: BSIZE 16→32 (core plan change)
- Status: profile_error (ncu lock file /tmp/nsight-compute-lock stale, owned by another user)
- Speedup: 2.76361
- Profile backend: none (ncu failed)
- What I learned: kernel runs correctly and faster, but ncu can't get its lock file. Fix: run with TMPDIR=/tmp/sheng_tmp
- Best speedup so far: N/A (not correct)
- Next step: retry with TMPDIR=/tmp/sheng_tmp

## Attempt 2

- Counted iteration: no
- Successful iteration number: N/A
- Change: none (same BSIZE=32, retry)
- Status: profile_error (same lock issue)
- Speedup: 2.76361
- Profile backend: none
- What I learned: profile_error is persistent without TMPDIR fix
- Best speedup so far: N/A
- Next step: retry with TMPDIR=/tmp/sheng_tmp

## Attempt 3

- Counted iteration: no
- Successful iteration number: N/A
- Change: none (same BSIZE=32, retry)
- Status: profile_error (same lock issue)
- Speedup: 2.76361
- Profile backend: none
- What I learned: confirmed TMPDIR=/tmp/sheng_tmp is needed
- Best speedup so far: N/A
- Next step: retry with TMPDIR=/tmp/sheng_tmp

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 1
- Change: BSIZE 16→32 with TMPDIR=/tmp/sheng_tmp
- Status: correct
- Speedup: 2.7636
- Profile backend: ncu
- What I learned: BSIZE=32 eliminates all bank conflicts (665804→0), reduces barrier stalls (47%→17%), load efficiency improves (80.5%→89.8%). New bottleneck: short dependency stalls 33.6%. Occupancy drops 79.6%→64.4% due to 40 regs/thread × 1024 threads = 1 block/SM on sm_89 (max 1536 threads/SM). ptxas reports 0 static_smem but actual smem is 32768 bytes per ptxas -v.
- Best speedup so far: 2.7636
- Next step: try __launch_bounds__(1024, 2) to target 2 blocks/SM by capping registers at 32

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 2
- Change: added __launch_bounds__(1024, 2) to kernel
- Status: correct
- Speedup: 2.7608
- Profile backend: ncu
- What I learned: registers dropped 40→32, short dependency stalls 33.6%→18.6%, but occupancy unchanged (64.4%→64.6%). sm_89 max threads/SM=1536, so 1024-thread blocks can never achieve 2 blocks/SM (2048>1536). The register reduction bought nothing occupancy-wise. Slightly worse speedup.
- Best speedup so far: 2.7636 (run_004)
- Next step: revert launch_bounds, try larger XTILE to reduce block count and improve x-loop amortization

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 3
- Change: reverted launch_bounds, XTILE 20→28
- Status: correct
- Speedup: 2.7511
- Profile backend: ncu
- What I learned: XTILE=28 slightly worse. Fewer blocks (10 vs 13 in x) didn't help.
- Best speedup so far: 2.7636 (run_004)
- Next step: try much larger XTILE=127 to maximize x-loop amortization

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 4
- Change: XTILE 28→127
- Status: correct
- Speedup: 2.1056
- Profile backend: ncu
- What I learned: XTILE=127 severely worse (648 total blocks, only 5 waves across 128 SMs). GPU underutilized and each block does too much serial work. XTILE=20 with ~4212 blocks is optimal for this GPU.
- Best speedup so far: 2.7636 (run_004)
- Next step: revert XTILE=20, try warp shuffle for z-face to eliminate 3 syncthreads per loop iteration

## Attempt 8

- Counted iteration: yes
- Successful iteration number: 5
- Change: XTILE→20, replaced z-face smem communication (sync4+sync5+sync3) with warp shuffle (__shfl_up_sync). BSIZE=32 guarantees one warp per y-row (tkk=0..31), so shuffle is valid.
- Status: correct
- Speedup: 2.7678
- Profile backend: ncu
- What I learned: warp shuffle slightly better (2.7678 vs 2.7636). Barrier stalls slightly reduced (16.5% vs 17%). Short dependency stalls still dominant at 32.7%. Improvement is modest because remaining syncs (sync1, sync2, sync6) are the heavy ones.
- Best speedup so far: 2.7678
- Next step: try XTILE=24 with warp shuffle

## Attempt 9

- Counted iteration: yes
- Successful iteration number: 6
- Change: XTILE 20→24 (with warp shuffle active)
- Status: correct
- Speedup: 2.7498
- Profile backend: ncu
- What I learned: XTILE=24 slightly worse. XTILE=20 remains best for x-dimension tiling.
- Best speedup so far: 2.7678 (run_008)
- Next step: revert XTILE=20, add __launch_bounds__(1024,1) to allow compiler to use more registers (up to 64/thread) and reduce spill stores (ptxas showed 16 bytes spill with 40 regs)

## Attempt 10

- Counted iteration: yes
- Successful iteration number: 7
- Change: XTILE→20, added __launch_bounds__(1024, 1)
- Status: correct
- Speedup: 2.7776
- Profile backend: ncu
- What I learned: __launch_bounds__(1024,1) increased registers 40→56, eliminating spill. Short dependency stalls dropped 32.7%→22.3% (compiler keeps more values in registers). Best speedup achieved: 2.7776 vs baseline 2.1793. Final config: BSIZE=32, XTILE=20, warp shuffle for z-face, __launch_bounds__(1024,1).
- Best speedup so far: 2.7776
- Next step: done — 7 successful iterations complete
