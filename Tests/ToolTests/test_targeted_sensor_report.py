import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('targeted_report', Path(__file__).parents[2] / 'Scripts/targeted-sensor-report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def record(phase, gpu=40):
    return {'model': 'Mac17,9', 'phase': phase, 'fans': [{'id': 0, 'mode': 0}, {'id': 1, 'mode': 0}],
            'keys': [{'key': key, 'type': 'flt ', 'size': 4, 'value': value, 'error': None, 'sampledAt': 10 + i / 10}
                     for i, (key, value) in enumerate([('Tp00', 45 if phase == 'cpu' else 40), ('Tm00', 44 if phase == 'cpu' else 40), ('Tg0U', gpu)])]}


class TargetedReportTests(unittest.TestCase):
    def test_insufficient_gpu_does_not_pass_variation_filter(self):
        rows = [record(p, 40.5 if p == 'gpu' else 40) for p in ['baseline', 'cpu', 'cpuCooldown', 'gpu'] for _ in range(10)]
        result = report.analyze(rows)
        self.assertFalse(result['qualificationChanged'])
        self.assertTrue(result['domains']['Tm candidates']['independentVariationObserved'])
        self.assertFalse(result['domains']['Tg candidates']['independentVariationObserved'])
        self.assertIn('Tg1g', result['absentPublishedGPU'])
    def test_nonfinite_missing_and_changing_membership_reject(self):
        for value in [None, float('nan'), float('inf'), 75, 0]:
            row = record('baseline'); row['keys'][0]['value'] = value
            with self.assertRaises(ValueError): report.analyze([row])
        row = record('baseline'); row['keys'].pop()
        with self.assertRaises(ValueError): report.analyze([record('baseline'), row])
    def test_manual_or_duplicate_fan_does_not_prove_ownership(self):
        for change in [lambda r: r['fans'][0].update(mode=1), lambda r: r['fans'][1].update(id=0)]:
            row = record('baseline'); change(row)
            with self.assertRaises(ValueError): report.analyze([row])
