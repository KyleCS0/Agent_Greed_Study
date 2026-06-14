#!/usr/bin/env python3
import json
import math
import re
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_kernel_config(kernel: str) -> dict:
    config_path = repo_root() / "config" / "kernels.json"
    with config_path.open("r", encoding="utf-8") as f:
        config = json.load(f)["kernels"]
    if kernel not in config:
        raise KeyError(f"unknown kernel: {kernel}")
    return config[kernel]["correctness"]


def numbers(text: str) -> list[float]:
    return [float(x) for x in re.findall(r"[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?", text)]


def compare_numeric(current: str, reference: str, rel_tol: float, abs_tol: float) -> tuple[bool, str]:
    cur = numbers(current)
    ref = numbers(reference)
    if len(cur) != len(ref):
        return False, f"numeric length mismatch: current={len(cur)} reference={len(ref)}"
    worst = 0.0
    worst_i = -1
    for i, (a, b) in enumerate(zip(cur, ref)):
        err = abs(a - b)
        allowed = max(abs_tol, rel_tol * max(abs(b), abs_tol))
        if err > allowed:
            return False, f"value {i} mismatch: current={a} reference={b} err={err} allowed={allowed}"
        if allowed > 0:
            scaled = err / allowed
            if scaled > worst:
                worst = scaled
                worst_i = i
    return True, f"numeric comparison passed ({len(cur)} values, worst_scaled_error={worst:.6g} at {worst_i})"


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: check_correctness.py <kernel> <output_file> <reference_file>")
        return 2

    kernel = sys.argv[1]
    output_file = Path(sys.argv[2])
    reference_file = Path(sys.argv[3])
    cfg = load_kernel_config(kernel)

    current = output_file.read_text(encoding="utf-8", errors="replace")
    method = cfg.get("method", "reference_compare")

    if method == "pass_token":
        token = cfg["pass_token"]
        if token in current:
            print(f"pass token found: {token}")
            return 0
        print(f"missing pass token: {token}")
        return 1

    if not reference_file.exists():
        print(f"missing reference output: {reference_file}")
        return 1

    reference = reference_file.read_text(encoding="utf-8", errors="replace")
    if method == "exact":
        if current == reference:
            print("exact comparison passed")
            return 0
        print("exact comparison failed")
        return 1

    rel_tol = float(cfg.get("relative_tolerance", 0.0))
    abs_tol = float(cfg.get("absolute_tolerance", 0.0))
    ok, message = compare_numeric(current, reference, rel_tol, abs_tol)
    print(message)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

