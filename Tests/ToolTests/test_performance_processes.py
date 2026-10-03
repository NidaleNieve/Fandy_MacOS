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
