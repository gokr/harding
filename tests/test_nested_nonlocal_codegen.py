"""Lexical return targets survive slot storage, nested blocks and callbacks."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/nested-nonlocal'
SOURCE = '''
ReturnProbe := Object derive: #(callback, cleanups).
ReturnProbe>>invoke: block [ ^ block value: 42 ]
ReturnProbe>>nested [
    callback := [:value | #(1, 2) do: [:each | [ ^ value + each ] value ]].
    self invoke: callback.
    ^ 0
]
ReturnProbe>>clean [
    cleanups := 0.
    callback := [:value | ^ value].
    [ self invoke: callback ] ensure: [ cleanups := cleanups + 1 ].
    ^ 0
]
ReturnProbe>>cleanupCount [ ^ cleanups ]
ReturnProbe>>dead [ ^ [ ^ 7 ] ]
ReturnProbe>>recursive: depth [
    | saved |
    saved := [:value | ^ value + depth].
    depth > 0 ifTrue: [ self recursive: depth - 1 ].
    self invoke: saved.
    ^ 0
]
ReturnChecks := Object derive.
ReturnChecks class>>assert: flag [ flag ifFalse: [ self error: "return mismatch" ] ]
ReturnChecks class>>run [
    | probe escaped |
    probe := ReturnProbe new.
    self assert: (probe nested = 43).
    self assert: (probe clean = 42).
    self assert: (probe cleanupCount = 1).
    self assert: ((probe recursive: 3) = 45).
    escaped := probe dead.
    self assert: ([ escaped value. false ] on: Error do: [:error | true]).
    "nonlocal passed" println.
]
ReturnChecks run.
'''


class NestedNonlocalTest(unittest.TestCase):
    def checked(self, command):
        run = subprocess.run([str(x) for x in command], cwd=ROOT,
                             capture_output=True, text=True, timeout=240)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        return run.stdout

    def test_activation_returns(self):
        BUILD.mkdir(parents=True, exist_ok=True)
        compiler = BUILD / 'private-granite'
        self.checked(['nim', 'c', '-p:external', '--nimcache:' + str(BUILD / 'compiler-cache'),
                      '-o:' + str(compiler), ROOT / 'src/harding/compiler/granite.nim'])
        source = BUILD / 'nested.hrd'
        source.write_text(SOURCE)
        for mm in ('arc', 'orc'):
            with self.subTest(mm=mm):
                interpreter = BUILD / ('harding-' + mm)
                self.checked(['nim', 'c', '--mm:' + mm, '-d:release', '-p:external',
                    '--nimcache:' + str(BUILD / ('interpreter-cache-' + mm)),
                    '-o:' + str(interpreter), ROOT / 'src/harding/repl/harding.nim'])
                for name, program, expected in [
                    ('nested', source, 'nonlocal passed\n'),
                    ('minimal', ROOT / 'benchmark/awfy/json/blocker_nonlocal.hrd', 'expected\n')]:
                    self.assertEqual(self.checked([interpreter, program]), expected)
                    directory = BUILD / mm
                    directory.mkdir(exist_ok=True)
                    self.checked([compiler, 'compile', program, '--dir:' + str(directory), '-o:' + name])
                    native = directory / name
                    self.checked(['nim', 'c', '--mm:' + mm, '-d:release',
                        '--nimcache:' + str(BUILD / ('native-cache-' + mm)),
                        '-o:' + str(native), directory / (name + '.nim')])
                    self.assertEqual(self.checked([native]), expected)


if __name__ == '__main__':
    unittest.main()
