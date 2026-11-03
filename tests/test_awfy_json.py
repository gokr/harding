"""AWFY SOM Json parity: recursive Harding parser, never native JSON parsing."""
from pathlib import Path
import os
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'benchmark/awfy/json'
BUILD = ROOT / 'build/awfy-json'


class AwfyJsonTest(unittest.TestCase):
    def checked(self, command, timeout=240):
        run = subprocess.run([str(x) for x in command], cwd=ROOT,
                             capture_output=True, text=True, timeout=timeout)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        return run.stdout

    def test_python_reference(self):
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        run = subprocess.run(['python3', '-c',
            'from json import Json; b=Json(); assert b.verify_result(b.benchmark()); '
            'print("AWFY Python Json checks passed")'], cwd=SOURCE / 'upstream',
            env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_engines(self):
        BUILD.mkdir(parents=True, exist_ok=True)
        program = BUILD / 'checked.hrd'
        program.write_text((SOURCE / 'json.hrd').read_text() + '\n' +
                           (SOURCE / 'checks.hrd').read_text())
        self.checked(['nim', 'c', '-p:external',
            '--nimcache:' + str(BUILD / 'compiler-cache'),
            '-o:' + str(BUILD / 'private-granite'), ROOT / 'src/harding/compiler/granite.nim'])
        for mm in ('arc', 'orc'):
            with self.subTest(mm=mm):
                interpreter = BUILD / ('harding-' + mm)
                self.checked(['nim', 'c', '--mm:' + mm, '-d:release', '-p:external',
                    '--nimcache:' + str(BUILD / ('interpreter-cache-' + mm)),
                    '-o:' + str(interpreter), ROOT / 'src/harding/repl/harding.nim'])
                self.assertEqual(self.checked([interpreter, program]),
                                 'AWFY Json checks passed\n')
                native_dir = BUILD / mm
                native_dir.mkdir(exist_ok=True)
                self.checked([BUILD / 'private-granite', 'compile', program,
                              '--dir:' + str(native_dir), '-o:json'])
                native = native_dir / 'json'
                self.checked(['nim', 'c', '--mm:' + mm, '-d:release',
                    '--nimcache:' + str(BUILD / ('native-cache-' + mm)),
                    '-o:' + str(native), native_dir / 'json.nim'])
                self.assertEqual(self.checked([native]), 'AWFY Json checks passed\n')


if __name__ == '__main__':
    unittest.main()
