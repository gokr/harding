"""Focused SOM Havlak parity; AWFY_HAVLAK_FULL=1 enables expensive upstream cases."""
from pathlib import Path
import os
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
PORT = ROOT / 'benchmark/awfy/havlak'
BUILD = ROOT / 'build/awfy-havlak'


def assemble():
    BUILD.mkdir(parents=True, exist_ok=True)
    driver = (PORT / 'driver.hrd').read_text()
    start = driver.index('|')
    end = driver.index('|', start + 1) + 1
    source = BUILD / 'run.hrd'
    source.write_text(driver[start:end] + '\n' + (PORT / 'havlak.hrd').read_text()
                      + '\n' + (PORT / 'checks.hrd').read_text() + '\n' + driver[end:])
    return source


class HavlakTest(unittest.TestCase):
    def checked(self, command, timeout=300):
        run = subprocess.run(list(map(str, command)), cwd=ROOT, text=True,
                             capture_output=True, timeout=timeout)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        return run

    def test_parity(self):
        source = assemble()
        granite = BUILD / 'granite'
        self.checked(['nim', 'c', '-d:release', '-p:external',
                      '--nimcache:' + str(BUILD / 'compiler-cache'),
                      '-o:' + str(granite), ROOT / 'src/harding/compiler/granite.nim'])
        generated = BUILD / 'generated'
        generated.mkdir(exist_ok=True)
        self.checked([granite, 'compile', source, '--dir:' + str(generated), '-o:havlak'])
        cases = [((1, 0, 1, 1, 1), (9, 16)),
                 ((0, 0, 1, 1, 1), (6, 16)),
                 ((15, 1, 1, 1, 1), (51, 16))]
        if os.environ.get('AWFY_HAVLAK_FULL') == '1':
            cases += [((n, 50, 10, 10, 5), (loops, 5213))
                      for n, loops in [(1, 1605), (15, 1647), (150, 2052),
                                       (1500, 6102), (15000, 46602)]]
        for mm in ('arc', 'orc'):
            with self.subTest(mm=mm):
                interpreter = BUILD / ('harding-' + mm)
                native = BUILD / ('havlak-' + mm)
                self.checked(['nim', 'c', '--mm:' + mm, '-d:release', '-p:external',
                              '--nimcache:' + str(BUILD / ('interpreter-cache-' + mm)),
                              '-o:' + str(interpreter), ROOT / 'src/harding/repl/harding.nim'])
                self.checked(['nim', 'c', '--mm:' + mm, '-d:release',
                              '--nimcache:' + str(BUILD / ('native-cache-' + mm)),
                              '-o:' + str(native), generated / 'havlak.nim'])
                for args, (loops, nodes) in cases:
                    expected = f'Havlak conformance passed\nHavlak loops={loops} nodes={nodes}\n'
                    for command in ([interpreter, source, '--', *args], [native, *args]):
                        with self.subTest(command=command):
                            run = self.checked(command, timeout=1800)
                            self.assertEqual(run.stdout, expected)
                            self.assertEqual(run.stderr, '')


if __name__ == '__main__':
    unittest.main()
