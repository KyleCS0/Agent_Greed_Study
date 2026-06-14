# Case Evidence Index

This file maps report claims to concrete log evidence. Use it when drafting the discussion so every qualitative category is traceable to raw Worker output.

## Evidence Table

| Claim | Source | Short excerpt | Report use |
|---|---|---|---|
| Bitonic A P1 is an immediate plateau. | `experiments/bitonic-sort-cuda/cond_A/workers/branch_1/LOG.md` | "Fusing smem stages gives 1.38x speedup... significant smem bank conflicts... Registers/thread increased to 39." | Shows a plausible first edit with limited later headroom. |
| Bitonic A P1 remains stable but capped. | `experiments/bitonic-sort-cuda/cond_A/workers/branch_1/LOG.md` | "The smem fused kernel consistently delivers ~1.382x speedup... Further improvement would require fixing smem bank conflicts or reducing register pressure." | Supports immediate-win plateau category. |
| Bitonic A P3 starts weak because the first edit targets the wrong cost. | `experiments/bitonic-sort-cuda/cond_A/workers/branch_3/LOG.md` | "Host-side pow() elimination had negligible effect since GPU kernel time dominates." | Shows why first-iteration speedup can understate trajectory value. |
| Bitonic A P3 discovers the real structural path. | `experiments/bitonic-sort-cuda/cond_A/workers/branch_3/LOG.md` | "Global load efficiency improved to 100%, occupancy to 92.4%. Shared memory approach is the right direction." | Shows productive recovery after weak first step. |
| Bitonic A P3 wins through divergence-free mapping. | `experiments/bitonic-sort-cuda/cond_A/workers/branch_3/LOG.md` | "Eliminating the conditional divergence in the global kernel and ensuring all threads do useful work greatly improved throughput." | Explains why the lower-preference direction reaches 2.366x. |
| Histogram A P1 targets a metric that does not move. | `experiments/histogram-cuda/cond_A/workers/branch_1/LOG.md` | "Global load efficiency remained at 57% after the swap... performance gain... negligible or slightly negative." | Supports salient metric fixation. |
| Histogram A P1 stays below baseline. | `experiments/histogram-cuda/cond_A/workers/branch_1/LOG.md` | "Final state... gives stable ~0.97 speedup... load efficiency (still 57%)." | Shows a non-causal metric fix. |
| Histogram B P2 starts badly due to under-parallelization. | `experiments/histogram-cuda/cond_B/workers/branch_2/LOG.md` | "64 blocks is not enough to cover the 1920x1080 image efficiently... serializing work." | Supports recoverable bad first implementation. |
| Histogram B P2 recovers after grid sizing. | `experiments/histogram-cuda/cond_B/workers/branch_2/LOG.md` | "Matching the original grid size recovers parallelism... eliminated the second kernel launch... and the global write+read round-trip." | Shows the strategy was strong despite a poor first step. |
| Histogram B P2 finds a parallelism/contention sweet spot. | `experiments/histogram-cuda/cond_B/workers/branch_2/LOG.md` | "20x20=400 blocks achieves 2.29x speedup... keeping global atomic contention manageable." | Explains the 2.286x peak. |
| Softmax A P1 reduces traffic but loses occupancy. | `experiments/softmax-cuda/cond_A/workers/branch_1/LOG.md` | "Smem reduced global loads from 3x to 1x and halved expf, but occupancy dropped from 74.1% to 30.7%." | Supports correct bottleneck, wrong mechanism. |
| Softmax A P1 recovers by abandoning shared memory. | `experiments/softmax-cuda/cond_A/workers/branch_1/LOG.md` | "dest-as-buffer strategy works well. Occupancy rose to 78.2%... Memory stall 95% -- still latency-limited." | Shows Worker recovery and persistent latency bottleneck. |
| Softmax A P1 shows resource tradeoff cancellation. | `experiments/softmax-cuda/cond_A/workers/branch_1/LOG.md` | "Memory stall dropped... but registers jumped from 28 to 37. Net speedup essentially unchanged." | Shows local metric improvement can be neutralized. |
| Softmax A P5 wins by hiding latency. | `experiments/softmax-cuda/cond_A/workers/branch_5/LOG.md` | "Occupancy jumped from 74.1% to 94.7%. Memory stalls dropped from 94.5% to 60.1%." | Shows why latency hiding beats read reduction. |
| Softmax A P5 proves fewer reads were not enough. | `experiments/softmax-cuda/cond_A/workers/branch_5/LOG.md` | "Load bandwidth dropped... But speedup unchanged... extra expf in merge operation offsets savings." | Supports mechanism distinction: traffic reduction vs latency hiding. |
| Softmax A P5 identifies the hard floor. | `experiments/softmax-cuda/cond_A/workers/branch_5/LOG.md` | "Speedup unchanged -- kernel is fundamentally memory-latency limited... bottleneck is DRAM/L2 latency, not compute or bandwidth." | Strongest log evidence for causal mechanism. |
| Softmax B P1 is an elegant loser. | `experiments/softmax-cuda/cond_B/workers/branch_1/LOG.md` | "Online softmax cuts memory stalls... Load BW dropped... Regs/thread increased from 19 to 32." | Shows online softmax helps some metrics but not enough. |
| Softmax B P1 regresses when chasing more traffic reduction. | `experiments/softmax-cuda/cond_B/workers/branch_1/LOG.md` | "Register caching hurt performance significantly... increased register pressure... local memory spilling." | Supports elegance/resource-tradeoff failure. |
| Softmax B P5 wins with a simple hardware knob. | `experiments/softmax-cuda/cond_B/workers/branch_5/LOG.md` | "BLOCK_SIZE=512 improved from 1.48x to 1.55x. More warps per SM improves scheduler utilization." | Supports simple tuning winner / elegance bias. |
| Softmax B P5 later tweaks are mostly noise. | `experiments/softmax-cuda/cond_B/workers/branch_5/LOG.md` | "Final best is attempt 2 (1.553x, BLOCK_SIZE=512 alone)." | Shows the main causal lever was simple launch configuration. |
| Stencil3d B P1 begins with a foundational resource change. | `experiments/stencil3d-cuda/cond_B/workers/branch_1/LOG.md` | "Float halved memory traffic and boosted occupancy 79.6%->96.7%." | Supports dependency-chain success. |
| Stencil3d B P1 uses profile evidence to choose the next move. | `experiments/stencil3d-cuda/cond_B/workers/branch_1/LOG.md` | "Dominant bottlenecks... global load efficiency 66%... change to blocks(32, 8, 1)." | Shows evidence-based local reasoning. |
| Stencil3d B P1 compounds through coalescing. | `experiments/stencil3d-cuda/cond_B/workers/branch_1/LOG.md` | "Global load efficiency improved 66%->80.9%, load bandwidth 578->773 GB/s." | Explains jump from 2.927x to 4.623x. |
| Stencil3d B P1 compounds through XTILE tuning. | `experiments/stencil3d-cuda/cond_B/workers/branch_1/LOG.md` | "XTILE=32 pushed load bandwidth to 826.8 GB/s... trend... 4.623->4.719->4.985." | Explains final 4.985x peak. |
| Stencil3d B P4 shows metric improvement can be canceled. | `experiments/stencil3d-cuda/cond_B/workers/branch_4/LOG.md` | "Bank conflicts dropped dramatically... but occupancy fell from 78.5% to 56.1%." | Supports resource-tradeoff miss category. |
| Stencil3d B P4 has marginal net gain despite fixing conflicts. | `experiments/stencil3d-cuda/cond_B/workers/branch_4/LOG.md` | "The bank-conflict fix via padding and the occupancy penalty nearly cancel out." | Shows why one-metric optimization is insufficient. |

