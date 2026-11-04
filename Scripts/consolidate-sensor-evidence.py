#!/usr/bin/env python3
"""Compare recorded SMC temperatures with TG Pro exports."""
import argparse
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location('correlation', Path(__file__).with_name('correlate-sensors.py'))
correlation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(correlation)

CHASSIS = {
    'Trackpad (C)': ('Ts0P', 'Historical VirtualSMC Trackpad name'),
    'Trackpad Actuator (C)': ('Ts1P', 'Historical VirtualSMC Actuator name'),
    'Airflow Left (C)': ('TaLP', 'Stats Left name'),
    'Airflow Top (C)': ('TaTP', 'iSMC Apple Ambient Top Proximity; exact-model Airflow Top identity unproved'),
    'Airflow Right (C)': ('TaRF', 'Stats Right name'),
    'Charger Proximity (C)': ('TCHP', 'Historical charger name'),
    'Power Supply Proximity (C)': ('TPSP', 'iSMC broad-platform Power Supply Proximity; exact-model identity unproved'),
    'Wireless Proximity (C)': ('TW0P', 'Stats Airport / historical wireless name'),
}


def consolidate(paths, rows):
    sessions = []
    # Identical recordings must not inflate evidence counts; conflicting overlapping recordings fail.
    by_time = {}
    for path in paths:
        samples = correlation.load_samples(path)
        sessions.append((path.name, len(samples), len(correlation.pair_samples(samples, rows))))
        for time, values in samples:
            if time in by_time and by_time[time] != values:
                raise ValueError('Conflicting raw recordings at the same timestamp')
            by_time[time] = values
    samples = sorted(by_time.items())
    analysis = correlation.analyze(samples, rows)
    return analysis, correlation.pair_samples(samples, rows), sessions


def number(value):
    return '—' if value is None else f'{value:.3f}'


def render(analysis, pairs, sessions):
    lines = ['# Sensor comparison', '',
             'SMC recordings compared with TG Pro temperature exports. '
             'This offline analysis does not change qualification.', '',
             '## Recordings', '', '| Recording | Samples | Matched samples |', '| --- | ---: | ---: |']
    lines += [f'| {name} | {count} | {matched} |' for name, count, matched in sessions]
    lines += ['', f'{analysis["sourceSamples"]} unique samples; {analysis["matchedSamples"]} CSV matches within two seconds. '
              'Timestamps use UTC. Duplicate recordings count once; readings must be finite, positive `flt ` values.', '',
              '## Chassis candidates', '',
              '| Role | Expected key | MAE °C | Pairs | Reference spread °C | Source |',
              '| --- | --- | ---: | ---: | ---: | --- |']
    for name, (key, source) in CHASSIS.items():
        values = [(raw[key], reference[name]) for raw, reference, _ in pairs if key in raw and name in reference]
        metrics = correlation.metrics(values) if values else {}
        lines.append(f'| {name.removesuffix(" (C)")} | {key} | {number(metrics.get("meanAbsoluteErrorC"))} | '
                     f'{len(values)} | {number(metrics.get("referenceSpreadC"))} | {source} |')
    lines += ['', 'Expected keys stay in the table even when another key matches more closely.', '',
              '## Competing matches', '',
              '| TG Pro sensor | Filter result | Key / MAE °C / RMSE °C / correlation | Runner-up MAE gap °C |',
              '| --- | --- | --- | ---: |']
    for sensor in analysis['sensors']:
        matches = '; '.join(f'{c["key"]} / {number(c["meanAbsoluteErrorC"])} / '
                            f'{number(c["rootMeanSquareErrorC"])} / {number(c["correlation"])}' for c in sensor['candidates'][:3]) or 'None'
        lines.append(f'| {sensor["name"].removesuffix(" (C)")} | {sensor["evidence"]} | {matches} | {number(sensor["runnerUpMarginC"])} |')
    lines += ['', '## Chip groups', '',
              'Every member of the predefined group and reference must be present in a pair.', '',
              '| Candidate group | Complete pairs | MAE °C | RMSE °C | Largest under-read °C |',
              '| --- | ---: | ---: | ---: | ---: |']
    groups = [
        ('CPU', ['Tp00','Tp04','Tp08','Tp0C','Tp0G','Tp0K','Tp0O','Tp0R','Tp0U','Tp0X','Tp0a','Tp0d','Tp0g','Tp0j','Tp0m','Tp0p','Tp0u','Tp0y'],
         [f'Performance Core {i} (C)' for i in range(1, 11)] + [f'Super Core {i} (C)' for i in range(1, 6)]),
        ('GPU', ['Tg0U','Tg0X','Tg0d','Tg0g','Tg0j','Tg1Y','Tg1c'], [f'GPU Region {i} (C)' for i in range(1, 5)]),
    ]
    for name, keys, columns in groups:
        for method in ('average', 'peak'):
            values = []
            for raw, reference, _ in pairs:
                if all(k in raw for k in keys) and all(c in reference for c in columns):
                    raw_group, ref_group = [raw[k] for k in keys], [reference[c] for c in columns]
                    aggregate = max if method == 'peak' else lambda xs: sum(xs) / len(xs)
                    values.append((aggregate(raw_group), aggregate(ref_group)))
            metrics = correlation.metrics(values) if values else {}
            under_read = max(0, max((ref - value for value, ref in values), default=0)) if values else None
            lines.append(f'| {name} {method} | {len(values)} | {number(metrics.get("meanAbsoluteErrorC"))} | '
                         f'{number(metrics.get("rootMeanSquareErrorC"))} | {number(under_read)} |')
    lines += ['', 'Filters require 30 pairs and 3°C reference variation. A runner-up gap below 0.4°C or '
              'MAE above 0.75°C marks a match as ambiguous. Flat traces have no correlation value. '
              'These are comparison filters, not thermal limits.', '',
              'TG Pro exports rounded temperatures and friendly names. Agreement can suggest a mapping, '
              'but sensor identity and coverage need independent confirmation.', '',
              '[Reference sources and licenses](https://github.com/NidaleNieve/Fandy_MacOS/blob/main/THIRD_PARTY_NOTICES.md).', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tg-pro-csv', required=True)
    parser.add_argument('--samples', nargs='+', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    rows = correlation.load_rows(args.tg_pro_csv)
    analysis, pairs, sessions = consolidate([Path(p) for p in args.samples], rows)
    Path(args.output).write_text(render(analysis, pairs, sessions))
    print(f'Evidence report: {analysis["matchedSamples"]} matched samples; qualification unchanged')


if __name__ == '__main__':
    main()
