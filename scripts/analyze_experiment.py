#!/usr/bin/env python3
import csv
import json
import math
from pathlib import Path


def load_json(path: Path) -> dict | list:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def avg_desc_ranks(items):
    valid = [(k, v) for k, v in items if isinstance(v, (int, float))]
    valid.sort(key=lambda kv: kv[1], reverse=True)
    ranks = {}
    i = 0
    while i < len(valid):
        j = i + 1
        while j < len(valid) and valid[j][1] == valid[i][1]:
            j += 1
        rank = (i + 1 + j) / 2.0
        for k in range(i, j):
            ranks[valid[k][0]] = rank
        i = j
    for k, v in items:
        if k not in ranks:
            ranks[k] = None
    return ranks


def spearman(pairs):
    if len(pairs) < 2:
        return None
    xs = [x for x, _ in pairs]
    ys = [y for _, y in pairs]
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    num = sum((x - mx) * (y - my) for x, y in pairs)
    dx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    dy = math.sqrt(sum((y - my) ** 2 for y in ys))
    return None if dx == 0 or dy == 0 else num / (dx * dy)


def result_from_run(path: Path) -> dict:
    data = load_json(path)
    if isinstance(data, dict) and isinstance(data.get("result"), dict):
        return data["result"]
    return data if isinstance(data, dict) else {}


def branch_row(branch: Path, rank: int) -> dict:
    out = branch / "out"
    all_runs = sorted(out.glob("run_*/run.json")) if out.exists() else []
    if not all_runs:
        all_runs = sorted(out.glob("run_*/result.json")) if out.exists() else []

    attempts = []
    successful = []
    for run in all_runs:
        result = result_from_run(run)
        row = {"path": str(run), "status": result.get("status"), "speedup": result.get("speedup")}
        attempts.append(row)
        if result.get("status") == "correct":
            successful.append(row)

    counted = successful[:7]
    speedups = [row["speedup"] for row in counted]
    valid_speedups = [s for s in speedups if isinstance(s, (int, float))]
    return {
        "rank": rank,
        "speedup_iter1": speedups[0] if speedups else None,
        "peak_speedup_7": max(valid_speedups) if valid_speedups else None,
        "num_successful_iterations": len(counted),
        "num_attempts_total": len(all_runs),
        "extra_successful_runs": max(0, len(successful) - 7),
        "attempt_statuses": [row["status"] for row in attempts],
        "counted_statuses": [row["status"] for row in counted],
    }


def main() -> int:
    condition_dir = Path.cwd()
    experiment = load_json(condition_dir / "experiment.json")
    rows = []
    for rank in range(1, 6):
        branch = condition_dir / "workers" / f"branch_{rank}"
        if not branch.exists():
            branch = condition_dir / f"branch_{rank}"
        rows.append(branch_row(branch, rank))
    short = avg_desc_ranks([(str(r["rank"]), r["speedup_iter1"]) for r in rows])
    long = avg_desc_ranks([(str(r["rank"]), r["peak_speedup_7"]) for r in rows])
    for row in rows:
        key = str(row["rank"])
        row["actual_rank_short"] = short[key]
        row["actual_rank_long"] = long[key]
    short_pairs = [(float(r["rank"]), float(r["actual_rank_short"])) for r in rows if r["actual_rank_short"] is not None]
    long_pairs = [(float(r["rank"]), float(r["actual_rank_long"])) for r in rows if r["actual_rank_long"] is not None]
    result = {
        "kernel": experiment["kernel"],
        "condition": experiment["condition"],
        "spearman_iter1": spearman(short_pairs),
        "spearman_peak7": spearman(long_pairs),
        "branches": rows,
    }
    out = condition_dir / "analysis"
    out.mkdir(exist_ok=True)
    (out / "analysis.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with (out / "analysis.csv").open("w", encoding="utf-8", newline="") as f:
        fields = ["rank", "speedup_iter1", "peak_speedup_7", "actual_rank_short", "actual_rank_long", "num_successful_iterations", "num_attempts_total", "extra_successful_runs"]
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field) for field in fields})
    print(out / "analysis.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
