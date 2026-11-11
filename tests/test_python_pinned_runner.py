"""The pinned runner must reject errors instead of reporting a timing."""
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from bench_compare_python_pinned import timed
from python_benchmark_source import driver
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


class PythonPorts(unittest.TestCase):
    def test_added_workloads_translate_and_agree_with_the_interpreter(self):
        # The comparison is only meaningful if the Python port answers exactly what
        # the Harding source answers, so check both rather than trusting the port.
        import subprocess
        for case, per_pass in (('shapes', 178000), ('tree', 10227)):
            source = (ROOT / 'benchmark' / (case + '.hrd')).read_text()
            for count in (1, 2):
                with self.subTest(case=case, count=count):
                    done = subprocess.run([sys.executable, '-c', driver(case, count, source)],
                                          capture_output=True, text=True, timeout=300)
                    self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                    self.assertEqual(done.stdout.strip(), str(count))
                    harding = subprocess.run(
                        [str(ROOT / 'harding'), str(ROOT / 'benchmark' / (case + '.hrd')), '--', str(count)],
                        cwd=ROOT, capture_output=True, text=True, timeout=300)
                    self.assertEqual(harding.returncode, 0, harding.stdout + harding.stderr)
                    self.assertEqual(harding.stdout.strip(), str(per_pass * count), case)


class NativePorts(unittest.TestCase):
    def test_native_references_agree_with_the_interpreter(self):
        # The native port is the performance floor, so it must compute the same
        # thing as the Harding source; otherwise the ratio is meaningless.
        import subprocess
        binary_root = ROOT / 'build/native-port-tests'
        binary_root.mkdir(parents=True, exist_ok=True)
        for case, per_pass in (('shapes', 178000), ('tree', 10227)):
            with self.subTest(case=case):
                binary = binary_root / case
                subprocess.run(['nim', 'c', '-d:release', '--hints:off',
                                '--nimcache:' + str(binary_root / ('cache-' + case)),
                                '-o:' + str(binary),
                                str(ROOT / 'benchmark' / 'native' / (case + '.nim'))],
                               check=True, capture_output=True, text=True, timeout=600)
                for count in (0, 1, 2):
                    got = subprocess.run([str(binary), str(count)], capture_output=True,
                                         text=True, timeout=300)
                    self.assertEqual(got.returncode, 0, got.stdout + got.stderr)
                    self.assertEqual(got.stdout.strip(), str(per_pass * count), case)
                    harding = subprocess.run(
                        [str(ROOT / 'harding'), str(ROOT / 'benchmark' / (case + '.hrd')), '--', str(count)],
                        cwd=ROOT, capture_output=True, text=True, timeout=300)
                    self.assertEqual(harding.returncode, 0, harding.stdout + harding.stderr)
                    self.assertEqual(harding.stdout.strip(), got.stdout.strip(), case)


if __name__ == '__main__':
    unittest.main()
