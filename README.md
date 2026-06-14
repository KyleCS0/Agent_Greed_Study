# Are Coding Agents Too Greedy?
### Measuring Short-Horizon Bias in LLM-Driven GPU Kernel Optimization

> **Kuan-Lei Wu · Sheng Chen · Young Lee**

Does Claude's optimization ranking predict which direction reaches the best final speedup — or just which one looks good first?

We ran a controlled Planner/Worker experiment across four CUDA kernels: Claude ranks five candidate plans before any implementation occurs, then each plan is executed independently for 7 iterations. Two prompt conditions: default vs. explicit long-horizon framing.

---

![Speedup drop per rank step](analysis/generated_plots/preference_penalty.png)

**Default prompt:** ranking predicts 3.0% of iteration-1 speedup but ~0% of final speedup. **Long-horizon prompt:** final-speedup alignment rises to 11.2% per rank step; cost of following the top pick drops from 26.1% to 10.8%.

![Per-kernel penalty](analysis/generated_plots/per_kernel_penalty.png)

Histogram A (default) has a −5.3% final-speedup penalty — Claude's top pick is actively worse than random for that kernel.

---

## Repo Layout

```
experiments/<kernel>/cond_<A|B>/
  response.json          Claude's ranked plans
  workers/branch_<1-5>/
    LOG.md               Worker iteration log with profiler evidence
    out/run_*/run.json   Per-iteration timing and correctness
analysis/
  generated_plots/       All figures
  scripts/compute_metrics.py
report/final_report.tex
```

Regenerate all metrics and plots:
```bash
python3 analysis/scripts/compute_metrics.py
```
