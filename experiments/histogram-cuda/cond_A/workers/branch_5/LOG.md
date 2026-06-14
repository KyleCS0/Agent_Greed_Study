# Worker Log

Record every attempt. Only attempts where `out/latest_run.json` has `status: "correct"` count toward the 7 successful iterations.

## Attempt 1

- Counted iteration: no
- Successful iteration number: N/A
- Change: Changed `unsigned int smem[...]` to `unsigned short smem[...]` and used `atomicAdd` with `(unsigned short)1` cast.
- Status: compile_error - no overload for `atomicAdd(unsigned short*, unsigned short)` in CUDA headers for sm_60.
- Speedup: null
- Profile backend: N/A
- What I learned: CUDA does not provide a native `atomicAdd(unsigned short*, unsigned short)` overload in sm_60 device headers. The 16-bit atomicAdd intrinsic mentioned in the plan requires sm_70+ or uses __half types.
- Best speedup so far: N/A
- Next step: Implement a CAS-based 16-bit atomic add helper.

## Attempt 2

- Counted iteration: yes
- Successful iteration number: 1
- Change: Replaced missing `atomicAdd(unsigned short*, unsigned short)` with a custom CAS-loop `atomicAddU16` using 32-bit `atomicCAS` on the containing word.
- Status: correct
- Speedup: 0.655637
- Profile backend: ncu
- What I learned: CAS-based 16-bit atomics are slower than native 32-bit atomicAdd because the retry loop adds overhead. Halving smem usage did not overcome the CAS penalty on sm_60.
- Best speedup so far: 0.655637 (but worse than baseline)
- Next step: Try PTX `atom.shared.add.u16` to avoid CAS overhead.

## Attempt 3

- Counted iteration: no
- Successful iteration number: N/A
- Change: Replaced CAS helper with inline PTX `atom.shared.add.u16` using `"l"` constraint for address.
- Status: compile_error - ptxas error: "Unexpected instruction types specified for 'atom'" (wrong address constraint).
- Speedup: null
- Profile backend: N/A
- What I learned: `atom.shared.add.u16` exists in PTX but requires correct operand types. The `"l"` constraint was wrong for shared memory address.
- Best speedup so far: 0.655637 (worse than baseline)
- Next step: Use `__cvta_generic_to_shared` to get 32-bit shared memory address with `"r"` constraint.

## Attempt 4

- Counted iteration: no
- Successful iteration number: N/A
- Change: Fixed PTX constraint to use `"r"(__cvta_generic_to_shared(addr))` (32-bit shared address).
- Status: compile_error - ptxas error: "Unexpected instruction types specified for 'atom'" - `atom.shared.add.u16` is not supported on sm_60 (requires sm_70+ PTX ISA 6.2).
- Speedup: null
- Profile backend: N/A
- What I learned: PTX `atom.add.u16` was introduced in PTX ISA 6.2 which requires sm_70+. On sm_60 there is no native 16-bit atomic add - only CAS-based workarounds. The README plan's claim about sm_60+ is incorrect for 16-bit atomicAdd.
- Best speedup so far: 0.655637 (worse than baseline)
- Next step: Revert to baseline 32-bit smem and try a different optimization.

## Attempt 5

- Counted iteration: no
- Successful iteration number: N/A
- Change: Tried fixing PTX with `unsigned int saddr = __cvta_generic_to_shared(addr)` before asm.
- Status: compile_error - same ptxas error, sm_60 does not support atom.add.u16.
- Speedup: null
- Profile backend: N/A
- What I learned: Confirmed atom.add.u16 requires sm_70+. Must abandon 16-bit PTX approach for sm_60.
- Best speedup so far: 0.655637 (worse than baseline)
- Next step: Revert smem to 32-bit and explore block/grid tuning to improve occupancy.

## Attempt 6

- Counted iteration: yes
- Successful iteration number: 2
- Change: Reverted `histogram_smem_atomics.h` to original baseline with `unsigned int smem[...]` and standard `atomicAdd`.
- Status: correct
- Speedup: 0.999516
- Profile backend: ncu
- What I learned: Baseline is restored. Low occupancy (16.5%) and memory latency stalls (87.2%) are the main bottlenecks. Need to increase warps per SM.
- Best speedup so far: 0.999516
- Next step: Increase block size from 32x4=128 to 32x8=256 threads to increase warp count and hide memory latency.

## Attempt 7

- Counted iteration: yes
- Successful iteration number: 3
- Change: Changed block from `(32, 4)` to `(32, 8)` (128 -> 256 threads per block).
- Status: correct
- Speedup: 1.29558
- Profile backend: ncu
- What I learned: More threads per block significantly improves latency hiding. 2x more warps gives ~1.3x speedup.
- Best speedup so far: 1.29558
- Next step: Try 32x16=512 threads per block for even more latency hiding.

## Attempt 8

- Counted iteration: yes
- Successful iteration number: 4
- Change: Changed block from `(32, 8)` to `(32, 16)` (256 -> 512 threads per block).
- Status: correct
- Speedup: 1.51937
- Profile backend: ncu
- What I learned: 512 threads per block further improves latency hiding. Occupancy increases with more warps.
- Best speedup so far: 1.51937
- Next step: Try 32x32=1024 threads per block to see if further gains are possible.

## Attempt 9

- Counted iteration: yes
- Successful iteration number: 5
- Change: Changed block from `(32, 16)` to `(32, 32)` (512 -> 1024 threads per block).
- Status: correct
- Speedup: 1.51909
- Profile backend: ncu
- What I learned: 1024 threads gives nearly the same speedup as 512. Sweet spot is around 512 threads. Register/smem constraints limit further gains at 1024 threads.
- Best speedup so far: 1.51937 (from attempt 8, block 32x16)
- Next step: Revert to best config (32x16) and try larger grid to see if that helps.

## Attempt 10

- Counted iteration: yes
- Successful iteration number: 6
- Change: Changed grid from `(16, 16)` to `(32, 16)` (256 -> 512 blocks, keeping block at 32x16).
- Status: correct
- Speedup: 0.985645
- Profile backend: ncu
- What I learned: Larger grid is slower - more blocks increases accumulation kernel work proportionally and offsets any first-pass parallelism gains.
- Best speedup so far: 1.51937 (attempt 8, block 32x16, grid 16x16)
- Next step: Return to best config and run more iterations.

## Attempt 11

- Counted iteration: yes
- Successful iteration number: 6
- Change: Reverted to best config: block `(32, 16)`, grid `(16, 16)`.
- Status: correct
- Speedup: 1.51844
- Profile backend: ncu
- What I learned: Best configuration confirmed: 32x16 block, 16x16 grid gives consistent ~1.52x speedup.
- Best speedup so far: 1.51937
- Next step: Run one final iteration with best config to reach 7 total.

## Attempt 12

- Counted iteration: no (iteration_limit reached by system - 7 successful runs already counted)
- Successful iteration number: N/A
- Change: No source change; re-ran best config.
- Status: iteration_limit (system reports successful_runs: 7, meaning 7 successful iterations completed)
- Speedup: null
- Profile backend: N/A
- What I learned: The system tracks successful iterations internally and stops after 7 are reached. Run 011 was the 7th successful iteration.
- Best speedup so far: 1.51937
- Next step: Task complete. 7 successful iterations achieved with best speedup of ~1.52x.
