"""Executed comparison ports, not just source generation smoke tests."""
import contextlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import python_benchmark_source as pyport
import gst_benchmark_source as gstport
from bench_compare_practical import native_source


class PracticalBenchmarkPorts(unittest.TestCase):
    def setUp(self):
        base = ROOT / 'build/practical-benchmark-tests'
        base.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=base)
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def source(self, case):
        return (ROOT / 'benchmark' / (case + '.hrd')).read_text()

    def run_checked(self, command, expected):
        result = subprocess.run(command, cwd=self.work, capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, expected)
        self.assertEqual(result.stderr, '')

    def test_python_ports_zero_one_and_repeated_verified_passes(self):
        for case in ('richards', 'deltablue', 'queens'):
            for count in (0, 1, 3):
                with self.subTest(case=case, count=count):
                    path = self.work / (case + '.py')
                    path.write_text(pyport.driver(case, count, self.source(case)))
                    self.run_checked([sys.executable, str(path)], str(count) + '\n')

    def test_python_reports_reference_results_and_retains_cleanup(self):
        namespaces = {}
        for case in ('richards', 'deltablue', 'queens'):
            namespace = {}
            with contextlib.redirect_stdout(io.StringIO()):
                exec(pyport.driver(case, 1, self.source(case)), namespace)
            namespaces[case] = namespace
        scheduler = namespaces['richards']['answer']
        self.assertEqual((scheduler.get_queueCount(), scheduler.get_holdCount()), (2322, 928))
        self.assertIsNone(scheduler._slot_blocks)
        self.assertIsNone(scheduler._slot_list)
        self.assertEqual(namespaces['queens']['answer'], 92)
        self.assertAlmostEqual(namespaces['deltablue']['answer'], 223305)
        self.assertIn('finally:', pyport.driver('deltablue', 0, self.source('deltablue')))

    def test_python_verification_rejects_wrong_results(self):
        for case, old, new in [('richards', '== (2322, 928)', '== (0, 0)'),
                               ('queens', 'assert answer == 92', 'assert answer == 0'),
                               ('deltablue', 'answer - 223305', 'answer - 1')]:
            program = pyport.driver(case, 1, self.source(case))
            self.assertIn(old, program)
            with self.subTest(case=case), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(AssertionError):
                    exec(program.replace(old, new), {})

    def test_adapter_preserves_control_flow_precedence_and_arithmetic_helpers(self):
        richards = pyport.driver('richards', 0, self.source('richards'))
        self.assertIn('def xor16_with_', richards)
        self.assertIn('// 2', richards)
        self.assertNotIn('getattr', richards)
        self.assertNotIn('eval(', richards)
        delta = pyport.driver('deltablue', 0, self.source('deltablue'))
        self.assertIn('.pop(', delta)
        self.assertIn('finally:', delta)
        # Smalltalk binary operators share precedence, unlike Python.
        node = pyport.Parser('2 + 3 * 4').expr()
        self.assertEqual(eval(pyport.Generator([], []).expr(node)), 20)

    def test_invalid_and_unsupported_input_fails_instead_of_hanging(self):
        for source in ('P := Object derive: #(x', 'P := Object derive: #(). P>>m [| unterminated',
                       'P := Object derive: #(). P>>m [x := @].'):
            with self.subTest(source=source), self.assertRaises(ValueError):
                pyport.definitions(source)
        for adapter in (pyport, gstport):
            with self.assertRaises(ValueError): adapter.driver('queens', -1, self.source('queens'))

    def test_generated_ports_keep_notices_and_matching_workload_checks(self):
        for adapter in (pyport, gstport):
            for case in ('richards', 'deltablue'):
                program = adapter.driver(case, 1, self.source(case))
                self.assertIn('V8 project authors', program)
                self.assertIn('GPL-2.0' if case == 'deltablue' else 'BSD-3-Clause', program)
                self.assertIn('223305' if case == 'deltablue' else '2322', program)

    def test_gst_ports_zero_one_and_repeated_verified_passes(self):
        configured = os.environ.get('BENCHMARK_GST')
        gst = Path(configured) if configured else ROOT / 'build/gnu-smalltalk/install/bin/gst'
        if not gst.is_file():
            if configured: self.fail('BENCHMARK_GST does not exist: ' + configured)
            self.skipTest('optional GNU Smalltalk not built; run scripts/setup_benchmark_gst.py')
        for case in ('richards', 'deltablue', 'queens'):
            for count in (0, 1, 3):
                with self.subTest(case=case, count=count):
                    path = self.work / (case + '.st')
                    path.write_text(gstport.driver(case, count, self.source(case)))
                    # GST may report errors on stdout yet return 0. Exact output
                    # comparison is essential; a zero status alone is not success.
                    self.run_checked([str(gst), '--no-user-files', '-q', str(path)], str(count) + '\n')

    def test_gst_verification_failure_is_not_a_successful_timing(self):
        from bench_compare import execute
        configured = os.environ.get('BENCHMARK_GST')
        gst = Path(configured) if configured else ROOT / 'build/gnu-smalltalk/install/bin/gst'
        if not gst.is_file():
            if configured: self.fail('BENCHMARK_GST does not exist: ' + configured)
            self.skipTest('optional GNU Smalltalk not built')
        path = self.work / 'wrong.st'
        program = gstport.driver('queens', 1, self.source('queens'))
        path.write_text(program.replace('answer = 92', 'answer = 0'))
        with self.assertRaises(RuntimeError):
            execute([str(gst), '--no-user-files', '-q', str(path)],
                    self.work, 'wrong-gst', 30, expected=1)

    def test_gst_bootstrap_and_indexing_are_explicit(self):
        program = gstport.driver('deltablue', 0, self.source('deltablue'))
        self.assertIn('HBObject class compile:', program)
        self.assertIn('^super new initialize', program)
        self.assertIn('storage at: index + 1', program)
        self.assertIn('storage removeAtIndex: index + 1', program)
        self.assertLess(program.index('Smalltalk at: #DBWeakest put: nil'),
                        program.index('DBStrength compile:'))

    def test_native_nim_references_arc_and_orc(self):
        if not shutil.which('nim'): self.skipTest('Nim unavailable')
        for mm in ('arc', 'orc'):
            for case in ('richards', 'deltablue', 'queens'):
                with self.subTest(case=case, mm=mm):
                    source = self.work / (case + '.nim')
                    source.write_text(native_source(case))
                    binary = self.work / (case + '_' + mm)
                    build = subprocess.run(['nim', 'c', '-d:release', '-d:' + case, '--mm:' + mm,
                        '--nimcache:' + str(self.work / ('cache_' + case + '_' + mm)),
                        '-o:' + str(binary), str(source)],
                        cwd=ROOT, capture_output=True, text=True, timeout=180)
                    self.assertEqual(build.returncode, 0, build.stderr)
                    self.assertNotIn('Warning:', build.stderr)
                    for count in (0, 1, 3):
                        expected = (f'Richards queued={2322*count} held={928*count}\n' if case == 'richards'
                                    else (f'DeltaBlue runs={count} verified\n' if case == 'deltablue'
                                          else ('92\n' if count else '0\n')))
                        self.run_checked([str(binary), str(count)], expected)
                    rejected = subprocess.run([str(binary), '-1'], cwd=self.work,
                                              capture_output=True, text=True, timeout=10)
                    self.assertNotEqual(rejected.returncode, 0)


if __name__ == '__main__':
    unittest.main()
