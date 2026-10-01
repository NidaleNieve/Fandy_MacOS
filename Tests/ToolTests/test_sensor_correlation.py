import importlib.util
import json
import math
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('sensor_correlation', Path(__file__).parents[2] / 'Scripts/correlate-sensors.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SensorCorrelationTests(unittest.TestCase):
    def test_invalid_numbers_cannot_match_temperatures(self):
        for value in (None, '', 'bad', 'NaN', 'Infinity', '-Infinity', 0, -5, 150, 1e309):
            self.assertIsNone(module.temperature(value))
        self.assertEqual(module.temperature('27.5'), 27.5)

    def test_timezone_is_explicit_and_offsets_match(self):
        self.assertEqual(module.timestamp('2026-09-30T12:00:00'), module.timestamp('2026-09-30T12:00:00Z'))
        self.assertEqual(module.timestamp('2026-09-30T14:00:00+02:00'), module.timestamp('2026-09-30T12:00:00Z'))

    def test_pairing_rejects_stale_and_handles_empty_rows(self):
        self.assertEqual(module.pair_samples([(10, {})], []), [])
        self.assertEqual(module.pair_samples([(10, {})], [(1, {})]), [])
        self.assertEqual(len(module.pair_samples([(10, {})], [(8, {})])), 1)

    def test_flat_coincidence_cannot_qualify(self):
        samples = [(t, {'Ts0P': 27, 'Other': 27}) for t in range(40)]
        rows = [(t, {'Trackpad (C)': 27}) for t in range(40)]
        result = module.analyze(samples, rows)
        self.assertEqual(result['sensors'][0]['evidence'], 'insufficientVariation')
        self.assertFalse(result['qualificationChanged'])
        self.assertIsNone(result['sensors'][0]['candidates'][0]['correlation'])
        json.dumps(result, allow_nan=False)

    def test_ambiguous_dynamic_matches_are_flagged(self):
        samples = [(t, {'Ts0P': 20 + t / 4, 'Other': 20.1 + t / 4}) for t in range(40)]
        rows = [(t, {'Trackpad (C)': 20 + t / 4}) for t in range(40)]
        self.assertEqual(module.analyze(samples, rows)['sensors'][0]['evidence'], 'ambiguous')

    def test_missing_key_cannot_win_from_subset(self):
        samples = [(t, {'Whole': 20.5 + t / 4, **({'Missing': 20 + t / 4} if t < 10 else {})}) for t in range(40)]
        rows = [(t, {'Trackpad (C)': 20 + t / 4}) for t in range(40)]
        candidates = module.analyze(samples, rows)['sensors'][0]['candidates']
        self.assertEqual([c['key'] for c in candidates], ['Whole'])

    def test_unique_match_is_only_a_review_candidate(self):
        samples = [(t, {'Ts0P': 20 + t / 4, 'Other': 30}) for t in range(40)]
        rows = [(t, {'Trackpad (C)': 20 + t / 4}) for t in range(40)]
        result = module.analyze(samples, rows)
        self.assertEqual(result['sensors'][0]['evidence'], 'candidateForReview')
        self.assertFalse(result['qualificationChanged'])

    def test_loader_excludes_unqualified_types_and_adjacent_json_works(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'samples.jsonl'
            sample = {'timestamp': '2026-09-30T12:00:00Z', 'keys': [
                {'key': 'Ts0P', 'type': 'flt ', 'size': 4, 'value': 27},
                {'key': 'Other', 'type': 'ioft', 'size': 8, 'value': 27}]}
            path.write_text(json.dumps(sample) + json.dumps(sample))
            loaded = module.load_samples(path)
            self.assertEqual(len(loaded), 2)
            self.assertEqual(loaded[0][1], {'Ts0P': 27})

    def test_csv_loader_keeps_only_requested_temperature_columns(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'sample.csv'
            path.write_text('Date,Time,Trackpad (C),Serial Number,Charge Cycles\n2026-09-30,12:00:00,27,PRIVATE,100\n')
            rows = module.load_rows(path)
            self.assertEqual(rows[0][1], {'Trackpad (C)': 27})


if __name__ == '__main__':
    unittest.main()
