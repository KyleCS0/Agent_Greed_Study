# Agent Greed CUDA Experiment

This repository contains the code, curated experiment traces, analysis
artifacts, and final report for:

> Does Claude Optimize for the First Step?

The experiment asks whether Claude's first-ranked CUDA optimization plan is
aligned with immediate speedup or with the best speedup found after continuing
optimization.

## Repository Layout

```text
report/                 Final LaTeX report, PDF, and plot assets
analysis/               CSV metrics, plots, qualitative evidence, scripts
experiments/            Curated Planner/Worker prompts, outputs, logs, run JSON
baselines/              Baseline timing/profile summaries
config/                 Kernel configuration
scripts/                Experiment harness utilities
tests/                  Small parser/validation fixtures
vendor/HeCBench         HecBench benchmark submodule
```

## Final Report

The submission source is:

```text
report/final_report.tex
```

Compile from `report/`:

```bash
pdflatex -interaction=nonstopmode -halt-on-error final_report.tex
pdflatex -interaction=nonstopmode -halt-on-error final_report.tex
```

The compiled PDF is also committed at:

```text
report/final_report.pdf
```

## Regenerate Analysis Artifacts

From repository root:

```bash
python3 analysis/scripts/compute_metrics.py
```

This reads `analysis/report_artifacts/branch_summary.csv` and writes:

```text
analysis/data/*.csv
analysis/generated_plots/*
analysis/notes/results_summary.md
report/paper_assets/*.pdf
```

## Experiment Evidence

Each condition keeps the prompt surface and Planner output:

```text
experiments/<kernel>/cond_<A|B>/README.md
experiments/<kernel>/cond_<A|B>/response.json
experiments/<kernel>/cond_<A|B>/analysis/analysis.json
```

Each Worker branch keeps the assigned task, log, source snapshot, and run
summaries:

```text
experiments/<kernel>/cond_<A|B>/workers/branch_<rank>/README.md
experiments/<kernel>/cond_<A|B>/workers/branch_<rank>/LOG.md
experiments/<kernel>/cond_<A|B>/workers/branch_<rank>/src/
experiments/<kernel>/cond_<A|B>/workers/branch_<rank>/out/run_*/run.json
```

Raw profiler dumps, binaries, object files, private audit logs, and LaTeX
intermediates are intentionally excluded.

## Experiment Plan

The high-level design and rationale are kept in:

```text
EXPERIMENT_PLAN.md
```
