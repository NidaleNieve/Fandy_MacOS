#!/usr/bin/env python3
"""Offline evidence review. Reads temperature-only references; cannot alter qualification."""
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
    lines = ['# M5 Pro sensor qualification evidence', '',
             'Offline consolidation of existing Mac17,9 recordings against the authorized TG Pro temperature export. '
             '**Analysis does not change qualification or fan state.**', '',
             'TG Pro exports friendly names and rounded temperatures, not SMC identifiers. '
             'Only contemporaneous samples can link those names to raw keys. All identities remain pending review; '
             'historical names and numerical agreement alone do not qualify current firmware.', '',
             '## Recording coverage', '', '| Recording | Raw samples | Matched samples |', '| --- | ---: | ---: |']
    lines += [f'| {name} | {count} | {matched} |' for name, count, matched in sessions]
    lines += ['', f'Unique raw samples: {analysis["sourceSamples"]}; contemporaneous matches: {analysis["matchedSamples"]}. '
              'Nearest CSV timestamp must be within 2 seconds; export timestamps use Iceland/UTC. '
              'Duplicate recordings do not increase evidence counts. Only finite positive `flt ` values with size 4 are used. '
              '`ioft` interpretations, missing keys, unrelated CSV fields and diagnostics are excluded.', '',
              '## Chassis candidates', '',
              '| Role | Expected key | Expected-key MAE °C | Pairs | Reference spread °C | Evidence source |',
              '| --- | --- | ---: | ---: | ---: | --- |']
    for name, (key, source) in CHASSIS.items():
        values = [(raw[key], reference[name]) for raw, reference, _ in pairs if key in raw and name in reference]
        metrics = correlation.metrics(values) if values else {}
        lines.append(f'| {name.removesuffix(" (C)")} | {key} | {number(metrics.get("meanAbsoluteErrorC"))} | '
                     f'{len(values)} | {number(metrics.get("referenceSpreadC"))} | {source} |')
    lines += ['', 'Expected-key metrics are reported even if a competing key matches more closely. '
              'Different temperature scales remain separate: Trackpad and Actuator curves use their own raw readings; '
              'Airflow uses its hottest qualified member. Charger, Power Supply and Wireless readings are required by '
              'the all-sensors-first discovery gate but do not independently increase comfort demand.', '',
              '## Competing matches and timing agreement', '',
              '| TG Pro reference | Evidence filter | Best matches: key / MAE °C / RMSE °C / correlation | Runner-up MAE margin °C |',
              '| --- | --- | --- | ---: |']
    for sensor in analysis['sensors']:
        matches = '; '.join(f'{c["key"]} / {number(c["meanAbsoluteErrorC"])} / '
                            f'{number(c["rootMeanSquareErrorC"])} / {number(c["correlation"])}' for c in sensor['candidates'][:3]) or 'None'
        lines.append(f'| {sensor["name"].removesuffix(" (C)")} | {sensor["evidence"]} | {matches} | {number(sensor["runnerUpMarginC"])} |')
    lines += ['', '## Candidate chip aggregation', '',
              'These comparisons use the whole predefined candidate groups, rather than selecting a '
              'different closest key for each export row. TG Pro core/region semantics and SMC group '
              'membership still need independent review. Missing members exclude the entire pair.', '',
              '| Candidate aggregation | Complete pairs | MAE °C | RMSE °C | Largest under-read versus TG Pro °C |',
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
    lines += ['', 'Filters require 30 pairs and 3°C reference variation; matches remain ambiguous when the '
              'runner-up margin is below 0.4°C or MAE exceeds 0.75°C. These are exploratory filters, '
              '**not thermal limits or automatic qualification rules**. Correlation is unavailable for flat traces. '
              'Pooling sessions improves variation but cannot remove rounding, sampling offset, common thermal '
              'movement or firmware-label ambiguity.', '',
              '## Chip coverage and remaining blockers', '',
              '- CPU candidates from the inspected Stats M5 table: '
              '`Tp00/Tp04/Tp08/Tp0C/Tp0G/Tp0K/Tp0O/Tp0R/Tp0U/Tp0X/Tp0a/Tp0d/Tp0g/Tp0j/Tp0m/Tp0p/Tp0u/Tp0y`.',
              '- GPU candidates: `Tg0U/Tg0X/Tg0d/Tg0g/Tg0j/Tg1Y/Tg1c`. '
              'TG Pro reports four GPU regions; their relationship to these seven candidates remains unproved.',
              '- Average and peak values are informational candidates. Active CPU membership and reliable '
              'CPU/GPU peak coverage must be demonstrated before any control lease.',
              '- iSMC provides independent broad-platform naming candidates for TaTP/TPSP, not an exact-model '
              'identity proof. Airflow Top and Power Supply identity need explicit resolution. Historical chassis mappings '
              'need current-model corroboration; no closest-temperature substitution is permitted.',
              '- The [chip coverage audit](CHIP_COVERAGE.md) compares complete published groups with wider '
              'enumerated families, and finds hotter unselected readings. It does not adopt prefix-based control. '
              'Resolve their provenance and membership before granting peak coverage.',
              '- Next measurement sessions must answer specific unresolved mappings, using distinct CPU/GPU '
              'changes and longer naturally varying chassis traces under verified Apple control. '
              'Repeating flat idle recordings is not an acceptance test.',
              '- Every requested chip/chassis role remains required before manual qualification writes. '
              'Independent hardware readings remain the production source; TG Pro logging is a development reference.', '',
              'Source revisions, licenses and provenance are recorded in [RESEARCH.md](RESEARCH.md), '
              '[SENSOR_DISCOVERY.md](SENSOR_DISCOVERY.md) and the bundled license notices. '
              'The comparison tool is independently authored; no TG Pro source or proprietary mapping database is used.', '']
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
