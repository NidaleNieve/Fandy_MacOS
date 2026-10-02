#!/usr/bin/env python3
"""Report finite selected-key measurements; never changes mapping or control authority."""
import argparse
import collections
import json
import math
import statistics
from pathlib import Path

COMFORT = {'Trackpad': 'Ts0P', 'Actuator': 'Ts1P', 'Airflow Left': 'TaLP', 'Airflow Top': 'TaTP', 'Airflow Right': 'TaRF'}


def analyze(records):
    if not records or any(r.get('model') != 'Mac17,9' for r in records):
        raise ValueError('Expected a nonempty Mac17,9 session')
    keys = None
    for record in records:
        readings = record['keys']
        current = {r['key'] for r in readings}
        if len(current) != len(readings) or (keys is not None and current != keys):
            raise ValueError('Duplicate or changing selected-key membership')
        keys = current
        if len(record['fans']) != 2 or {f['id'] for f in record['fans']} != {0, 1} or any(f['mode'] != 0 for f in record['fans']):
            raise ValueError('Automatic ownership was not maintained')
        for reading in readings:
            value = reading.get('value')
            at = reading.get('sampledAt')
            if (reading.get('type') != 'flt ' or reading.get('size') != 4 or reading.get('error') or
                    not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 < value < 75 or
                    not isinstance(at, (int, float)) or not math.isfinite(at)):
                raise ValueError('Invalid selected-key reading')
    phases = collections.Counter(r['phase'] for r in records)
    result = {'records': len(records), 'phaseSamples': dict(phases), 'qualificationChanged': False,
              'selectedKeyCount': len(keys), 'absentPublishedGPU': ['Tg1g'] if 'Tg1g' not in keys else [],
              'domains': {}, 'comfort': {}, 'acquisitionSpanMaxS': max(max(k['sampledAt'] for k in r['keys']) - min(k['sampledAt'] for k in r['keys']) for r in records)}
    def values(record):
        return {k['key']: k['value'] for k in record['keys']}
    for name, prefix, phase, baseline in [('Tp candidates', 'Tp', 'cpu', 'baseline'), ('Tm candidates', 'Tm', 'cpu', 'baseline'), ('Tg candidates', 'Tg', 'gpu', 'cpuCooldown')]:
        members = sorted(k for k in keys if k.startswith(prefix))
        if not members:
            continue
        if phase == 'gpu' and not any(r['phase'] == baseline for r in records):
            baseline = 'baseline'
        prior = [r for r in records if r['phase'] == baseline][-10:]
        active = [r for r in records if r['phase'] == phase]
        peaks = lambda rows: [max(values(r)[key] for key in members) for r in rows]
        change = max(peaks(active)) - statistics.median(peaks(prior)) if prior and active else None
        result['domains'][name] = {'members': members, 'baselinePeakMedianC': statistics.median(peaks(prior)) if prior else None,
            'pulsePeakMaxC': max(peaks(active)) if active else None, 'pulseRiseC': change,
            'independentVariationObserved': len(prior) >= 10 and len(active) >= 10 and change is not None and change >= 3,
            'note': 'The 3 C filter describes diagnostic variation, not identity qualification or an Apple thermal threshold.'}
    for name, key in COMFORT.items():
        if key in keys:
            samples = [values(r)[key] for r in records]
            result['comfort'][name] = {'key': key, 'minimumC': min(samples), 'maximumC': max(samples)}
    return result


def render(result):
    lines = ['# Targeted temperature session', '',
             f'{result["records"]} records, {result["selectedKeyCount"]} selected keys; both fans automatic throughout.',
             f'Maximum selected-key acquisition span: {result["acquisitionSpanMaxS"]:.3f} seconds.', '',
             '| Candidate domain | Keys | Pre-pulse peak median | Pulse maximum | Rise | Independent variation |',
             '| --- | ---: | ---: | ---: | ---: | --- |']
    for name, domain in result['domains'].items():
        def number(value): return 'unavailable' if value is None else f'{value:.2f} C'
        lines.append(f'| {name} | {len(domain["members"])} | {number(domain["baselinePeakMedianC"])} | {number(domain["pulsePeakMaxC"])} | {number(domain["pulseRiseC"])} | {domain["independentVariationObserved"]} |')
    lines += ['', 'The GPU pulse must show independent variation before it can resolve regional coverage. '
              'Low-duty success or common heat movement alone does not prove that coverage. No qualification was changed.', '',
              'Reference matching must be reported separately using contemporaneous CSV rows. '
              'Named PMU temperature events are supplementary die readings, not substitutes for identified CPU/GPU groups.', '',
              '| Comfort candidate | Key | Minimum | Maximum |', '| --- | --- | ---: | ---: |']
    for name, reading in result['comfort'].items():
        lines.append(f'| {name} | {reading["key"]} | {reading["minimumC"]:.2f} C | {reading["maximumC"]:.2f} C |')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('samples')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    records = [json.loads(line) for line in Path(args.samples).read_text().splitlines() if line.strip()]
    result = analyze(records)
    print(json.dumps(result, indent=2, allow_nan=False) if args.json else render(result), end='\n')


if __name__ == '__main__':
    main()
