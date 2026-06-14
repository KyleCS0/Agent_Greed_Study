#!/usr/bin/env python3
import csv
import re
import sys
from pathlib import Path


ALIASES = {
    'achieved_occupancy_pct': ['sm__warps_active.avg.pct_of_peak_sustained_active'],
    'fma_utilization_pct': ['smsp__pipe_fma_cycles_active.avg.pct_of_peak_sustained_active'],
    'global_load_bps': ['l1tex__t_bytes_pipe_lsu_mem_global_op_ld.sum.per_second'],
    'global_store_bps': ['l1tex__t_bytes_pipe_lsu_mem_global_op_st.sum.per_second'],
    'global_load_efficiency_pct': ['smsp__sass_average_data_bytes_per_sector_mem_global_op_ld.pct'],
    'smem_load_bank_conflicts': ['l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_ld.sum'],
    'smem_store_bank_conflicts': ['l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_st.sum'],
    'stall_memory_pct': ['smsp__warp_issue_stalled_long_scoreboard_per_warp_active.pct'],
    'stall_barrier_pct': ['smsp__warp_issue_stalled_barrier_per_warp_active.pct'],
    'stall_short_dep_pct': ['smsp__warp_issue_stalled_short_scoreboard_per_warp_active.pct'],
    'stall_wait_pct': ['smsp__warp_issue_stalled_wait_per_warp_active.pct'],
    'warp_active_pct': ['smsp__warp_issue_stalled_selected_per_warp_active.pct'],
    'l2_read_hit_rate_pct': ['lts__t_sectors_srcunit_tex_op_read_hit_rate.pct'],
    # Older/fallback metrics from previous harness versions.
    'l1_hit_pct': ['l1tex__t_sector_hit_rate.pct'],
    'l2_hit_pct': ['lts__t_sector_hit_rate.pct'],
    'dram_bps': ['dram__bytes.sum.per_second'],
    'gpu_time': ['gpu__time_duration.sum'],
}


