"""The pinned runner must reject errors instead of reporting a timing."""
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from bench_compare_python_pinned import timed
from bench_compare_native_nim import timed as native_timed


class PinnedRunner(unittest.TestCase):
    def test_checked_execution(self):
        cpu = min(os.sched_getaffinity(0))
        self.assertGreater(timed([sys.executable, '-c', 'print(92)'], '92\n', cpu), 0)
        for program in ['print(91)', 'raise SystemExit(1)',
                        'import sys; print(92); print("warning", file=sys.stderr)']:
            with self.subTest(program=program), self.assertRaises(RuntimeError):
                timed([sys.executable, '-c', program], '92\n', cpu)


    def test_native_reference_rejects_stderr_and_errors(self):
        cpu = min(os.sched_getaffinity(0))
        elapsed, output = native_timed([sys.executable, '-c', 'print(92)'], cpu)
        self.assertGreater(elapsed, 0)
        self.assertEqual(output, '92\n')
        for program in ['raise SystemExit(1)', 'import sys; print("warning", file=sys.stderr)']:
            with self.subTest(program=program), self.assertRaises(RuntimeError):
                native_timed([sys.executable, '-c', program], cpu)


if __name__ == '__main__':
    unittest.main()
