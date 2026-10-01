import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('measurement_report', Path(__file__).parents[2] / 'Scripts/measurement-report.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class MeasurementReportTests(unittest.TestCase):
    def records(self):
        return [{'elapsed': t, 'phase': phase, 'model': 'Mac17,9', 'fans': [{'id': 0, 'mode': 0}, {'id': 1, 'mode': 0}],
                 'timestamp': '2026-10-01T12:00:00Z', 'keys': [{'key': key, 'type': 'flt ', 'size': 4, 'value': 40 if key in m.CPU else 35} for key in m.CPU + m.GPU]}
                for t, phase in zip([0,60,90,210,240,959], ['baseline','cpu','cpuCooldown','gpu','gpuCooldown','chassis'])]

    def test_incomplete_or_aborted_session_cannot_claim_completion(self):
        records = self.records()
        with self.assertRaises(ValueError):
            m.validate_session(records, 'Measurement aborted')
        with self.assertRaises(ValueError):
            m.validate_session(records[:-1], 'Measurement completed: 960-second bounded cycle, no fan writes.')
        records[-1]['fans'][1]['mode'] = 1
        with self.assertRaises(ValueError):
            m.validate_session(records, 'Measurement completed: 960-second bounded cycle, no fan writes.')

    def test_reference_peak_underread_and_timing_are_reported_without_qualification(self):
        records = self.records()
        time = m.c.timestamp(records[0]['timestamp'])
        phases = m.summarize(records, [(time, {'Performance Core 1 (C)': 45, 'GPU Region 1 (C)': 37})])
        self.assertEqual(phases['cpu']['cpuUnder'], [5])
        self.assertEqual(phases['gpu']['gpuUnder'], [2])
        self.assertIn('Every sensor capability remains pending', m.render(records, phases))
        phases = m.summarize(records, [(time+3, {'Performance Core 1 (C)': 45})])
        self.assertEqual(phases['cpu']['pairs'], 0)

    def test_missing_chip_member_rejects_evidence(self):
        records = self.records()
        records[0]['keys'].pop()
        with self.assertRaises(ValueError):
            m.summarize(records, [])
