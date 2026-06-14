#!/usr/bin/env python3
"""Generate report metrics and report-ready plots.

Inputs are the verified branch-level artifacts from analysis/report_artifacts.
The trajectory case plot uses trajectories already verified in
analysis/evidence/case_evidence_index.md, because the older trajectory.csv includes
out/latest rows that can confuse successful-iteration order.
"""

from __future__ import annotations

import csv
import math
import os
import shutil
from collections import defaultdict
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-agent-greed-analysis")

import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[2]
IN = ROOT / "analysis" / "report_artifacts" / "branch_summary.csv"
OUT = Path(__file__).resolve().parents[1]
DATA = OUT / "data"
NOTES = OUT / "notes"
PLOTS = OUT / "generated_plots"
ASSETS = ROOT / "report" / "paper_assets"


def read_rows() -> list[dict]:
    with IN.open(newline="") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        row["pref"] = int(float(row["planner_rank"]))
        row["speedup_iter1"] = float(row["speedup_iter1"])
        row["peak_speedup_7"] = float(row["peak_speedup_7"])
        row["peak_minus_iter1"] = float(row["peak_minus_iter1"])
    return rows


def geomean(values: list[float]) -> float:
    return math.exp(sum(math.log(v) for v in values) / len(values))


def slope(xs: list[float], ys: list[float]) -> float:
    xbar = sum(xs) / len(xs)
    ybar = sum(ys) / len(ys)
    return sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys)) / sum(
        (x - xbar) ** 2 for x in xs
    )


def normalized_penalty(rows: list[dict], condition: str, metric: str) -> float:
    points: list[tuple[int, float]] = []
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        if row["condition"] == condition:
            groups[row["kernel"]].append(row)

    for group in groups.values():
        gm = geomean([r[metric] for r in group])
        for row in group:
            points.append((row["pref"], row[metric] / gm))

    b = slope([p for p, _ in points], [q for _, q in points])
    return -100.0 * b


def normalized_penalty_for_group(group: list[dict], metric: str) -> float:
    gm = geomean([r[metric] for r in group])
    b = slope([r["pref"] for r in group], [r[metric] / gm for r in group])
    return -100.0 * b


def regret_by_kernel(rows: list[dict], condition: str, metric: str) -> list[dict]:
    out: list[dict] = []
    kernels = sorted({r["kernel"] for r in rows if r["condition"] == condition})
    for kernel in kernels:
        group = [r for r in rows if r["condition"] == condition and r["kernel"] == kernel]
        first = next(r for r in group if r["pref"] == 1)
        best = max(r[metric] for r in group)
        regret = (best - first[metric]) / best
        winner = next(r for r in group if abs(r[metric] - best) < 1e-12)
        out.append(
            {
                "kernel": kernel,
                "condition": condition,
                "metric": metric,
                "top_choice_speedup": first[metric],
                "best_speedup": best,
                "winner_pref": winner["pref"],
                "regret": regret,
            }
        )
    return out


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def plot_preference_penalty(metrics: list[dict]) -> None:
    labels = []
    values = []
    colors = []
    for cond in ["A", "B"]:
        for horizon in ["Iteration 1", "Peak over 7"]:
            row = next(m for m in metrics if m["condition"] == cond and m["horizon"] == horizon)
            labels.append(f"{cond}\n{horizon}")
            values.append(row["rank_step_penalty_percent"])
            colors.append("#6f8fc7" if horizon == "Iteration 1" else "#d08a57")

    fig, ax = plt.subplots(figsize=(5.4, 3.1))
    ax.axhline(0, color="#333333", linewidth=0.8)
    bars = ax.bar(labels, values, color=colors, edgecolor="#333333", linewidth=0.6)
    ax.set_ylabel("Speedup drop per rank step (%)")
    ax.set_title("Does Claude's ranking predict speedup?")
    for bar, value in zip(bars, values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            value + (0.25 if value >= 0 else -0.7),
            f"{value:.1f}%",
            ha="center",
            va="bottom" if value >= 0 else "top",
            fontsize=9,
        )
    ax.set_ylim(-1.5, 13)
    fig.tight_layout()
    fig.savefig(PLOTS / "preference_penalty.pdf")
    fig.savefig(PLOTS / "preference_penalty.png", dpi=200)
    plt.close(fig)


