"""Execute the real DeltaBlue source and shared conformance checks in both engines."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeltaBlueTest(unittest.TestCase):
    def run_checked(self, command, expected, cwd=ROOT):
        run = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=180)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(run.stderr, '')
        self.assertEqual(run.stdout, expected)

    def build_checked(self, command):
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_reference_workloads_plans_removal_and_repeated_runs(self):
        base = ROOT / 'build/deltablue-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            source = ROOT / 'benchmark/deltablue.hrd'
            conformance = work / 'conformance.hrd'
            conformance.write_text(source.read_text() + '\n' +
                                   (ROOT / 'tests/deltablue_checks.hrd').read_text())
            for mm in ('arc', 'orc'):
                with self.subTest(mm=mm):
                    interpreter = work / ('harding_' + mm)
                    self.build_checked(['nim', 'c', '--mm:' + mm, '-d:release',
                        '--nimcache:' + str(work / ('interp-cache-' + mm)),
                        '-p:external', '-o:' + str(interpreter), 'src/harding/repl/harding.nim'])
                    directory = work / mm
                    directory.mkdir()
                    generated = directory / 'deltablue.nim'
                    self.build_checked([str(ROOT / 'granite'), 'compile', str(conformance),
                                        '--dir:' + str(directory), '-o:deltablue'])
                    native = directory / 'deltablue'
                    self.build_checked(['nim', 'c', '--mm:' + mm, '-d:release',
                        '--nimcache:' + str(work / ('native-cache-' + mm)),
                        '-o:' + str(native), str(generated)])
                    expected = 'DeltaBlue runs=0 verified\nDeltaBlue conformance passed\n'
                    self.run_checked([str(interpreter), str(conformance), '--', '0'], expected)
                    self.run_checked([str(native), '0'], expected)
                    # Compile the unmodified benchmark separately: the test fixture is not the driver.
                    self.build_checked([str(ROOT / 'granite'), 'compile', str(source),
                                        '--dir:' + str(directory), '-o:driver'])
                    driver = directory / 'driver'
                    self.build_checked(['nim', 'c', '--mm:' + mm, '-d:release',
                        '--nimcache:' + str(work / ('driver-cache-' + mm)),
                        '-o:' + str(driver), str(directory / 'driver.nim')])
                    self.run_checked([str(interpreter), str(source)],
                                     'DeltaBlue runs=1 verified\n')
                    self.run_checked([str(driver)], 'DeltaBlue runs=1 verified\n', cwd=work)
                    for count in (0, 1, 3):
                        expected = f'DeltaBlue runs={count} verified\n'
                        self.run_checked([str(interpreter), str(source), '--', str(count)], expected)
                        self.run_checked([str(driver), str(count)], expected, cwd=work)
                    for invalid in ('-1', 'invalid'):
                        for command in ([str(interpreter), str(source), '--', invalid],
                                        [str(driver), invalid]):
                            rejected = subprocess.run(command, cwd=ROOT, capture_output=True,
                                                      text=True, timeout=30)
                            self.assertNotEqual(rejected.returncode, 0)
                            self.assertIn('Expected a nonnegative repetition count',
                                          rejected.stdout + rejected.stderr)


if __name__ == '__main__':
    unittest.main()
