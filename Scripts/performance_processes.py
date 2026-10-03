#!/usr/bin/env python3
"""Read-only local process sampling; never launches an app or controls a fan.

Pair with a fixed --performance-monitoring-long / --performance-comfort-long
session, or sample ordinary GUI use. Output is private local evidence, not export.
"""
import argparse
import json
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pids', type=int, nargs='+', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not args.pids or any(pid <= 0 for pid in args.pids):
        parser.error('positive process identifiers required')
    baseline = {}
    started = time.monotonic()
    with open(args.output, 'x', encoding='utf-8') as output:
        while time.monotonic() - started < 1800:
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
                json.dump({'elapsedSeconds': elapsed, 'pid': int(pid), 'cpuSeconds': seconds,
                           'accumulatedCPUPercent': 100 * (seconds-first_cpu) / max(0.001, elapsed-first_time),
                           'residentKiB': int(rss)}, output, sort_keys=True)
                output.write('\n')
            output.flush()
            time.sleep(min(5, max(0, 1800 - (time.monotonic()-started))))


if __name__ == '__main__':
    main()