def plot_top_choice_regret(regret_summary: list[dict]) -> None:
    labels = []
    values = []
    colors = []
    for cond in ["A", "B"]:
        for horizon in ["Iteration 1", "Peak over 7"]:
            row = next(r for r in regret_summary if r["condition"] == cond and r["horizon"] == horizon)
            labels.append(f"{cond}\n{horizon}")
            values.append(100 * row["mean_regret"])
            colors.append("#6f8fc7" if horizon == "Iteration 1" else "#d08a57")

    fig, ax = plt.subplots(figsize=(5.4, 3.1))
    bars = ax.bar(labels, values, color=colors, edgecolor="#333333", linewidth=0.6)
    ax.set_ylabel("Speedup left on table by following P1 (%)")
    ax.set_title("Cost of following Claude's top pick (lower = better)")
    for bar, value in zip(bars, values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            value + 0.6,
            f"{value:.1f}%",
            ha="center",
            va="bottom",
            fontsize=9,
        )
    ax.set_ylim(0, max(values) * 1.25)
    fig.tight_layout()
    fig.savefig(PLOTS / "top_choice_regret.pdf")
    fig.savefig(PLOTS / "top_choice_regret.png", dpi=200)
    plt.close(fig)


def plot_per_kernel_penalty(per_kernel_rows: list[dict]) -> None:
    kernels = ["bitonic-sort", "histogram", "softmax", "stencil3d"]
    kernel_labels = ["bitonic-sort", "histogram", "softmax", "stencil3d"]
    conditions = ["A", "B"]
    cond_titles = {"A": "Condition A (default prompt)", "B": "Condition B (long-horizon prompt)"}

    col_iter1 = "#6f8fc7"
    col_peak7 = "#d08a57"
    bar_width = 0.35

    fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.4), sharey=True)
    for ax, cond in zip(axes, conditions):
        data = {r["kernel"]: r for r in per_kernel_rows if r["condition"] == cond}
        xs = range(len(kernels))
        iter1_vals = [data[k]["iter1_penalty_percent"] for k in kernels]
        peak7_vals = [data[k]["peak7_penalty_percent"] for k in kernels]

        bars1 = ax.bar(
            [x - bar_width / 2 for x in xs], iter1_vals,
            width=bar_width, label="Iteration 1",
            color=col_iter1, edgecolor="#333333", linewidth=0.6,
        )
        bars2 = ax.bar(
            [x + bar_width / 2 for x in xs], peak7_vals,
            width=bar_width, label="Peak over 7",
            color=col_peak7, edgecolor="#333333", linewidth=0.6,
        )
        ax.axhline(0, color="#333333", linewidth=0.8)
        ax.set_xticks(list(xs))
        ax.set_xticklabels(kernel_labels, fontsize=8, rotation=15, ha="right")
        ax.set_title(cond_titles[cond], fontsize=9)
        ax.set_xlabel("")

        for bar, val in list(zip(bars1, iter1_vals)) + list(zip(bars2, peak7_vals)):
            offset = 0.4 if val >= 0 else -1.2
            va = "bottom" if val >= 0 else "top"
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                val + offset,
                f"{val:.1f}",
                ha="center", va=va, fontsize=6.5,
            )

    axes[0].set_ylabel("Speedup drop per rank step (%)")
    axes[0].legend(fontsize=8, frameon=False, loc="upper right")
    fig.suptitle("Per-kernel preference alignment: Iteration 1 vs. Peak over 7", fontsize=10)
    fig.tight_layout()
    fig.savefig(PLOTS / "per_kernel_penalty.pdf")
    fig.savefig(PLOTS / "per_kernel_penalty.png", dpi=200)
    plt.close(fig)


