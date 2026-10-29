import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('profile_granite', ROOT / 'scripts/profile_granite.py')
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class ProfileSnapshots(unittest.TestCase):
    def test_expected_outputs_verify_full_workload(self):
        self.assertEqual(profile.expected('richards', 3), 'Richards queued=6966 held=2784\n')
        self.assertEqual(profile.expected('deltablue', 3), 'DeltaBlue runs=3 verified\n')
        self.assertEqual(profile.expected('queens', 3), '92\n')
        self.assertEqual(profile.expected('queens', 0), '0\n')

    def test_snapshots_use_checked_sources_without_the_default_queens_driver(self):
        for name in ['richards', 'deltablue']:
            self.assertEqual(profile.snapshot(name), (ROOT / 'benchmark' / (name + '.hrd')).read_text())
        source = profile.snapshot('queens')
        self.assertTrue(source.startswith('| repetitions solver answer |'))
        self.assertIn('Wrong Queens result', source)
        self.assertIn('repetitions timesRepeat:', source)
        self.assertNotIn('# Benchmark driver', source)


if __name__ == '__main__':
    unittest.main()
