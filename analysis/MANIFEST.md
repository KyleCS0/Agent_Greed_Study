# Analysis Manifest

## Source Artifacts

```text
analysis/report_artifacts/branch_summary.csv
analysis/report_artifacts/trajectory.csv
analysis/report_artifacts/measurement_quality.csv
analysis/report_artifacts/rho_summary.csv
```

## Derived Data

```text
analysis/data/metric_summary.csv
analysis/data/greediness_summary.csv
analysis/data/per_kernel_penalty.csv
analysis/data/top_choice_regret_summary.csv
analysis/data/top_choice_regret_by_kernel.csv
analysis/data/peak_speedup_by_preference.csv
analysis/data/headroom_recovery.csv
```

## Evidence

```text
analysis/evidence/log_taxonomy.csv
analysis/evidence/case_evidence_index.md
```

## Report Plots

```text
report/paper_assets/preference_penalty.pdf
report/paper_assets/top_choice_regret.pdf
report/paper_assets/trajectory_cases.pdf
```

## Regeneration Command

```bash
python3 analysis/scripts/compute_metrics.py
```
