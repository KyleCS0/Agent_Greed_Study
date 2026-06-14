#!/usr/bin/env python3
import re
import sys
from pathlib import Path


def parse_number(value: str) -> float | None:
    cleaned = value.replace(',', '').strip()
    match = re.search(r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?', cleaned)
    if not match:
        return None
    return float(match.group(0))


def ns_to_ms(value: float | None) -> str:
    if value is None:
        return 'unknown'
    return f'{value / 1_000_000.0:.3f} ms'


def mb_to_gb(value: float | None) -> str:
    if value is None:
        return 'unknown'
    return f'{value / 1000.0:.3f} GB'


def parse_kernel_summary(text: str) -> dict | None:
    marker = 'CUDA GPU Kernel Summary'
    start = text.find(marker)
    if start == -1:
        return None
    section = text[start:]
    for line in section.splitlines():
        parts = line.split()
        if len(parts) < 15:
            continue
        if not re.fullmatch(r'[-+]?\d+(?:\.\d+)?', parts[0]):
            continue
        return {
            'time_pct': parse_number(parts[0]),
            'total_ns': parse_number(parts[1]),
            'instances': int(parse_number(parts[2]) or 0),
            'avg_ns': parse_number(parts[3]),
            'med_ns': parse_number(parts[4]),
            'min_ns': parse_number(parts[5]),
            'max_ns': parse_number(parts[6]),
            'stddev_ns': parse_number(parts[7]),
            'grid': tuple(int(parse_number(p) or 0) for p in parts[8:11]),
            'block': tuple(int(parse_number(p) or 0) for p in parts[11:14]),
            'name': ' '.join(parts[14:]),
        }
    return None


def parse_mem_size_summary(text: str) -> dict[str, dict]:
    marker = 'GPU MemOps Summary (by Size)'
    start = text.find(marker)
    if start == -1:
        return {}
    section = text[start:]
    result = {}
    for line in section.splitlines():
        if '[CUDA memcpy' not in line:
            continue
        op_match = re.search(r'\[CUDA memcpy ([^\]]+)\]', line)
        if not op_match:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        total_mb = parse_number(parts[0])
        count = int(parse_number(parts[1]) or 0)
        result[op_match.group(1)] = {'total_mb': total_mb, 'count': count}
    return result


def parse_mem_time_summary(text: str) -> dict[str, dict]:
    marker = 'GPU MemOps Summary (by Time)'
    start = text.find(marker)
    if start == -1:
        return {}
    section = text[start:]
    result = {}
    for line in section.splitlines():
        if '[CUDA memcpy' not in line:
            continue
        op_match = re.search(r'\[CUDA memcpy ([^\]]+)\]', line)
        if not op_match:
            continue
        parts = line.split()
        if len(parts) < 6:
            continue
        result[op_match.group(1)] = {
            'time_pct': parse_number(parts[0]),
            'total_ns': parse_number(parts[1]),
            'count': int(parse_number(parts[2]) or 0),
            'avg_ns': parse_number(parts[3]),
        }
    return result


def softmax_estimate(kernel: dict | None, mem_sizes: dict[str, dict]) -> list[str]:
    if not kernel or 'softMax' not in kernel.get('name', ''):
        return []
    h2d = mem_sizes.get('HtoD', {}).get('total_mb')
    d2h = mem_sizes.get('DtoH', {}).get('total_mb')
    array_mb = h2d or d2h
    avg_ns = kernel.get('avg_ns')
    if array_mb is None or avg_ns is None or avg_ns <= 0:
        return []
    estimated_mb = array_mb * 3.0
    gbps = (estimated_mb * 1_000_000.0) / (avg_ns / 1_000_000_000.0) / 1_000_000_000.0
    return [
        '',
        'Softmax-specific estimate:',
        f'  one tensor size:            {array_mb:,.1f} MB',
        f'  approx kernel traffic:      {estimated_mb:,.1f} MB/launch (2 input reads + 1 output write)',
        f'  implied bandwidth:          {gbps:,.1f} GB/s from Nsys avg time',
        '  note: this is an estimate from timeline data; use NCU counters to confirm actual traffic/stalls.',
    ]


def main() -> int:
    if len(sys.argv) != 3:
        print('Usage: parse_nsys_stats.py <nsys_stats.txt> <digest.txt>')
        return 2

    text = Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
    kernel = parse_kernel_summary(text)
    mem_sizes = parse_mem_size_summary(text)
    mem_times = parse_mem_time_summary(text)

    lines = [
        'Hardware counters:   unavailable in Nsys fallback (no occupancy/stall/cache counters)',
        'Bound type:          Timeline-only; use estimates below and enable NCU for real bottleneck data',
    ]

    if kernel:
        grid = 'x'.join(str(x) for x in kernel['grid'])
        block = 'x'.join(str(x) for x in kernel['block'])
        lines.extend([
            '',
            'Nsight Systems kernel trace:',
            f"  kernel:                   {kernel['name']}",
            f"  instances:                {kernel['instances']}",
            f"  avg / median:             {ns_to_ms(kernel['avg_ns'])} / {ns_to_ms(kernel['med_ns'])}",
            f"  min / max:                {ns_to_ms(kernel['min_ns'])} / {ns_to_ms(kernel['max_ns'])}",
            f"  total kernel time:        {ns_to_ms(kernel['total_ns'])}",
            f"  launch shape:             grid={grid}, block={block}",
        ])
    else:
        lines.extend(['', 'Nsight Systems kernel trace: unavailable'])

    if mem_sizes or mem_times:
        lines.extend(['', 'GPU memcpy summary (setup/check path, not the timed kernel loop):'])
        for op in sorted(set(mem_sizes) | set(mem_times)):
            size = mem_sizes.get(op, {})
            timing = mem_times.get(op, {})
            lines.append(
                '  {op:<4} total={size:<12} count={count:<3} avg_time={avg}'.format(
                    op=op,
                    size=mb_to_gb(size.get('total_mb')),
                    count=size.get('count', timing.get('count', 'unknown')),
                    avg=ns_to_ms(timing.get('avg_ns')),
                )
            )

    lines.extend(softmax_estimate(kernel, mem_sizes))

    lines.extend([
        '',
        'What Claude can infer from this fallback:',
        '  - launch geometry and per-launch runtime are known',
        '  - host/device transfer size shows the working-set scale',
        '  - static compiler resources appended below show register/smem pressure',
        '  - cache hit rates, stall reasons, achieved occupancy, and true DRAM throughput still require NCU',
    ])

    Path(sys.argv[2]).write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
