#!/usr/bin/env python3
import json
import math
import os
import re
import fnmatch
import hashlib
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path


NCU_METRICS = [
    "sm__warps_active.avg.pct_of_peak_sustained_active",
    "smsp__pipe_fma_cycles_active.avg.pct_of_peak_sustained_active",
    "l1tex__t_bytes_pipe_lsu_mem_global_op_ld.sum.per_second",
    "l1tex__t_bytes_pipe_lsu_mem_global_op_st.sum.per_second",
    "smsp__sass_average_data_bytes_per_sector_mem_global_op_ld.pct",
    "l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_ld.sum",
    "l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_st.sum",
    "smsp__warp_issue_stalled_long_scoreboard_per_warp_active.pct",
    "smsp__warp_issue_stalled_barrier_per_warp_active.pct",
    "smsp__warp_issue_stalled_short_scoreboard_per_warp_active.pct",
    "smsp__warp_issue_stalled_wait_per_warp_active.pct",
    "smsp__warp_issue_stalled_selected_per_warp_active.pct",
    "lts__t_sectors_srcunit_tex_op_read_hit_rate.pct",
]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def append_text(path: Path, text: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(text)
    if mode is not None:
        path.chmod(mode)


def run_command(argv: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def run_ncu_command(argv: list[str], cwd: Path) -> tuple[subprocess.CompletedProcess, str]:
    sudo = shutil.which("sudo")
    ncu = shutil.which("ncu")
    if sudo and ncu:
        sudo_proc = run_command([sudo, "-n", ncu, *argv], cwd)
        if "password is required" not in sudo_proc.stdout.lower():
            return sudo_proc, "sudo -n ncu"
    return run_command(["ncu", *argv], cwd), "ncu"


def unit_to_ms(value: float, unit: str) -> float:
    unit = unit.lower()
    if unit == "ms":
        return value
    if unit == "s":
        return value * 1000.0
    if unit == "us":
        return value / 1000.0
    return value


def extract_timing(output: str, timing_cfg: dict) -> float:
    pattern = re.compile(timing_cfg["regex"])
    matches = pattern.findall(output)
    if not matches:
        raise ValueError("timing regex did not match program output")
    value = matches[0]
    if isinstance(value, tuple):
        value = value[0]
    return float(value)


def rel_stddev(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    mean = statistics.mean(values)
    if mean == 0:
        return 0.0
    return statistics.stdev(values) / mean


def baseline_value(kernel: str, unit: str, higher_is_better: bool) -> float | None:
    path = repo_root() / "baselines" / kernel / "baseline.json"
    if not path.exists():
        return None
    data = load_json(path)
    for key in ("baseline_median_ms", "median_ms", "baseline_median"):
        if isinstance(data.get(key), (int, float)):
            return float(data[key])
    observed = data.get("observed_single_run", {})
    if isinstance(observed, dict):
        if isinstance(observed.get("median_ms"), (int, float)):
            return float(observed["median_ms"])
        sample_key = f"sample_{unit.lower()}"
        if isinstance(observed.get(sample_key), (int, float)):
            return unit_to_ms(float(observed[sample_key]), unit)
    return None


def find_run_context(start: Path) -> Path | None:
    env = os.environ.get("AGENT_GREED_RUN_CONTEXT")
    if env:
        candidate = Path(env)
        if candidate.exists():
            return candidate.resolve()
    current = start.resolve()
    for path in [current, *current.parents]:
        candidate = path / ".agent_greed_run.json"
        if candidate.exists():
            return candidate
    return None




def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def enforce_file_policy(context: dict | None, out_dir: Path) -> list[str]:
    if not context:
        return []
    context_path = find_run_context(Path.cwd())
    if context_path is None:
        return []
    branch = context_path.parent
    policy_path = branch / ".agent_greed_policy.json"
    if not policy_path.exists():
        return [f"missing policy file: {policy_path}"]

    registry_rel = context.get("policy_registry")
    if registry_rel:
        registry_path = repo_root() / registry_rel
        if not registry_path.exists():
            return [f"missing policy registry: {registry_rel}"]
        registry = load_json(registry_path)
        expected_policy_hash = registry.get(branch.name)
        if not expected_policy_hash:
            return [f"policy registry missing branch entry: {branch.name}"]
        if sha256(policy_path) != expected_policy_hash:
            return ["policy file modified: .agent_greed_policy.json"]

    policy = load_json(policy_path)
    editable = set(policy.get("editable", []))
    allowed_extra = set(policy.get("allowed_extra", []))
    ignore_dirs = set(policy.get("ignore_dirs", []))
    ignore_globs = policy.get("ignore_globs", [])
    protected = policy.get("protected_hashes", {})
    errors = []

    for rel, expected in protected.items():
        path = branch / rel
        if not path.exists():
            errors.append(f"protected file missing: {rel}")
        elif sha256(path) != expected:
            errors.append(f"protected file modified: {rel}")

    for path in branch.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(branch).as_posix()
        first = rel.split("/", 1)[0]
        if rel == ".agent_greed_policy.json":
            continue
        if first in ignore_dirs or rel in editable or rel in allowed_extra or rel in protected:
            continue
        if any(fnmatch.fnmatch(rel, pat) for pat in ignore_globs):
            continue
        if any(fnmatch.fnmatch(path.name, pat) for pat in ignore_globs):
            continue
        errors.append(f"unexpected file in workspace: {rel}")

    if errors:
        write_text(out_dir / "policy_violations.txt", "\n".join(errors) + "\n")
    return errors

def next_output_dir(output_root: Path) -> Path:
    output_root.mkdir(parents=True, exist_ok=True)
    existing = []
    for child in output_root.iterdir():
        if child.is_dir() and child.name.startswith("run_"):
            try:
                existing.append(int(child.name.removeprefix("run_")))
            except ValueError:
                pass
    return output_root / f"run_{max(existing, default=0) + 1:03d}"


def count_successful_runs(output_root: Path) -> int:
    if not output_root.exists():
        return 0
    count = 0
    for run in sorted(output_root.glob("run_*/run.json")):
        try:
            data = load_json(run)
        except Exception:
            continue
        result = data.get("result", data)
        if result.get("status") == "correct":
            count += 1
    return count


def load_no_arg_context() -> tuple[str, Path, Path, dict]:
    context_path = find_run_context(Path.cwd())
    if context_path is None:
        raise FileNotFoundError("no .agent_greed_run.json found from current directory upward")
    context = load_json(context_path)
    kernel_name = context["kernel"]
    kernel_path = (context_path.parent / context.get("kernel_path", "src")).resolve()
    output_root = (context_path.parent / context.get("output_root", "out")).resolve()
    return kernel_name, kernel_path, next_output_dir(output_root), context


def set_status(out_dir: Path, status: str, result: dict) -> None:
    result["status"] = status


def run_json_display_path(out_dir: Path) -> str:
    context_path = find_run_context(Path.cwd())
    target = out_dir / "run.json"
    if context_path is not None:
        try:
            return target.relative_to(context_path.parent).as_posix()
        except ValueError:
            pass
    return str(target)


def finish(out_dir: Path, status: str, result: dict, context: dict | None) -> int:
    set_status(out_dir, status, result)
    bundle_run(out_dir, result)
    publish_latest(out_dir)
    audit_record(context, out_dir, result)
    speedup = result.get("speedup")
    speedup_text = "null" if speedup is None else f"{speedup:.6g}"
    print(f"wrote {run_json_display_path(out_dir)} status={status} speedup={speedup_text}")
    return 0


def read_optional(path: Path) -> str | None:
    if not path.exists() or not path.is_file():
        return None
    return path.read_text(encoding="utf-8", errors="replace")


def load_optional_json(path: Path) -> dict | list | None:
    if not path.exists() or not path.is_file():
        return None
    try:
        return load_json(path)
    except Exception:
        return None


def bundle_run(out_dir: Path, result: dict) -> None:
    if (out_dir / "profile_digest.txt").exists():
        result["profile_digest_path"] = "raw/profile_digest.txt"
    artifact_names = [
        "status.txt",
        "compile_log.txt",
        "program_output.txt",
        "correctness_diff.txt",
        "warmup_output.txt",
        "timing_raw.txt",
        "speedup.txt",
        "ptxas_log.txt",
        "static_resources.json",
        "profile.csv",
        "profile_digest.txt",
        "profile_digest_error.txt",
        "profile_nsys.log",
        "profile_nsys_import.log",
        "profile_nsys_stats.txt",
        "policy_violations.txt",
    ]
    report = {
        "result": result,
        "status": result.get("status"),
        "summary": {
            "status": result.get("status"),
            "speedup": result.get("speedup"),
            "median_ms": result.get("median_ms"),
            "baseline_median_ms": result.get("baseline_median_ms"),
            "profile_backend": result.get("profile_backend"),
            "profile_command": result.get("profile_command"),
            "timing_rel_stddev": result.get("timing_rel_stddev"),
        },
        "profile_digest": read_optional(out_dir / "profile_digest.txt"),
        "timing": read_optional(out_dir / "timing_raw.txt"),
        "compile_log": read_optional(out_dir / "compile_log.txt"),
        "program_output": read_optional(out_dir / "program_output.txt"),
        "correctness_diff": read_optional(out_dir / "correctness_diff.txt"),
        "policy_violations": read_optional(out_dir / "policy_violations.txt"),
        "static_resources": load_optional_json(out_dir / "static_resources.json"),
        "raw_files": [],
    }
    raw_dir = out_dir / "raw"
    raw_dir.mkdir(exist_ok=True)
    for name in artifact_names:
        path = out_dir / name
        if not path.exists():
            continue
        destination = raw_dir / name
        if destination.exists():
            destination.unlink()
        shutil.move(str(path), str(destination))
        report["raw_files"].append(f"raw/{name}")

    for binary_name in ["profile_nsys.qdstrm", "profile_nsys.nsys-rep", "profile_nsys.sqlite"]:
        path = out_dir / binary_name
        if not path.exists():
            continue
        destination = raw_dir / binary_name
        if destination.exists():
            destination.unlink()
        shutil.move(str(path), str(destination))
        report["raw_files"].append(f"raw/{binary_name}")

    write_text(out_dir / "run.json", json.dumps(report, indent=2, sort_keys=True) + "\n")


def publish_latest(out_dir: Path) -> None:
    root = out_dir.parent
    latest = root / "latest"
    if latest.exists() or latest.is_symlink():
        if latest.is_dir() and not latest.is_symlink():
            shutil.rmtree(latest)
        else:
            latest.unlink()
    try:
        latest.symlink_to(out_dir, target_is_directory=True)
    except OSError:
        pass
    src = out_dir / "run.json"
    if src.exists():
        shutil.copyfile(src, root / "latest_run.json")
    for stale_name in ("latest_result.json", "latest_status.txt", "latest_profile_digest.txt"):
        stale = root / stale_name
        if stale.exists():
            stale.unlink()


def audit_record(context: dict | None, out_dir: Path, result: dict) -> None:
    if not context or not context.get("private_log"):
        return
    record = {
        "timestamp": int(time.time()),
        "kernel": result.get("kernel"),
        "condition": context.get("condition"),
        "strategy_rank": context.get("strategy_rank"),
        "strategy_id": context.get("strategy_id"),
        "kernel_path": result.get("kernel_path"),
        "output_dir": str(out_dir),
        "status": result.get("status"),
        "speedup": result.get("speedup"),
        "median_ms": result.get("median_ms"),
        "profile_backend": result.get("profile_backend"),
    }
    append_text(repo_root() / context["private_log"], json.dumps(record, sort_keys=True) + "\n", mode=0o600)


def run_nsys_fallback(program_argv: list[str], kernel_path: Path, out_dir: Path) -> bool:
    prefix = out_dir / "profile_nsys"
    qdstrm = out_dir / "profile_nsys.qdstrm"
    report = out_dir / "profile_nsys.nsys-rep"
    stats = out_dir / "profile_nsys_stats.txt"
    digest = out_dir / "profile_digest.txt"
    importer = Path("/usr/lib/nsight-systems/host-linux-x64/QdstrmImporter")

    nsys_cmd = [
        "nsys",
        "profile",
        "--trace=cuda",
        "--sample=none",
        "--stats=false",
        "--force-overwrite=true",
        f"--output={prefix}",
        *program_argv,
    ]
    nsys_proc = run_command(nsys_cmd, kernel_path)
    write_text(out_dir / "profile_nsys.log", nsys_proc.stdout)
    if nsys_proc.returncode != 0 or not qdstrm.exists() or not importer.exists():
        return False

    import_proc = run_command(
        [str(importer), "-i", str(qdstrm), "-o", str(report), "-f"],
        kernel_path,
    )
    write_text(out_dir / "profile_nsys_import.log", import_proc.stdout)
    if import_proc.returncode != 0 or not report.exists():
        return False

    stats_proc = run_command(["nsys", "stats", str(report)], kernel_path)
    write_text(stats, stats_proc.stdout)
    if stats_proc.returncode != 0:
        return False

    digest_proc = run_command(
        [
            sys.executable,
            str(repo_root() / "scripts" / "parse_nsys_stats.py"),
            str(stats),
            str(digest),
        ],
        repo_root(),
    )
    if digest_proc.returncode != 0:
        write_text(out_dir / "profile_digest_error.txt", digest_proc.stdout)
        return False
    return True


def collect_static_resources(kernel_cfg: dict, kernel_path: Path, out_dir: Path) -> dict:
    clean_cmd = kernel_cfg.get("clean_command")
    if clean_cmd:
        run_command(clean_cmd, kernel_path)
    make_cmd = ["make", "EXTRA_CFLAGS=-Xptxas=-v"]
    if arch := kernel_cfg.get("arch"):
        make_cmd.append(f"ARCH={arch}")
    proc = run_command(make_cmd, kernel_path)
    write_text(out_dir / "ptxas_log.txt", proc.stdout)
    entries = []
    current = None
    for line in proc.stdout.splitlines():
        match_func = re.search(r"Function properties for (.+)", line)
        if match_func:
            current = match_func.group(1).strip()
        match_used = re.search(r"Used\s+([0-9]+)\s+registers(?:,\s+([0-9]+)\s+bytes smem)?", line)
        if match_used:
            entries.append(
                {
                    "function": current or "unknown",
                    "regs_per_thread": int(match_used.group(1)),
                    "static_smem_bytes": int(match_used.group(2) or 0),
                }
            )
    result = {"available": proc.returncode == 0 and bool(entries), "entries": entries}
    write_text(out_dir / "static_resources.json", json.dumps(result, indent=2, sort_keys=True) + "\n")
    return result


def append_static_resources_to_digest(out_dir: Path, static_resources: dict) -> None:
    digest = out_dir / "profile_digest.txt"
    if not digest.exists():
        return
    lines = ["", "Static compiler resources:"]
    if not static_resources.get("available"):
        lines.append("  unavailable")
    else:
        for entry in static_resources.get("entries", []):
            lines.append(
                "  {function}: regs/thread={regs_per_thread}, static_smem={static_smem_bytes} bytes".format(
                    **entry
                )
            )
    append_text(digest, "\n".join(lines) + "\n")


def usage() -> str:
    return (
        "Usage:\n"
        "  ./run.sh  # uses .agent_greed_run.json from current directory or parent\n"
        "  ./run.sh <kernel_name> <kernel_path> <output_dir>\n"
        "  ./run.sh <kernel_name> <output_dir>  # uses config source_dir\n"
    )


def main() -> int:
    run_context = None
    if len(sys.argv) == 1:
        try:
            kernel_name, kernel_path, out_dir, run_context = load_no_arg_context()
        except Exception as exc:
            print(f"run context error: {exc}", file=sys.stderr)
            return 2
    elif len(sys.argv) == 4:
        kernel_name = sys.argv[1]
        kernel_path = Path(sys.argv[2])
        out_dir = Path(sys.argv[3])
    elif len(sys.argv) == 3:
        kernel_name = sys.argv[1]
        out_dir = Path(sys.argv[2])
        cfg = load_json(repo_root() / "config" / "kernels.json")["kernels"]
        if kernel_name not in cfg:
            print(f"unknown kernel: {kernel_name}", file=sys.stderr)
            return 2
        kernel_path = repo_root() / cfg[kernel_name]["source_dir"]
    else:
        print(usage(), file=sys.stderr)
        return 2

    out_dir.mkdir(parents=True, exist_ok=True)
    config = load_json(repo_root() / "config" / "kernels.json")["kernels"]
    if kernel_name not in config:
        return finish(out_dir, "config_error", {"kernel": kernel_name, "error": "unknown kernel"}, run_context) or 2
    kernel_cfg = config[kernel_name]
    if not kernel_path.is_absolute():
        kernel_path = (repo_root() / kernel_path).resolve()

    result = {
        "kernel": kernel_name,
        "kernel_path": str(kernel_path),
        "status": "started",
        "baseline_median_ms": None,
        "median_ms": None,
        "speedup": None,
        "timing_runs_ms": [],
        "timing_rel_stddev": None,
        "profile_digest_path": None,
        "profile_backend": None,
    }

    if run_context and run_context.get("max_runs"):
        max_runs = int(run_context["max_runs"])
        successful_runs = count_successful_runs(out_dir.parent)
        if successful_runs >= max_runs:
            result["max_runs"] = max_runs
            result["successful_runs"] = successful_runs
            return finish(out_dir, "iteration_limit", result, run_context)

    policy_errors = enforce_file_policy(run_context, out_dir)
    if policy_errors:
        result["policy_errors"] = policy_errors
        return finish(out_dir, "policy_violation", result, run_context)

    clean_cmd = kernel_cfg.get("clean_command")
    if clean_cmd:
        run_command(clean_cmd, kernel_path)

    compile_log = []
    for cmd in kernel_cfg["build_command"]:
        if isinstance(cmd, str):
            argv = [cmd]
        else:
            argv = cmd
        proc = run_command(argv, kernel_path)
        compile_log.append(f"$ {' '.join(argv)}\n{proc.stdout}")
        if proc.returncode != 0:
            write_text(out_dir / "compile_log.txt", "\n".join(compile_log))
            return finish(out_dir, "compile_error", result, run_context)
    write_text(out_dir / "compile_log.txt", "\n".join(compile_log))

    binary = kernel_path / kernel_cfg["binary"]
    run_args = kernel_cfg.get("run_args", [])
    program_argv = [str(binary), *run_args]

    correctness_proc = run_command(program_argv, kernel_path)
    write_text(out_dir / "program_output.txt", correctness_proc.stdout)
    if correctness_proc.returncode != 0:
        write_text(out_dir / "correctness_diff.txt", f"program exited {correctness_proc.returncode}\n")
        return finish(out_dir, "correctness_fail", result, run_context)

    reference = repo_root() / "baselines" / kernel_name / "reference_output.txt"
    output_file = out_dir / "program_output.txt"
    check = run_command(
        [
            sys.executable,
            str(repo_root() / "scripts" / "check_correctness.py"),
            kernel_name,
            str(output_file),
            str(reference),
        ],
        repo_root(),
    )
    if check.returncode != 0:
        write_text(out_dir / "correctness_diff.txt", check.stdout)
        return finish(out_dir, "correctness_fail", result, run_context)

    timing_cfg = kernel_cfg["timing"]
    warmup = run_command(program_argv, kernel_path)
    write_text(out_dir / "warmup_output.txt", warmup.stdout)
    timing_values = []
    timing_outputs = []
    for i in range(5):
        proc = run_command(program_argv, kernel_path)
        timing_outputs.append(f"run {i + 1}\n{proc.stdout}")
        if proc.returncode != 0:
            write_text(out_dir / "timing_raw.txt", "\n".join(timing_outputs))
            return finish(out_dir, "runtime_error", result, run_context)
        raw = extract_timing(proc.stdout, timing_cfg)
        timing_values.append(unit_to_ms(raw, timing_cfg["unit"]))

    median_ms = statistics.median(timing_values)
    result["median_ms"] = median_ms
    result["timing_runs_ms"] = timing_values
    result["timing_rel_stddev"] = rel_stddev(timing_values)

    baseline_ms = baseline_value(kernel_name, timing_cfg["unit"], timing_cfg.get("higher_is_better", False))
    result["baseline_median_ms"] = baseline_ms
    if baseline_ms and median_ms:
        if timing_cfg.get("higher_is_better", False):
            result["speedup"] = median_ms / baseline_ms
        else:
            result["speedup"] = baseline_ms / median_ms
        write_text(out_dir / "speedup.txt", f"{result['speedup']:.9g}\n")

    timing_text = "\n".join(
        [
            *(f"run_{i + 1}_ms={value:.9g}" for i, value in enumerate(timing_values)),
            f"median_ms={median_ms:.9g}",
            f"relative_stddev={result['timing_rel_stddev']:.9g}",
        ]
    )
    write_text(out_dir / "timing_raw.txt", timing_text + "\n\n" + "\n".join(timing_outputs))

    static_resources = collect_static_resources(kernel_cfg, kernel_path, out_dir)

    profile_path = out_dir / "profile.csv"
    ncu_args = [
        "--csv",
        "--target-processes",
        "all",
        "--launch-count",
        "1",
        "--metrics",
        ",".join(NCU_METRICS),
        *program_argv,
    ]
    ncu_proc, ncu_backend = run_ncu_command(ncu_args, kernel_path)
    write_text(profile_path, ncu_proc.stdout)
    result["profile_command"] = ncu_backend
    if ncu_proc.returncode != 0 or "ERR_NVGPUCTRPERM" in ncu_proc.stdout or "No kernels were profiled" in ncu_proc.stdout:
        if run_nsys_fallback(program_argv, kernel_path, out_dir):
            append_static_resources_to_digest(out_dir, static_resources)
            result["profile_backend"] = "nsys"
            result["profile_digest_path"] = "profile_digest.txt"
            return finish(out_dir, "correct", result, run_context)
        return finish(out_dir, "profile_error", result, run_context)

    digest_path = out_dir / "profile_digest.txt"
    digest_proc = run_command(
        [
            sys.executable,
            str(repo_root() / "scripts" / "parse_ncu.py"),
            str(profile_path),
            str(digest_path),
        ],
        repo_root(),
    )
    if digest_proc.returncode != 0:
        write_text(out_dir / "profile_digest_error.txt", digest_proc.stdout)
        return finish(out_dir, "profile_error", result, run_context)

    result["profile_digest_path"] = "profile_digest.txt"
    result["profile_backend"] = "ncu"
    append_static_resources_to_digest(out_dir, static_resources)
    return finish(out_dir, "correct", result, run_context)


if __name__ == "__main__":
    raise SystemExit(main())