def parse_number(value: str) -> float | None:
    cleaned = value.replace(',', '').strip()
    match = re.search(r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?', cleaned)
    if not match:
        return None
    return float(match.group(0))


def read_metrics(path: Path) -> dict[str, float]:
    metrics: dict[str, float] = {}
    with path.open('r', encoding='utf-8', errors='replace', newline='') as f:
        rows = list(csv.reader(f))

    header = None
    for row in rows:
        normalized = [cell.strip().strip('"') for cell in row]
        if 'Metric Name' in normalized and 'Metric Value' in normalized:
            header = {name: i for i, name in enumerate(normalized)}
            continue
        if header:
            name_i = header.get('Metric Name')
            value_i = header.get('Metric Value')
            if name_i is not None and value_i is not None and len(row) > max(name_i, value_i):
                name = row[name_i].strip().strip('"')
                value = parse_number(row[value_i])
                if name and value is not None:
                    metrics.setdefault(name, value)
            continue

        # Fallback for NCU variants where CSV rows are not headed as expected.
        for i, cell in enumerate(row):
            name = cell.strip().strip('"')
            if '__' not in name and not name.startswith('gpu__'):
                continue
            for value_cell in reversed(row[i + 1:]):
                value = parse_number(value_cell)
                if value is not None:
                    metrics.setdefault(name, value)
                    break
    return metrics


def get(metrics: dict[str, float], key: str) -> float | None:
    for name in ALIASES[key]:
        if name in metrics:
            return metrics[name]
    return None


def fmt_pct(value: float | None) -> str:
    return 'unknown' if value is None else f'{value:.1f}%'


def fmt_num(value: float | None) -> str:
    return 'unknown' if value is None else f'{value:.0f}'


def fmt_gbs(value: float | None) -> str:
    return 'unknown' if value is None else f'{value / 1e9:.1f} GB/s'


def bound_hint(metrics: dict[str, float]) -> str:
    stall_mem = get(metrics, 'stall_memory_pct')
    stall_bar = get(metrics, 'stall_barrier_pct')
    fma = get(metrics, 'fma_utilization_pct')
    load_bw = get(metrics, 'global_load_bps')
    if stall_mem is not None and stall_mem >= 25:
        return 'likely memory-latency limited'
    if stall_bar is not None and stall_bar >= 15:
        return 'likely synchronization/barrier limited'
    if fma is not None and fma >= 60:
        return 'meaningful compute-pipe pressure'
    if load_bw is not None:
        return 'memory traffic visible; compare bandwidth and coalescing below'
    return 'unknown from available counters'


def top_stalls(metrics: dict[str, float]) -> list[tuple[str, float]]:
    items = [
        ('memory/long scoreboard', get(metrics, 'stall_memory_pct')),
        ('barrier', get(metrics, 'stall_barrier_pct')),
        ('short dependency', get(metrics, 'stall_short_dep_pct')),
        ('wait', get(metrics, 'stall_wait_pct')),
    ]
    valid = [(name, value) for name, value in items if value is not None]
    valid.sort(key=lambda item: item[1], reverse=True)
    return valid


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print('Usage: parse_ncu.py <profile.csv> [output_digest.txt]')
        return 2

    profile = Path(sys.argv[1])
    output = Path(sys.argv[2]) if len(sys.argv) == 3 else None
    metrics = read_metrics(profile)
    if not metrics:
        print('no ncu metrics found')
        return 1

    lines = [
        'Hardware counters:   available from Nsight Compute',
        f'Bound hint:          {bound_hint(metrics)}',
        '',
        'Occupancy / utilization:',
        f"  achieved occupancy:        {fmt_pct(get(metrics, 'achieved_occupancy_pct'))}",
        f"  FMA pipe utilization:      {fmt_pct(get(metrics, 'fma_utilization_pct'))}",
        f"  warp issue selected:       {fmt_pct(get(metrics, 'warp_active_pct'))}",
        '',
        'Global memory:',
        f"  load bandwidth:            {fmt_gbs(get(metrics, 'global_load_bps'))}",
        f"  store bandwidth:           {fmt_gbs(get(metrics, 'global_store_bps'))}",
        f"  global load efficiency:    {fmt_pct(get(metrics, 'global_load_efficiency_pct'))}",
        f"  L2 read hit rate:          {fmt_pct(get(metrics, 'l2_read_hit_rate_pct') or get(metrics, 'l2_hit_pct'))}",
        '',
        'Shared memory:',
        f"  load bank conflicts:       {fmt_num(get(metrics, 'smem_load_bank_conflicts'))}",
        f"  store bank conflicts:      {fmt_num(get(metrics, 'smem_store_bank_conflicts'))}",
        '',
        'Warp stalls:',
        f"  memory / long scoreboard:  {fmt_pct(get(metrics, 'stall_memory_pct'))}",
        f"  barrier:                   {fmt_pct(get(metrics, 'stall_barrier_pct'))}",
        f"  short dependency:          {fmt_pct(get(metrics, 'stall_short_dep_pct'))}",
        f"  wait:                      {fmt_pct(get(metrics, 'stall_wait_pct'))}",
    ]

    stalls = top_stalls(metrics)
    if stalls:
        lines.extend(['', 'Top stall reasons:'])
        for name, value in stalls[:3]:
            lines.append(f'  {name}: {value:.1f}%')

    lines.extend([
        '',
        'Interpretation hints:',
        '  - occupancy below ~25% often points to register/smem/resource limits',
        '  - high memory/long-scoreboard stalls point to memory latency or cache misses',
        '  - global load efficiency below ~85% suggests uncoalesced/wasted transactions',
        '  - any shared-memory bank conflicts are worth investigating when smem is used',
        '  - compare load/store bandwidth against expected GPU peak before assuming bandwidth saturation',
    ])

    text = '\n'.join(lines) + '\n'
    if output:
        output.write_text(text, encoding='utf-8')
    else:
        print(text, end='')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
