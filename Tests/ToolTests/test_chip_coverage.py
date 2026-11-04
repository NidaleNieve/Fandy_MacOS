import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('chip_coverage', Path(__file__).parents[2] / 'Scripts/chip-coverage-report.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ChipCoverageTests(unittest.TestCase):
    def test_missing_members_exclude_the_entire_pair(self):
        pairs = [({'Tp00': 40}, {'CPU': 45}, 0)]
        self.assertEqual(module.compare_group(pairs, ['Tp00', 'Tp04'], ['CPU'])['pairs'], 0)
        self.assertEqual(module.compare_group(pairs, ['Tp00'], ['CPU', 'Other'])['pairs'], 0)
        self.assertEqual(module.compare_group(pairs, [], ['CPU'])['pairs'], 0)

    def test_unselected_hot_family_is_reported_without_qualification(self):
        raw = {key: 40 for key in module.CPU}; raw['Tm00'] = 50
        reference = {column: 45 for column in module.CPU_COLUMNS}
        result = module.audit([(10, raw)], [(10, reference)])
        self.assertFalse(result['qualificationChanged'])
        cpu = result['domains'][0]
        self.assertEqual(cpu['higherOmissions'][0]['key'], 'Tm00')
        self.assertEqual(cpu['higherOmissions'][0]['maximumDelta'], 10)
        self.assertIn('never select production control inputs', module.render(result))
        self.assertEqual(result['domains'][1]['comparisons'][0]['pairs'], 0)

    def test_alias_requires_exact_complete_trace_not_correlation(self):
        samples = [(10, {'Tp00': 40, 'Tp01': 40, 'Tp02': 40.1}), (11, {'Tp00': 41, 'Tp01': 41, 'Tp02': 41.1})]
        aliases = module.audit(samples, [])['domains'][0]['exactValueAliases']
        self.assertEqual(aliases, [['Tp00', 'Tp01']])
        del samples[1][1]['Tp01']
        self.assertEqual(module.audit(samples, [])['domains'][0]['exactValueAliases'], [])

    def test_wrong_model_and_invalid_numeric_values_do_not_enter_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'raw.jsonl'
            record = {'model': 'Mac17,9', 'timestamp': '2026-10-01T12:00:00Z', 'keys': [
                {'key': 'Tp00', 'type': 'flt ', 'size': 4, 'value': 40},
                {'key': 'Tp04', 'type': 'flt ', 'size': 4, 'value': float('nan')}]}
            path.write_text(json.dumps(record))
            self.assertEqual(module.load_model_samples(path)[0][1], {'Tp00': 40})
            record['model'] = 'Other'; path.write_text(json.dumps(record))
            with self.assertRaises(ValueError):
                module.load_model_samples(path)

    def test_report_keeps_group_metrics_without_claiming_an_old_gpu_test_result(self):
        raw = {key: 40 for key in module.CPU + module.GPU}
        reference = {column: 45 for column in module.CPU_COLUMNS + module.GPU_COLUMNS}
        text = module.render(module.audit([(10, raw)], [(10, reference)]))
        self.assertIn('| Full published domain | 8 | 1 | 5.000 |', text)
        self.assertIn('never select production control inputs', text)
        self.assertNotIn('Current sensor capabilities remain pending', text)
        self.assertNotIn('bounded GPU phase lacked', text)
        self.assertNotIn('Consequences for the next measurement', text)


if __name__ == '__main__':
    unittest.main()
