#!/usr/bin/env python3
"""Read-only local process sampling; never launches an app or controls a fan.

Pair with a fixed --performance-monitoring-long / --performance-comfort-long
session, or sample ordinary GUI use. Output is private local evidence, not export.
"""
import argparse
import json
import math
import re
import statistics
import subprocess
import time


def cpu_seconds(value):
    parts = value.split(':')
    if '-' in parts[0]:
        days, hours = parts[0].split('-')
        return int(days) * 86400 + int(hours) * 3600 + int(parts[1]) * 60 + float(parts[2])
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    return int(parts[0]) * 60 + float(parts[1])


def parse_footprint(pid, output):
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[0] != str(pid):
            continue
        match = re.fullmatch(r'([0-9]+(?:\.[0-9]+)?)([BKMGTP])[-+]?', parts[1])
        if match:
            value = float(match[1]) * 1024 ** 'BKMGTP'.index(match[2])
            if math.isfinite(value) and 0 < value < 2**64:
                return int(value)
    raise ValueError('Physical footprint unavailable; do not substitute resident size or zero')


def summarize(rows):
    if not rows:
        raise ValueError('No process observations')
    result = {}
    for pid in sorted({row['pid'] for row in rows}):
        samples = [r for r in rows if r['pid'] == pid]
        first, last = samples[0], samples[-1]
        duration = last['elapsedSeconds'] - first['elapsedSeconds']
        delta = last['cpuSeconds'] - first['cpuSeconds']
        if len(samples) < 2 or duration <= 0 or delta < 0:
            raise ValueError('Incomplete or restarted process window')
        result[str(pid)] = {'durationSeconds': duration, 'cpuPercent': 100 * delta / duration,
            'cpuSeconds': delta, 'residentMedianKiB': statistics.median(r['residentKiB'] for r in samples),
            'residentMaximumKiB': max(r['residentKiB'] for r in samples)}
        if any('footprintBytes' in r for r in samples):
            if not all(isinstance(r.get('footprintBytes'), int) and r['footprintBytes'] > 0 for r in samples):
                raise ValueError('Incomplete physical footprint observations')
            result[str(pid)]['footprintMedianBytes'] = statistics.median(r['footprintBytes'] for r in samples)
            result[str(pid)]['footprintMaximumBytes'] = max(r['footprintBytes'] for r in samples)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pids', type=int, nargs='+', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--seconds', type=float, default=1800)
    parser.add_argument('--interval', type=float, default=5)
    parser.add_argument('--footprint', action='store_true', help='Read macOS physical footprint separately using top')
    args = parser.parse_args()
    if not math.isfinite(args.seconds) or not 10 <= args.seconds <= 1800 or not math.isfinite(args.interval) or not 1 <= args.interval <= 30:
        parser.error('Use 10–1800 seconds and a 1–30 second interval')
    if not args.pids or any(pid <= 0 for pid in args.pids):
        parser.error('positive process identifiers required')
    baseline = {}
    started = time.monotonic()
    with open(args.output, 'x', encoding='utf-8') as output:
        while time.monotonic() - started <= args.seconds:
            result = subprocess.run(['/bin/ps', '-p', ','.join(map(str, args.pids)), '-o', 'pid=,time=,rss='], capture_output=True, text=True, check=False)
            if result.returncode:
                raise RuntimeError('A measured process disappeared; session is incomplete')
            rows = [row.split() for row in result.stdout.splitlines() if row.strip()]
            if {int(row[0]) for row in rows} != set(args.pids):
                raise RuntimeError('A measured process disappeared; session is incomplete')
            elapsed = time.monotonic() - started
            for pid, cpu, rss in rows:
                seconds = cpu_seconds(cpu)
                baseline.setdefault(int(pid), (elapsed, seconds))
                first_time, first_cpu = baseline[int(pid)]
                row = {'elapsedSeconds': elapsed, 'pid': int(pid), 'cpuSeconds': seconds,
                           'accumulatedCPUPercent': 100 * (seconds-first_cpu) / max(0.001, elapsed-first_time),
                           'residentKiB': int(rss)}
                if args.footprint:
                    measured = subprocess.run(['/usr/bin/top', '-l', '1', '-pid', pid, '-stats', 'pid,mem'],
                        capture_output=True, text=True, check=True, timeout=15)
                    row['footprintBytes'] = parse_footprint(pid, measured.stdout)
                json.dump(row, output, sort_keys=True)
                output.write('\n')
            output.flush()
            time.sleep(args.interval)


if __name__ == '__main__':
    main()
