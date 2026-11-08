"""The pinned runner must reject errors instead of reporting a timing."""
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from bench_compare_python_pinned import timed


class PinnedRunner(unittest.TestCase):
    def test_checked_execution(self):
        cpu = min(os.sched_getaffinity(0))
        self.assertGreater(timed([sys.executable, '-c', 'print(92)'], '92\n', cpu), 0)
        for program in ['print(91)', 'raise SystemExit(1)',
                        'import sys; print(92); print("warning", file=sys.stderr)']:
            with self.subTest(program=program), self.assertRaises(RuntimeError):
                timed([sys.executable, '-c', program], '92\n', cpu)


if __name__ == '__main__':
    unittest.main()
