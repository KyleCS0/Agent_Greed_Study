# Analysis Package

This directory contains the data and scripts used by the final report.

## Layout

```text
analysis/
  data/              Derived CSV metrics used in report tables
  evidence/          Qualitative log taxonomy and evidence index
  generated_plots/   Full generated plot outputs, PDF and PNG
  notes/             Short generated results summary
  report_artifacts/  Source CSVs used to regenerate metrics
  scripts/           Metric and plot generation script
```

## Regenerate

From repository root:

```bash
python3 analysis/scripts/compute_metrics.py
```

The script reads:

```text
analysis/report_artifacts/branch_summary.csv
```

and writes:

```text
analysis/data/*.csv
analysis/generated_plots/*
analysis/notes/results_summary.md
report/paper_assets/*.pdf
```