def plot_trajectory_cases() -> None:
    cases = [
        (
            "Bitonic A",
            [
                ("P1 plateau", [1.382, 1.328, 1.381, 1.326, 1.382, 1.374, 1.382]),
                ("P3 late winner", [0.997, 1.176, 1.855, 1.829, 1.856, 2.366, 2.358]),
            ],
        ),
        (
            "Histogram B",
            [
                ("P2 recovery", [0.599, 1.633, 2.099, 1.774, 2.083, 2.286, 2.147]),
            ],
        ),
        (
            "Softmax A",
            [
                ("P1 read reduction", [1.360, 1.634, 1.653, 1.653, 1.652, 1.643, 1.485]),
                ("P5 latency hiding", [1.676, 1.673, 1.676, 1.676, 1.659, 1.677, 1.677]),
            ],
        ),
        (
            "Stencil3d B",
            [
                ("P1 dependency chain", [2.927, 2.927, 4.623, 4.608, 4.623, 4.719, 4.985]),
            ],
        ),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(7.2, 4.7))
    xs = list(range(1, 8))
    for ax, (title, series) in zip(axes.flat, cases):
        for label, ys in series:
            ax.plot(xs, ys, marker="o", linewidth=1.8, label=label)
        ax.axhline(1.0, color="#777777", linewidth=0.7, linestyle="--")
        ax.set_title(title, fontsize=10)
        ax.set_xlabel("Successful iteration")
        ax.set_ylabel("Speedup")
        ax.legend(fontsize=7, frameon=False)
    fig.suptitle("Trajectory archetypes from Worker logs", fontsize=12)
    fig.tight_layout()
    fig.savefig(PLOTS / "trajectory_cases.pdf")
    fig.savefig(PLOTS / "trajectory_cases.png", dpi=200)
    plt.close(fig)


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    NOTES.mkdir(parents=True, exist_ok=True)
    PLOTS.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    rows = read_rows()

    metric_names = {
        "speedup_iter1": "Iteration 1",
        "peak_speedup_7": "Peak over 7",
    }
    metric_rows: list[dict] = []
    for cond in ["A", "B"]:
        for metric, horizon in metric_names.items():
            metric_rows.append(
                {
                    "condition": cond,
                    "horizon": horizon,
                    "rank_step_penalty_percent": round(normalized_penalty(rows, cond, metric), 4),
                }
            )

    penalty = {
        (r["condition"], r["horizon"]): r["rank_step_penalty_percent"] for r in metric_rows
    }
    greediness_rows = [
        {
            "condition": cond,
            "iter1_penalty_percent": penalty[(cond, "Iteration 1")],
            "peak7_penalty_percent": penalty[(cond, "Peak over 7")],
            "greediness_percentage_points": round(
                penalty[(cond, "Iteration 1")] - penalty[(cond, "Peak over 7")], 4
            ),
        }
        for cond in ["A", "B"]
    ]

    per_kernel_penalty_rows = []
    for cond in ["A", "B"]:
        kernels = sorted({r["kernel"] for r in rows if r["condition"] == cond})
        for kernel in kernels:
            group = [r for r in rows if r["condition"] == cond and r["kernel"] == kernel]
            iter1 = normalized_penalty_for_group(group, "speedup_iter1")
            peak7 = normalized_penalty_for_group(group, "peak_speedup_7")
            per_kernel_penalty_rows.append(
                {
                    "kernel": kernel,
                    "condition": cond,
                    "iter1_penalty_percent": round(iter1, 4),
                    "peak7_penalty_percent": round(peak7, 4),
                    "greediness_percentage_points": round(iter1 - peak7, 4),
                }
            )

    regret_detail: list[dict] = []
    regret_summary: list[dict] = []
    for cond in ["A", "B"]:
        for metric, horizon in metric_names.items():
            detail = regret_by_kernel(rows, cond, metric)
            regret_detail.extend(detail)
            regret_summary.append(
                {
                    "condition": cond,
                    "horizon": horizon,
                    "mean_regret": sum(d["regret"] for d in detail) / len(detail),
                }
            )

    peak_rows = []
    for cond in ["A", "B"]:
        kernels = sorted({r["kernel"] for r in rows if r["condition"] == cond})
        for kernel in kernels:
            group = sorted(
                [r for r in rows if r["condition"] == cond and r["kernel"] == kernel],
                key=lambda r: r["pref"],
            )
            winner = max(group, key=lambda r: r["peak_speedup_7"])
            peak_rows.append(
                {
                    "kernel": kernel,
                    "condition": cond,
                    "P1": group[0]["peak_speedup_7"],
                    "P2": group[1]["peak_speedup_7"],
                    "P3": group[2]["peak_speedup_7"],
                    "P4": group[3]["peak_speedup_7"],
                    "P5": group[4]["peak_speedup_7"],
                    "winner": f"P{winner['pref']}",
                }
            )

    headroom_rows = []
    for row in rows:
        recovery = row["peak_speedup_7"] / row["speedup_iter1"]
        headroom_rows.append(
            {
                "kernel": row["kernel"],
                "condition": row["condition"],
                "preference_position": row["pref"],
                "speedup_iter1": row["speedup_iter1"],
                "peak_speedup_7": row["peak_speedup_7"],
                "headroom": row["peak_minus_iter1"],
                "recovery_ratio": recovery,
            }
        )

    write_csv(
        DATA / "metric_summary.csv",
        metric_rows,
        ["condition", "horizon", "rank_step_penalty_percent"],
    )
    write_csv(
        DATA / "greediness_summary.csv",
        greediness_rows,
        ["condition", "iter1_penalty_percent", "peak7_penalty_percent", "greediness_percentage_points"],
    )
    write_csv(
        DATA / "per_kernel_penalty.csv",
        per_kernel_penalty_rows,
        ["kernel", "condition", "iter1_penalty_percent", "peak7_penalty_percent", "greediness_percentage_points"],
    )
    write_csv(
        DATA / "top_choice_regret_by_kernel.csv",
        regret_detail,
        ["kernel", "condition", "metric", "top_choice_speedup", "best_speedup", "winner_pref", "regret"],
    )
    write_csv(
        DATA / "top_choice_regret_summary.csv",
        regret_summary,
        ["condition", "horizon", "mean_regret"],
    )
    write_csv(DATA / "peak_speedup_by_preference.csv", peak_rows, ["kernel", "condition", "P1", "P2", "P3", "P4", "P5", "winner"])
    write_csv(
        DATA / "headroom_recovery.csv",
        headroom_rows,
        ["kernel", "condition", "preference_position", "speedup_iter1", "peak_speedup_7", "headroom", "recovery_ratio"],
    )

    plot_preference_penalty(metric_rows)
    plot_top_choice_regret(regret_summary)
    plot_trajectory_cases()
    plot_per_kernel_penalty(per_kernel_penalty_rows)
    for name in ["preference_penalty.pdf", "top_choice_regret.pdf", "trajectory_cases.pdf", "per_kernel_penalty.pdf"]:
        shutil.copy2(PLOTS / name, ASSETS / name)

    lines = [
        "# Analysis2 Results Summary",
        "",
        "## Magnitude-Aware Preference Alignment",
        "",
        "| Condition | Horizon | Rank-step penalty |",
        "|---|---:|---:|",
    ]
    for row in metric_rows:
        lines.append(
            f"| {row['condition']} | {row['horizon']} | {row['rank_step_penalty_percent']:.1f}% |"
        )
    lines += [
        "",
        "## Greediness",
        "",
        "| Condition | Iter1 penalty | Peak7 penalty | Greediness |",
        "|---|---:|---:|---:|",
    ]
    for row in greediness_rows:
        lines.append(
            f"| {row['condition']} | {row['iter1_penalty_percent']:.1f}% | "
            f"{row['peak7_penalty_percent']:.1f}% | {row['greediness_percentage_points']:+.1f} pp |"
        )
    lines += [
        "",
        "## Top-Choice Regret",
        "",
        "| Condition | Horizon | Mean regret |",
        "|---|---:|---:|",
    ]
    for row in regret_summary:
        lines.append(f"| {row['condition']} | {row['horizon']} | {100 * row['mean_regret']:.1f}% |")
    lines += [
        "",
        "## Generated Artifacts",
        "",
        "- `data/metric_summary.csv`",
        "- `data/greediness_summary.csv`",
        "- `data/per_kernel_penalty.csv`",
        "- `data/top_choice_regret_by_kernel.csv`",
        "- `data/top_choice_regret_summary.csv`",
        "- `data/peak_speedup_by_preference.csv`",
        "- `data/headroom_recovery.csv`",
        "- `generated_plots/preference_penalty.pdf`",
        "- `generated_plots/top_choice_regret.pdf`",
        "- `generated_plots/trajectory_cases.pdf`",
        "- `report/paper_assets/preference_penalty.pdf`",
        "- `report/paper_assets/top_choice_regret.pdf`",
        "- `report/paper_assets/trajectory_cases.pdf`",
        "",
    ]
    (NOTES / "results_summary.md").write_text("\n".join(lines))


if __name__ == "__main__":
    main()
