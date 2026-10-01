#!/usr/bin/env python3
"""Compare temperature-only exports. Rankings are evidence, never control qualification."""
import argparse
import bisect
import csv
import datetime
import json
import math
import re
import statistics
from pathlib import Path

TEMPERATURE_COLUMN = re.compile(
    r'^(?:Performance Core \d+|Super Core \d+|GPU Region \d+|Trackpad(?: Actuator)?|'
    r'Airflow (?:Left|Top|Right)|(?:Charger|Power Supply|Wireless) Proximity) \(C\)$'
)
UTC = datetime.timezone.utc


def temperature(value):
    try:
        value = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return value if math.isfinite(value) and 0 < value < 150 else None


def timestamp(value):
    parsed = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
    # Offline comparison expects naive reference timestamps to use UTC.
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.timestamp()


def load_samples(path):
    # Also accept the early discovery export with adjacent JSON objects.
    text = Path(path).read_text()
    decoder = json.JSONDecoder()
    samples = []
    offset = 0
    while offset < len(text):
        while offset < len(text) and text[offset].isspace():
            offset += 1
        if offset == len(text):
            break
        sample, offset = decoder.raw_decode(text, offset)
        values = {}
        for key in sample['keys']:
            # Unqualified ioft interpretations cannot establish a mapping.
            value = temperature(key.get('value'))
            if key.get('type') == 'flt ' and key.get('size') == 4 and value is not None:
                if key['key'] in values:
                    raise ValueError('Duplicate SMC key in sample')
                values[key['key']] = value
        samples.append((timestamp(sample['timestamp']), values))
    return sorted(samples, key=lambda item: item[0])


def load_rows(path):
    rows = []
    with open(path, newline='') as stream:
        for row in csv.DictReader(stream):
            values = {name: value for name, raw in row.items()
                      if name and TEMPERATURE_COLUMN.fullmatch(name)
                      and (value := temperature(raw)) is not None}
            rows.append((timestamp(row['Date'] + 'T' + row['Time']), values))
    return sorted(rows, key=lambda item: item[0])


def pair_samples(samples, rows, max_gap=2):
    times = [row[0] for row in rows]
    paired = []
    for time, values in samples:
        position = bisect.bisect_left(times, time)
        neighbors = [index for index in (position - 1, position) if 0 <= index < len(rows)]
        if not neighbors:
            continue
        index = min(neighbors, key=lambda index: (abs(times[index] - time), times[index]))
        if abs(times[index] - time) <= max_gap:
            paired.append((values, rows[index][1], abs(times[index] - time)))
    return paired


def metrics(pairs):
    raw, reference = zip(*pairs)
    errors = [a - b for a, b in pairs]
    raw_spread = max(raw) - min(raw)
    reference_spread = max(reference) - min(reference)
    correlation = None
    if len(pairs) >= 3 and statistics.pstdev(raw) > 0 and statistics.pstdev(reference) > 0:
        correlation = statistics.correlation(raw, reference)
    return {'samples': len(pairs), 'meanAbsoluteErrorC': statistics.mean(abs(e) for e in errors),
            'rootMeanSquareErrorC': math.sqrt(statistics.mean(e * e for e in errors)),
            'referenceSpreadC': reference_spread, 'smcSpreadC': raw_spread,
            'correlation': correlation}


def analyze(samples, rows):
    paired = pair_samples(samples, rows)
    columns = sorted({name for _, values in rows for name in values})
    keys = sorted({name for values, _, _ in paired for name in values})
    result = {'matchedSamples': len(paired), 'sourceSamples': len(samples),
              'qualificationChanged': False, 'sensors': []}
    for column in columns:
        available = sum(column in reference for _, reference, _ in paired)
        ranked = []
        for key in keys:
            values = [(raw[key], reference[column]) for raw, reference, _ in paired
                      if key in raw and column in reference]
            # Do not let a disappearing sensor win from a tiny favorable subset.
            if values and len(values) == available:
                ranked.append({'key': key, **metrics(values)})
        ranked.sort(key=lambda item: (item['meanAbsoluteErrorC'], item['key']))
        if not ranked:
            evidence = 'noContemporaneousData'
            margin = None
        else:
            margin = ranked[1]['meanAbsoluteErrorC'] - ranked[0]['meanAbsoluteErrorC'] if len(ranked) > 1 else None
            if available < 30 or ranked[0]['referenceSpreadC'] < 3:
                evidence = 'insufficientVariation'
            elif margin is None or margin < 0.4 or ranked[0]['meanAbsoluteErrorC'] > 0.75:
                evidence = 'ambiguous'
            else:
                # Still requires independent identity and coverage review, including timing/rounding.
                evidence = 'candidateForReview'
        result['sensors'].append({'name': column, 'evidence': evidence, 'runnerUpMarginC': margin, 'candidates': ranked[:5]})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('samples')
    parser.add_argument('tg_pro_csv')
    parser.add_argument('--json', action='store_true')
    arguments = parser.parse_args()
    try:
        result = analyze(load_samples(arguments.samples), load_rows(arguments.tg_pro_csv))
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f'Cannot compare temperature exports: {type(error).__name__}\n')
    if arguments.json:
        print(json.dumps(result, allow_nan=False, sort_keys=True))
    else:
        print('Matched samples:', result['matchedSamples'], '/', result['sourceSamples'], '; qualification unchanged')
        for sensor in result['sensors']:
            rankings = [(round(c['meanAbsoluteErrorC'], 3), c['key']) for c in sensor['candidates']]
            print(sensor['name'], sensor['evidence'], rankings)
    return 0 if result['matchedSamples'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
