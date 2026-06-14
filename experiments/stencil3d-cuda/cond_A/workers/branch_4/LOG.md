# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Converted sigma layout from direction-major (stride=vol=128MB between directions) to direction-innermost (stride=3 between directions). Changed macros from `d_sigmaX[z + nz*(y + ny*(x + nx*dir))]` to `d_sigmaX[(z + nz*(y + ny*x))*3 + dir]`. Updated main() initialization to maintain correct logical values under the new layout.
- Status: correct
- Speedup: 2.6668
- Profile backend: ncu
- What I learned: Occupancy jumped from 79.6% to 93.3%; kernel went from memory-latency limited to synchronization/barrier limited. Load bandwidth shot up to 1923.9 GB/s. Global load efficiency dropped from 80.5% to 35.4% (stride-3 access pattern) but faster overall due to better occupancy and lower barrier/memory stalls.
- Best speedup so far: 2.6668
- Next step: Try `#pragma unroll` on the main x-loop or a larger XTILE to amortize __syncthreads() overhead.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Increased XTILE from 20 to 28. More x-positions processed per block reduces barrier overhead and improves register reuse.
- Status: correct
- Speedup: 2.7401
- Profile backend: ncu
- What I learned: Small improvement. Barrier stalls dropped from 36.1% to 34.8%, memory stalls from 20.4% to 19.4%. Median time 2.001ms. Bank conflicts still 662564 — suspect row-stride aliasing since BSIZE=16 doubles = 128 bytes = exactly 32 banks, so consecutive rows share banks when a warp spans two y-rows.
- Best speedup so far: 2.7401
- Next step: Add +1 padding to sm_psi shared memory rows to break bank aliasing.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Added BSIZE+1 padding to sm_psi shared memory to break bank aliasing.
- Status: correct
- Speedup: 2.7224
- Profile backend: ncu
- What I learned: Padding did NOT reduce bank conflicts (still 662564) — padding only changed smem size but the conflict source is elsewhere. Occupancy dropped slightly to 91.9%, slightly worse overall. Reverting to no-padding.
- Best speedup so far: 2.7401 (XTILE=28, no padding)
- Next step: Try removing the redundant __syncthreads() after z-neighbor read (line 112) — safe because the loop-end sync at line 125 already prevents proceeding to next iteration's sm_psi[3] write.

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Removed the __syncthreads() after z-neighbor read (after dV -= sm_psi[3][tkk-1]). Safe because the loop-end sync already barriers before the next iteration writes sm_psi[3] for ycharge.
- Status: correct
- Speedup: 2.7415
- Profile backend: ncu
- What I learned: Barrier stalls dropped from 34.8% to 33.5%. Short dependency stalls rose from 22.5% to 24.7% (the removed sync may have exposed more instruction-level dependencies). Overall ~marginal improvement. 4 syncthreads per iteration remain; the other 3 are necessary.
- Best speedup so far: 2.7415
- Next step: Try XTILE=40 to further reduce relative sync overhead per x-point processed.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Increased XTILE from 28 to 40.
- Status: correct
- Speedup: 2.7511
- Profile backend: ncu
- What I learned: Barrier stalls continued to drop (33.5%→32.2%). Occupancy dropped slightly to 90.2% (fewer blocks per SM). Bank conflicts slightly reduced to 659324. Still barrier-limited. Larger XTILE is helping by reducing the ratio of sync overhead to compute work.
- Best speedup so far: 2.7511
- Next step: Try XTILE=56 to see if the trend continues.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Increased XTILE from 40 to 56.
- Status: correct
- Speedup: 2.6891
- Profile backend: ncu
- What I learned: Too large — went too far. Fewer blocks (5×19×19=1805) reduced occupancy too much, hurting more than the sync-amortization gain. Reverting to XTILE=40 for final attempt. Optimum XTILE appears to be around 40.
- Best speedup so far: 2.7511 (XTILE=40)
- Next step: Last iteration — revert to XTILE=40 (best configuration) and try XTILE=48 to see if it's a slight sweet spot.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Changed XTILE from 56 to 48.
- Status: correct
- Speedup: 2.6411
- Profile backend: ncu
- What I learned: Still worse than XTILE=40 (2.7511). The sweet spot is around XTILE=40: bdimx=7 gives ~2527 blocks, enough to keep 128 SMs busy while amortizing sync overhead sufficiently. XTILE=48+ has too few x-blocks, hurting occupancy.
- Best speedup so far: 2.7511 (XTILE=40)
- Next step: All 7 successful iterations complete. Reverting code to best configuration (XTILE=40).
