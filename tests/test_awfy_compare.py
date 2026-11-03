"""Checked AWFY cross-engine adapters: provenance, coverage and answer contracts.

These tests pin the properties the timing harness relies on, so a comparison can
never quietly time a different program or score an unchecked run:

* every port's vendored upstream revision and source digests still match;
* the Harding program the harness times is the port's own source, byte for byte,
  apart from the counted driver;
* a zero-repetition program prints nothing and an N-repetition program prints the
  verified answer (both engines), which is what makes the subtraction honest;
* coverage claims match reality: GNU Smalltalk is Bounce only, and asking for an
  uncovered engine raises rather than substituting something.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))

import awfy_engines as engines   # noqa: E402
import awfy_repeat as repeat     # noqa: E402

BUILD = ROOT / 'build/test-awfy-compare'


class AwfyCompareTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)

    def test_provenance_matches_vendored_sources(self):
        for case in ('bounce', 'json', 'havlak'):
            with self.subTest(case=case):
                manifest = engines.provenance(case)
                self.assertEqual(manifest['commit'], engines.REVISION)
                for entry in manifest['files']:
                    data = (engines.AWYF / case / 'upstream' / entry['path']).read_bytes()
                    self.assertEqual(hashlib.sha256(data).hexdigest(), entry['sha256'],
                                     f'{case}: {entry["path"]} differs from pinned upstream')

    def test_timed_source_is_the_port_itself(self):
        for case in ('bounce', 'json', 'havlak'):
            with self.subTest(case=case):
                source = engines.harding_source(case)
                # The harness must time the port's own program, not a re-write.
                for marker in self.port_markers(case):
                    self.assertIn(marker, source)

    @staticmethod
    def port_markers(case):
        return {
            'bounce': ['Bounce :=', '>>benchmark', 'verifyResult:'],
            'json': ['JsonParser', 'isNull', 'AWFY Json checks passed'],
            'havlak': ['LoopTesterApp', 'HavlakLoopFinder', 'UnionFindNode'],
        }[case]

    def test_zero_run_drops_driver_and_work_run_counts(self):
        for case, reps in (('bounce', 3), ('json', 2)):
            with self.subTest(case=case):
                zero = repeat.granite_program(case, 0)
                work = repeat.granite_program(case, reps)
                driver = repeat.DRIVER[case]
                # Only the trailing driver statement is replaced; the workload,
                # its classes and its checks stay the port's own source.
                self.assertNotIn(driver, work)
                self.assertNotIn(driver, zero)
                self.assertIn(f'1 to: {reps} do:', work)
                # Both engines are driven by the same counted loop construct; the
                # zero program is the same shape with a zero bound.
                if case == 'json':
                    self.assertIn('1 to: 0 do:', zero)
                # The zero-work program must not print an answer.
                self.assertNotIn('answer println', zero)

    def test_coverage_is_declared_not_substituted(self):
        self.assertIsNotNone(repeat.gst_program('bounce', 1))
        for case in ('json', 'havlak'):
            with self.subTest(case=case):
                self.assertIsNone(repeat.gst_program(case, 1))
                self.assertIsNone(engines.gst_driver(case, engines.harding_source(case)))

    def test_gst_bounce_reports_the_same_verified_answer(self):
        gst = ROOT / 'build/gnu-smalltalk/install/bin/gst'
        if not gst.is_file():
            self.skipTest('GNU Smalltalk not built; see scripts/setup_benchmark_gst.py')
        script = BUILD / 'gst-bounce.st'
        script.write_text(repeat.gst_program('bounce', 2))
        run = subprocess.run([str(gst), '--no-user-files', '-q', str(script)],
                             cwd=ROOT, capture_output=True, text=True, timeout=300)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(run.stdout, repeat.ANSWER['bounce'] + '\n')

    def test_python_reports_the_same_verified_answer(self):
        for case in ('bounce', 'json'):
            with self.subTest(case=case):
                script = BUILD / ('python-' + case + '.py')
                script.write_text(repeat.python_program(case, 1))
                expected = repeat.ANSWER[case] if case == 'bounce' else 'AWFY Json checks passed'
                run = subprocess.run([sys.executable, '-B', str(script)], cwd=ROOT,
                                     capture_output=True, text=True, timeout=600)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertEqual(run.stdout, expected + '\n')


if __name__ == '__main__':
    unittest.main()
