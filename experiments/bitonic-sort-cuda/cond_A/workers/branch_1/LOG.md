# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: yes
- Successful iteration number: 1
- Change: Added fused shared-memory kernel `bitonic_sort_shared`. Each block loads a tile of 2*BLOCK_SIZE=512 elements into smem, then processes all stages where seq_len <= TILE (stages 0..8) in a single kernel call, eliminating hundreds of global kernel launches. Thread `tid` maps to the tid-th compare-swap pair in the tile: seq_in_tile=tid/h_len, local_i=seq_in_tile*seq_len+tid%h_len, local_j=local_i+h_len. Global kernel still handles large stages (seq_len > 512).
- Status: correct
- Speedup: 1.3822
- Profile backend: ncu
- What I learned: Fusing smem stages gives 1.38x speedup. Occupancy improved to 92.2% (from 80.1%). However, significant smem bank conflicts detected (524K load, 518K store) due to non-stride-1 access in small stages (seq_len < BLOCK_SIZE). Registers/thread increased to 39 (from 16). Global load efficiency improved from 50% to 100%.
- Best speedup so far: 1.3822
- Next step: Fix smem bank conflicts by using warp shuffle (`__shfl_xor_sync`) for stages 0..4 (seq_len <= 32), which fit within a single warp's elements. This should reduce bank conflicts and potentially improve performance further.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 2
- Change: Added smem padding (SMEM_PAD macro: p + p/32) to try to eliminate bank conflicts. Used 528-element smem instead of 512.
- Status: correct
- Speedup: 1.32766
- Profile backend: ncu
- What I learned: Padding increased index computation overhead and smem size, hurting performance. Reverted.
- Best speedup so far: 1.3822 (attempt 1)
- Next step: Revert to attempt 1 code, explore other optimizations.

## Attempt 3

- Counted iteration: yes
- Successful iteration number: 3
- Change: Reverted to clean smem kernel from attempt 1 (no padding). Same implementation.
- Status: correct
- Speedup: 1.38132
- Profile backend: ncu
- What I learned: Consistent 1.38x speedup confirms the smem fused kernel is stable.
- Best speedup so far: 1.3822 (attempt 1)
- Next step: Try BLOCK_SIZE=512 to capture one more stage in smem (stage 9).

## Attempt 4

- Counted iteration: yes
- Successful iteration number: 4
- Change: Increased BLOCK_SIZE from 256 to 512.
- Status: correct
- Speedup: 1.32565
- Profile backend: ncu
- What I learned: Larger blocks reduce occupancy. BLOCK_SIZE=512 hurts. Reverted to BLOCK_SIZE=256.
- Best speedup so far: 1.3822 (attempt 1)
- Next step: Try __ldg for read-only loads in global kernel.

## Attempt 5

- Counted iteration: yes
- Successful iteration number: 5
- Change: Reverted to BLOCK_SIZE=256. Same as attempt 1/3.
- Status: correct
- Speedup: 1.38184
- Profile backend: ncu
- What I learned: BLOCK_SIZE=256 consistently gives ~1.382x speedup.
- Best speedup so far: 1.3822 (attempt 1)
- Next step: Try __ldg in global kernel.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 6
- Change: Added `__ldg` to global kernel reads.
- Status: correct
- Speedup: 1.37384
- Profile backend: ncu
- What I learned: `__ldg` slightly worse (1.374 vs 1.382). Read-only cache doesn't help since same locations are both read and written. Reverted.
- Best speedup so far: 1.3822 (attempt 1)
- Next step: Revert and run final iteration with best code.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 7
- Change: Reverted `__ldg`. Final run with best performing code (smem fused kernel, BLOCK_SIZE=256).
- Status: correct
- Speedup: 1.38186
- Profile backend: ncu
- What I learned: The smem fused kernel consistently delivers ~1.382x speedup. Main gains: fusing 9 stages/step into one kernel launch, keeping inner stages in smem. Further improvement would require fixing smem bank conflicts or reducing register pressure (39 regs/thread).
- Best speedup so far: 1.38186
- Next step: All 7 iterations complete.
