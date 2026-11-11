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
        # The added workloads assert their own answer and scale linearly, so the
        # harness can check every repetition count it times.
        self.assertEqual(profile.expected('shapes', 1), '178000\n')
        self.assertEqual(profile.expected('shapes', 3), '534000\n')
        self.assertEqual(profile.expected('tree', 2), '20454\n')
        self.assertEqual(profile.expected('tree', 0), '0\n')

    def test_snapshots_use_checked_sources_without_the_default_queens_driver(self):
        for name in ['richards', 'deltablue']:
            self.assertEqual(profile.snapshot(name), (ROOT / 'benchmark' / (name + '.hrd')).read_text())
        source = profile.snapshot('queens')
        self.assertTrue(source.startswith('| repetitions solver answer |'))
        self.assertIn('Wrong Queens result', source)
        self.assertIn('repetitions timesRepeat:', source)
        self.assertNotIn('# Benchmark driver', source)

    def test_added_workloads_are_covered_by_the_retained_profile(self):
        for name in ('shapes', 'tree'):
            self.assertIn(name, profile.CASES)
            # No synthesis: the snapshot is the checked benchmark source itself.
            self.assertEqual(profile.snapshot(name), (ROOT / 'benchmark' / (name + '.hrd')).read_text())

    def test_expected_values_match_the_interpreter(self):
        # Read the answer from the interpreter rather than trusting a constant.
        import subprocess
        for name, per_pass in (('shapes', 178000), ('tree', 10227)):
            done = subprocess.run([str(ROOT / 'harding'), str(ROOT / 'benchmark' / (name + '.hrd'))],
                                  cwd=ROOT, capture_output=True, text=True, timeout=300)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertEqual(done.stdout.strip(), str(per_pass), name)


if __name__ == '__main__':
    unittest.main()
