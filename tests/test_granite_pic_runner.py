"""PIC experiments use checked results and preserve the requested receiver set."""
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import bench_granite_pic as runner


class PicRunner(unittest.TestCase):
    def test_sources_cover_width_and_skew_without_changing_cost_bodies(self):
        for width in range(1, 7):
            for skew in [False, True]:
                with self.subTest(width=width, skew=skew):
                    code, answer = runner.source(width, skew)
                    self.assertEqual(code.count('>>cost ['), width)
                    self.assertEqual(answer, width * (width + 1) // 2 + (9 if skew else 0))
                    self.assertIn('(collection at: index) cost', code)
                    self.assertEqual(code.count('PicShape0 new'), 10 if skew else 1)

    def test_wrong_output_stderr_and_nonzero_exit_are_rejected(self):
        cpu = min(os.sched_getaffinity(0))
        for status, output, error in [(0, '999\n', ''), (0, '42\n', 'warning'), (1, '42\n', '')]:
            with self.subTest(status=status, output=output, error=error):
                done = subprocess.CompletedProcess([], status, output, error)
                with patch.object(runner.subprocess, 'run', return_value=done), self.assertRaises(RuntimeError):
                    runner.timed(Path('binary'), 2, 21, cpu)
        done = subprocess.CompletedProcess([], 0, '42\n', '')
        with patch.object(runner.subprocess, 'run', return_value=done):
            self.assertGreater(runner.timed(Path('binary'), 2, 21, cpu), 0)


if __name__ == '__main__':
    unittest.main()
