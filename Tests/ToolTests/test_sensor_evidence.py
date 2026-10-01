import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('sensor_evidence', Path(__file__).parents[2] / 'Scripts/consolidate-sensor-evidence.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SensorEvidenceTests(unittest.TestCase):
    def sample(self, value=27):
        return {'timestamp': '2026-09-30T12:00:00Z', 'keys': [
            {'key': 'Ts0P', 'type': 'flt ', 'size': 4, 'value': value}]}

    def test_duplicate_files_do_not_inflate_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / 'one.jsonl', Path(directory) / 'two.jsonl']
            for path in paths:
                path.write_text(json.dumps(self.sample()))
            rows = [(module.correlation.timestamp(self.sample()['timestamp']), {'Trackpad (C)': 27})]
            analysis, pairs, sessions = module.consolidate(paths, rows)
            self.assertEqual(analysis['sourceSamples'], 1)
            self.assertEqual(analysis['matchedSamples'], 1)
            self.assertFalse(analysis['qualificationChanged'])
            text = module.render(analysis, pairs, sessions)
            self.assertIn('All identities remain pending', text)
            self.assertIn('Ts0P', text)
            self.assertIn('insufficientVariation', text)

    def test_conflicting_same_time_samples_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / 'one.jsonl', Path(directory) / 'two.jsonl']
            for path, value in zip(paths, [27, 31]):
                path.write_text(json.dumps(self.sample(value)))
            with self.assertRaises(ValueError):
                module.consolidate(paths, [])

    def test_named_candidate_is_not_replaced_by_best_numeric_match(self):
        analysis = {'sourceSamples': 1, 'matchedSamples': 1, 'sensors': [{
            'name': 'Trackpad (C)', 'evidence': 'ambiguous', 'runnerUpMarginC': .1,
            'candidates': [{'key': 'Fake', 'meanAbsoluteErrorC': 0, 'rootMeanSquareErrorC': 0, 'correlation': 1}]}]}
        text = module.render(analysis, [({'Ts0P': 27.5}, {'Trackpad (C)': 27}, 0)], [('sample', 1, 1)])
        self.assertIn('| Trackpad | Ts0P | 0.500 |', text)
        self.assertIn('Fake / 0.000', text)


if __name__ == '__main__':
    unittest.main()
