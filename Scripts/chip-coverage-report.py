#!/usr/bin/env python3
"""Compare recorded chip-sensor groups with reference temperatures."""
import argparse
import collections
import importlib.util
import json
import statistics
from pathlib import Path

spec = importlib.util.spec_from_file_location('correlation', Path(__file__).with_name('correlate-sensors.py'))
correlation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(correlation)

CPU = ['Tp00', 'Tp04', 'Tp08', 'Tp0C', 'Tp0G', 'Tp0K', 'Tp0O', 'Tp0R', 'Tp0U',
       'Tp0X', 'Tp0a', 'Tp0d', 'Tp0g', 'Tp0j', 'Tp0m', 'Tp0p', 'Tp0u', 'Tp0y']
GPU = ['Tg0U', 'Tg0X', 'Tg0d', 'Tg0g', 'Tg0j', 'Tg1Y', 'Tg1c', 'Tg1g']
CPU_COLUMNS = [f'Performance Core {i} (C)' for i in range(1, 11)] + [f'Super Core {i} (C)' for i in range(1, 6)]
GPU_COLUMNS = [f'GPU Region {i} (C)' for i in range(1, 5)]


def load_model_samples(path):
    # This audit accepts complete JSONL discoveries for the exact development model.
    records = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
    if not records or any(record.get('model') != 'Mac17,9' for record in records):
        raise ValueError('Expected only Mac17,9 recordings')
    return correlation.load_samples(path)


def compare_group(pairs, keys, columns):
    values = [(max(raw[key] for key in keys), max(reference[column] for column in columns))
              for raw, reference, _ in pairs
              if keys and all(key in raw for key in keys) and all(column in reference for column in columns)]
    if not values:
        return {'pairs': 0, 'mae': None, 'underRead': None, 'overRead': None}
    return {'pairs': len(values), 'mae': statistics.mean(abs(a-b) for a, b in values),
            'underRead': max(0, max(b-a for a, b in values)), 'overRead': max(0, max(a-b for a, b in values))}


def audit(samples, rows):
    pairs = correlation.pair_samples(samples, rows)
    seen = set().union(*(set(raw) for _, raw in samples)) if samples else set()
    result = {'sourceSamples': len(samples), 'matchedSamples': len(pairs), 'qualificationChanged': False, 'domains': []}
    for name, published, columns, prefixes in [('CPU', CPU, CPU_COLUMNS, ('Tp', 'Tm')), ('GPU', GPU, GPU_COLUMNS, ('Tg',))]:
        present = sorted(set(published) & seen)
        families = {prefix: sorted(key for key in seen if key.startswith(prefix)) for prefix in prefixes}
        groups = [('Full published domain', published), ('Present published candidates', present)]
        groups += [(f'Exploratory {prefix} family', keys) for prefix, keys in families.items()]
        if len(prefixes) > 1:
            groups.append(('Exploratory family union', sorted(set().union(*map(set, families.values())))))
        comparisons = [{'name': label, 'keys': keys, **compare_group(pairs, keys, columns)} for label, keys in groups]
        # Find hotter omitted keys for review; a prefix does not identify their physical role.
        omitted = sorted(set().union(*map(set, families.values())) - set(present))
        higher = []
        for key in omitted:
            deltas = [raw[key] - max(raw[k] for k in present) for raw, _, _ in pairs
                      if present and key in raw and all(k in raw for k in present)]
            above = [delta for delta in deltas if delta > 0.5]
            if above:
                higher.append({'key': key, 'pairs': len(deltas), 'aboveRoundedMargin': len(above), 'maximumDelta': max(above)})
        higher.sort(key=lambda item: (-item['aboveRoundedMargin'], -item['maximumDelta'], item['key']))
        # Exact-value aliases across the entire recording, not correlations or rounded temperatures.
        traces = collections.defaultdict(list)
        for key in sorted(set().union(*map(set, families.values()))):
            if samples and all(key in raw for _, raw in samples):
                traces[tuple(raw[key] for _, raw in samples)].append(key)
        aliases = [keys for keys in traces.values() if len(keys) > 1]
        result['domains'].append({'name': name, 'absentPublished': sorted(set(published) - seen),
                                  'comparisons': comparisons, 'higherOmissions': higher, 'exactValueAliases': aliases})
    return result


def number(value):
    return '—' if value is None else f'{value:.3f}'


def render(result):
    lines = ['# Mac17,9 chip coverage', '',
             f'{result["sourceSamples"]} samples; {result["matchedSamples"]} TG Pro pairs within two seconds.', '',
             'Stats M5 candidate groups are compared with the wider recorded sensor families. '
             'Prefix groups are exploratory and never select production control inputs. '
             'Only complete groups and references enter each comparison.', '']
    for domain in result['domains']:
        lines += [f'## {domain["name"]}', '',
                  'Absent published keys: ' + (', '.join(domain['absentPublished']) or 'none') + '.', '',
                  '| Peak group | Keys | Complete pairs | MAE °C | Maximum under-read °C | Maximum over-read °C |',
                  '| --- | ---: | ---: | ---: | ---: | ---: |']
        for group in domain['comparisons']:
            lines.append(f'| {group["name"]} | {len(group["keys"])} | {group["pairs"]} | {number(group["mae"])} | '
                         f'{number(group["underRead"])} | {number(group["overRead"])} |')
        lines += ['', 'Unselected keys above the candidate peak by more than 0.5°C:', '',
                  '| Key | Complete comparisons | Above margin | Maximum difference °C |', '| --- | ---: | ---: | ---: |']
        for omission in domain['higherOmissions'][:12]:
            lines.append(f'| {omission["key"]} | {omission["pairs"]} | {omission["aboveRoundedMargin"]} | {number(omission["maximumDelta"])} |')
        if not domain['higherOmissions']:
            lines.append('| None in this recording | — | — | — |')
        lines += ['', 'Identical traces: '
                  + ('; '.join('/'.join(keys) for keys in domain['exactValueAliases']) or 'none') + '.', '']
    lines += ['A hotter unselected key may belong to memory or another domain. Identical traces can show '
              'redundancy in a recording without establishing physical sensor identity. '
              'Rounding, acquisition lag and different group definitions also affect comparisons. '
              'The 0.5°C reporting margin is not a thermal limit.', '',
              'This offline report does not change qualification.', '',
              'Candidate source: [Stats M5 sensor definitions](https://github.com/exelban/stats/blob/d85c26351cb16335d6af2219f19e543016d4d416/Modules/Sensors/values.swift).', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples', required=True)
    parser.add_argument('--tg-pro-csv', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = audit(load_model_samples(args.samples), correlation.load_rows(args.tg_pro_csv))
    Path(args.output).write_text(render(result))
    print(f'Coverage audit: {result["matchedSamples"]} pairs; qualification unchanged')


if __name__ == '__main__':
    main()
