#!/usr/bin/env python3
"""Summarize a recorded Mac17,9 temperature session."""
import argparse
import bisect
import importlib.util
import json
import math
from pathlib import Path

spec = importlib.util.spec_from_file_location('correlation', Path(__file__).with_name('correlate-sensors.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
CPU = ['Tp00','Tp04','Tp08','Tp0C','Tp0G','Tp0K','Tp0O','Tp0R','Tp0U','Tp0X','Tp0a','Tp0d','Tp0g','Tp0j','Tp0m','Tp0p','Tp0u','Tp0y']
GPU = ['Tg0U','Tg0X','Tg0d','Tg0g','Tg0j','Tg1Y','Tg1c']


def validate_session(records, completion):
    if completion.strip() != 'Measurement completed: 960-second bounded cycle, no fan writes.':
        raise ValueError('No successful bounded-cycle completion evidence')
    order = ['baseline', 'cpu', 'cpuCooldown', 'gpu', 'gpuCooldown', 'chassis']
    seen = []
    last = -1
    for record in records:
        elapsed = record['elapsed']
        if not math.isfinite(elapsed) or elapsed <= last or not 0 <= elapsed < 960:
            raise ValueError('Invalid diagnostic timeline')
        last = elapsed
        intervals = zip([0,60,90,210,240,360], [60,90,210,240,360,960], order)
        expected = next(name for lo, hi, name in intervals if lo <= elapsed < hi)
        if record['phase'] != expected:
            raise ValueError('Phase disagrees with absolute diagnostic deadline')
        if record['model'] != 'Mac17,9' or sorted(f['id'] for f in record['fans']) != [0, 1] or any(f['mode'] != 0 for f in record['fans']):
            raise ValueError('Unqualified ownership/model')
        if not seen or seen[-1] != record['phase']:
            seen.append(record['phase'])
    if seen != order or records[0]['elapsed'] > 10 or last < 958:
        raise ValueError('Incomplete diagnostic phase coverage')


def summarize(records, rows):
    times = [time for time, _ in rows]
    phases = {}
    for record in records:
        values = {item['key']: value for item in record['keys']
                  if item['type'] == 'flt ' and item['size'] == 4 and (value := c.temperature(item.get('value'))) is not None}
        if not all(key in values for key in CPU + GPU):
            raise ValueError('Incomplete documented chip domain in diagnostic record')
        phase = phases.setdefault(record['phase'], {'samples': 0, 'pairs': 0, 'cpu': [], 'gpu': [], 'cpuUnder': [], 'gpuUnder': [], 'gaps': []})
        phase['samples'] += 1
        phase['cpu'].append(max(values[key] for key in CPU)); phase['gpu'].append(max(values[key] for key in GPU))
        time = c.timestamp(record['timestamp'])
        i = bisect.bisect_left(times, time)
        candidates = [j for j in (i-1, i) if 0 <= j < len(rows)]
        if not candidates:
            continue
        j = min(candidates, key=lambda j: abs(times[j] - time))
        gap = abs(times[j] - time)
        if gap > 2:
            continue
        reference = rows[j][1]
        cpu = [v for name, v in reference.items() if name.startswith(('Super Core ', 'Performance Core '))]
        gpu = [v for name, v in reference.items() if name.startswith('GPU Region ')]
        phase['pairs'] += 1; phase['gaps'].append(gap)
        if cpu: phase['cpuUnder'].append(max(cpu) - phase['cpu'][-1])
        if gpu: phase['gpuUnder'].append(max(gpu) - phase['gpu'][-1])
    return phases


def render(records, phases):
    lines = ['# Mac17,9 sensor measurement', '',
             f'{len(records)} records: {records[0]["timestamp"]} to {records[-1]["timestamp"]}. '
             'The 960-second session completed with both fans in automatic mode.', '',
             '| Phase | Samples / TG Pro pairs | CPU peak range °C | GPU peak range °C | Largest CPU / GPU under-read °C | Pairing gap s |',
             '| --- | ---: | --- | --- | --- | ---: |']
    for name, p in phases.items():
        lines.append(f'| {name} | {p["samples"]} / {p["pairs"]} | {min(p["cpu"]):.2f}–{max(p["cpu"]):.2f} | '
                     f'{min(p["gpu"]):.2f}–{max(p["gpu"]):.2f} | '
                     f'{max(0,max(p["cpuUnder"],default=0)):.2f} / {max(0,max(p["gpuUnder"],default=0)):.2f} | {max(p["gaps"],default=0):.2f} |')
    lines += ['', 'Peaks use the candidate CPU/GPU groups defined by this tool. Each group must be complete. '
              'TG Pro samples are paired within two seconds. Under-read is the reference peak minus the candidate peak; '
              'rounding, sampling lag and group membership can affect the difference.', '',
              'This offline report does not change qualification. Sensor identity and hotspot coverage '
              'need independent confirmation.']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples', required=True); parser.add_argument('--tg-pro-csv', required=True); parser.add_argument('--output', required=True)
    parser.add_argument('--completion-log', required=True)
    args = parser.parse_args()
    records = [json.loads(line) for line in Path(args.samples).read_text().splitlines()]
    validate_session(records, Path(args.completion_log).read_text())
    rows = c.load_rows(args.tg_pro_csv)
    Path(args.output).write_text(render(records, summarize(records, rows)))
    print(f'Measurement report: {len(records)} records; qualification unchanged')


if __name__ == '__main__':
    main()