## Case-To-Report Mapping

### Bitonic A

Use for:

- immediate plateau
- slow-start winner
- first-step speedup can hide limited headroom

Main evidence:

```text
P1: 1.382x first step and 1.382x peak.
P3: 0.997x first step and 2.366x peak.
```

### Histogram A/B

Use for:

- salient metric fixation
- recoverable bad first implementation
- productive recovery through grid tuning

Main evidence:

```text
Histogram A P1: load efficiency stayed 57%, speedup stayed ~0.97x.
Histogram B P2: 0.599x first step, 2.286x peak after grid tuning.
```

### Softmax A/B

Use for:

- correct bottleneck, wrong mechanism
- elegance bias
- traffic reduction vs latency hiding
- close-cluster magnitude lesson

Main evidence:

```text
Softmax A P1: reads 3x->1x, occupancy 74.1%->30.7%, peak 1.653x.
Softmax A P5: occupancy 74.1%->94.7%, stalls 94.5%->60.1%, peak 1.677x.
Softmax B P1: online softmax peak 1.438x.
Softmax B P5: BLOCK_SIZE=512 peak 1.553x.
```

### Stencil3d B

Use for:

- successful long-horizon dependency chain
- evidence-based local reasoning
- resource-tradeoff cancellation via P4

Main evidence:

```text
P1: 2.927x -> 4.623x -> 4.985x.
P4: bank conflicts 35.6M -> 819K, but occupancy 78.5% -> 56.1%.
```

