# Analysis2 Results Summary

## Magnitude-Aware Preference Alignment

| Condition | Horizon | Rank-step penalty |
|---|---:|---:|
| A | Iteration 1 | 3.0% |
| A | Peak over 7 | -0.0% |
| B | Iteration 1 | 2.9% |
| B | Peak over 7 | 11.2% |

## Greediness

| Condition | Iter1 penalty | Peak7 penalty | Greediness |
|---|---:|---:|---:|
| A | 3.0% | -0.0% | +3.0 pp |
| B | 2.9% | 11.2% | -8.3 pp |

## Top-Choice Regret

| Condition | Horizon | Mean regret |
|---|---:|---:|
| A | Iteration 1 | 11.7% |
| A | Peak over 7 | 26.1% |
| B | Iteration 1 | 5.3% |
| B | Peak over 7 | 10.8% |

## Generated Artifacts

- `data/metric_summary.csv`
- `data/greediness_summary.csv`
- `data/per_kernel_penalty.csv`
- `data/top_choice_regret_by_kernel.csv`
- `data/top_choice_regret_summary.csv`
- `data/peak_speedup_by_preference.csv`
- `data/headroom_recovery.csv`
- `generated_plots/preference_penalty.pdf`
- `generated_plots/top_choice_regret.pdf`
- `generated_plots/trajectory_cases.pdf`
- `report/paper_assets/preference_penalty.pdf`
- `report/paper_assets/top_choice_regret.pdf`
- `report/paper_assets/trajectory_cases.pdf`
