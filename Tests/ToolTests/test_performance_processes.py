import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('performance_processes', Path(__file__).parents[2] / 'Scripts/performance_processes.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PerformanceProcessTests(unittest.TestCase):
    def test_cpu_time_formats_preserve_fractional_seconds(self):
        self.assertAlmostEqual(module.cpu_seconds('2:03.25'), 123.25)
        self.assertAlmostEqual(module.cpu_seconds('1:02:03.5'), 3723.5)
        self.assertAlmostEqual(module.cpu_seconds('2-01:02:03.5'), 176523.5)

    def test_malformed_cpu_time_is_not_a_zero_measurement(self):
        for value in ['', 'unknown', '1:garbage', 'bad:0:0']:
            with self.subTest(value=value), self.assertRaises((ValueError, IndexError)):
                module.cpu_seconds(value)

class ResourceBenchmarkTests(unittest.TestCase):
    def test_window_summary_uses_cpu_deltas_and_distinguishes_resident_memory(self):
        rows = [{'elapsedSeconds': t, 'pid': 10, 'cpuSeconds': c, 'residentKiB': rss}
                for t, c, rss in [(0, 100, 1000), (10, 100.1, 1100), (20, 100.4, 1200)]]
        result = module.summarize(rows)
        self.assertAlmostEqual(result['10']['cpuPercent'], 2.0)
        self.assertEqual(result['10']['residentMedianKiB'], 1100)
        self.assertEqual(result['10']['durationSeconds'], 20)

    def test_incomplete_or_restarted_process_windows_are_not_valid_improvements(self):
        for rows in [[], [{'elapsedSeconds': 0, 'pid': 10, 'cpuSeconds': 1, 'residentKiB': 10}],
                     [{'elapsedSeconds': 0, 'pid': 10, 'cpuSeconds': 2, 'residentKiB': 10},
                      {'elapsedSeconds': 10, 'pid': 10, 'cpuSeconds': 1, 'residentKiB': 10}]]:
            with self.assertRaises(ValueError): module.summarize(rows)

class FootprintTests(unittest.TestCase):
    def test_native_footprint_parser_rejects_missing_and_invalid_measurements(self):
        self.assertEqual(module.parse_footprint(12, 'PID MEM\n12 5713K+\n'), 5713 * 1024)
        self.assertEqual(module.parse_footprint(12, 'PID MEM\n12 17.5M\n'), int(17.5 * 1024 * 1024))
        for text in ['PID MEM\n13 20M\n', 'PID MEM\n12 0B\n', 'PID MEM\n12 -2M\n', 'PID MEM\n12 NaNM\n']:
            with self.assertRaises(ValueError):
                module.parse_footprint(12, text)

    def test_summary_keeps_footprint_separate_from_resident_size(self):
        rows = [dict(pid=1, elapsedSeconds=0, cpuSeconds=1, residentKiB=80, footprintBytes=20),
                dict(pid=1, elapsedSeconds=10, cpuSeconds=2, residentKiB=100, footprintBytes=30)]
        result = module.summarize(rows)['1']
        self.assertEqual(result['residentMedianKiB'], 90)
        self.assertEqual(result['footprintMedianBytes'], 25)
        self.assertEqual(result['footprintMaximumBytes'], 30)
