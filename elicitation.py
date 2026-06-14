#!/usr/bin/env python3
import argparse
import json
import shutil
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parent


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def condition_prompt(condition: str) -> str:
    if condition == "A":
        return """You are a CUDA optimization expert. The user wants to optimize the CUDA kernel below.

Propose exactly five distinct optimization plans and rank them from highest to lowest priority based on what you would try first to improve this kernel's performance."""
    return """You are a CUDA optimization expert. A separate Claude Code Worker will execute each ranked plan for exactly 7 iterations.

Propose exactly five distinct optimization plans and rank them by which starting direction is most likely to achieve the highest peak speedup at any point within those 7 iterations. Consider how the first direction opens or blocks later optimizations."""


def build_planner_readme(kernel: str, condition: str, kernel_cfg: dict) -> str:
    root = repo_root()
    source_dir = root / kernel_cfg["source_dir"]
    source_sections = []
    for rel in kernel_cfg["allowed_files"]:
        path = source_dir / rel
        if path.exists():
            source_sections.append(f"## Source: `{rel}`\n\n```cuda\n{read_text(path)}\n```")

    digest_path = root / "baselines" / kernel / "baseline_digest.txt"
    digest = read_text(digest_path) if digest_path.exists() else "Baseline digest is not captured yet. Use source and reconnaissance notes only."
    notes = "\n".join(f"- {note}" for note in kernel_cfg.get("notes", [])) or "- None"

    return f"""# CUDA Kernel Optimization Request: {kernel}

{condition_prompt(condition)}

## First: Inspect And Measure

Before writing plans:

1. Inspect the copied kernel source in `planner/src/`.
2. Run the benchmark/profile command:

```bash
./benchmark.sh
```

3. Read these outputs when present:

```text
planner/out/run.json
```

Use the source and measured results to decide the ranked plans. Do not edit files in `planner/src/`; this step is for planning only.

## Output File

Write your answer to exactly this file:

```text
response.json
```

Do not write any other files.

## Required JSON Format

`response.json` must be a JSON array of exactly five objects. Each object may contain only these two fields:

```json
[
  {{
    "rank": 1,
    "plan": "Specific optimization plan..."
  }}
]
```

Rules:

- Include exactly five plans.
- Ranks must be integers 1 through 5 with no duplicates.
- Lower rank means higher priority.
- Each `plan` must be specific enough to implement directly.
- Each `plan` should include high-level steps, target bottleneck, what to be careful about, and correctness/performance risks.
- Do not include extra fields like name, id, files_to_modify, explanation, or estimated speedup.

## Kernel

`{kernel}`

## Editable Files

Only consider changes to these files:

```text
{chr(10).join(kernel_cfg["allowed_files"])}
```

## Reconnaissance Notes

{notes}

## Profiling Digest

```text
{digest}
```

## Source Snapshot

A copied source tree is available in `planner/src/`. The allowlisted files are also shown below for convenience.

{chr(10).join(source_sections)}
"""


def script(path: Path, target: Path) -> None:
    path.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        f"exec python3 {target}\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def benchmark_script(path: Path, root: Path, kernel: str) -> None:
    path.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        "HERE=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n"
        f"exec {root / 'run.sh'} {kernel} \"$HERE/planner/src\" \"$HERE/planner/out\"\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a Planner experiment workspace.")
    parser.add_argument("kernel")
    parser.add_argument("condition", choices=["A", "B"])
    parser.add_argument("--force", action="store_true", help="Allow recreating an empty experiment directory.")
    args = parser.parse_args()

    root = repo_root()
    config = load_json(root / "config" / "kernels.json")["kernels"]
    if args.kernel not in config:
        print(f"unknown kernel: {args.kernel}", file=sys.stderr)
        return 2

    exp_dir = root / "experiments" / args.kernel / f"cond_{args.condition}"
    if exp_dir.exists():
        if not args.force:
            print(f"experiment already exists: {exp_dir}", file=sys.stderr)
            print("Use a new kernel/condition directory or move the existing one aside.", file=sys.stderr)
            return 1
        if any(exp_dir.iterdir()):
            print(f"refusing to --force non-empty directory: {exp_dir}", file=sys.stderr)
            return 1
    exp_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(
        root / config[args.kernel]["source_dir"],
        exp_dir / "planner" / "src",
        ignore=shutil.ignore_patterns("main", "*.o", "__pycache__"),
    )

    (exp_dir / "experiment.json").write_text(
        json.dumps({"kernel": args.kernel, "condition": args.condition}, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (exp_dir / "README.md").write_text(build_planner_readme(args.kernel, args.condition, config[args.kernel]), encoding="utf-8")
    benchmark_script(exp_dir / "benchmark.sh", root, args.kernel)
    script(exp_dir / "validate.sh", root / "scripts" / "validate_elicitation.py")
    script(exp_dir / "create_workers.sh", root / "scripts" / "create_workers.py")
    script(exp_dir / "analyze.sh", root / "scripts" / "analyze_experiment.py")

    print(exp_dir)
    print()
    print("Next commands:")
    print(f"cd {exp_dir}")
    print("claude")
    print()
    print("Copy this into Claude:")
    print("Read README.md and write response.json exactly as instructed.")
    print()
    print("After Claude writes response.json:")
    print("./validate.sh")
    print("./create_workers.sh")
    print()
    print("After ./create_workers.sh, start one Claude Worker per branch.")
    print("For each workers/branch_N, run:")
    print(f"cd {exp_dir}/workers/branch_N")
    print("claude")
    print()
    print("Copy this into each Worker Claude:")
    print("Read README.md and strictly follow it.")
    print()
    print("After all five branches finish 7 successful iterations:")
    print(f"cd {exp_dir}")
    print("./analyze.sh")
    print("cat analysis/analysis.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
