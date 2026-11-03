"""Focused generic Integer iteration parity; no large Havlak workload."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/integer-iteration'

SOURCE = r'''
IterationProbe := Object derive: #().
IterationProbe>>visit: start stop: stop step: step [
    | block total answer |
    total := 0.
    block := [:i | total := (total * 10) + i. 999].
    answer := start to: stop by: step do: block.
    answer println.
    ^ total
].
IterationProbe>>early [
    | block |
    block := [:i | i = 2 ifTrue: [ ^ 42 ]].
    4 to: 0 by: (0 - 1) do: block.
    ^ 0
].
IterationProbe>>zero [
    | block count |
    count := 0.
    block := [:i | count := count + 1. count = 3 ifTrue: [ ^ i ]].
    3 to: 1 by: 0 do: block.
    ^ 99
].
IterationProbe>>failure [
    | block count answer |
    count := 0.
    block := [:i | count := count + 1. Error signal: "iteration callback"].
    answer := [ 1 to: 3 by: 1 do: block ] on: Error do: [:ex | 77].
    answer println.
    ^ count
].
p := IterationProbe new.
(p visit: 1 stop: 5 step: 2) println.
(p visit: 5 stop: 1 step: (0 - 2)) println.
(p visit: 1 stop: 4 step: 2) println.
(p visit: 2 stop: 2 step: 3) println.
(p visit: 3 stop: 1 step: 1) println.
(p visit: 1 stop: 3 step: (0 - 1)) println.
(p visit: 1 stop: 3 step: 0) println.
p early println.
p zero println.
p failure println.
'''
EXPECTED = '1\n135\n5\n531\n1\n13\n2\n2\n3\n0\n1\n0\n1\n0\n42\n3\n77\n1\n'


class NativeIntegerIterationTest(unittest.TestCase):
    @staticmethod
    def build(label, command):
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240)
        (WORK / (label + '.log')).write_text(run.stdout + run.stderr)
        if run.returncode:
            raise AssertionError(label + ': ' + run.stdout + run.stderr)

    def test_interpreter_native_arc_orc(self):
        WORK.mkdir(parents=True, exist_ok=True)
        source = WORK / 'iteration.hrd'
        source.write_text(SOURCE)
        compiler = WORK / 'granite'
        self.build('compiler', ['nim', 'c', '-p:external',
            '--nimcache:' + str(WORK / 'compiler-cache'), '-o:' + str(compiler),
            'src/harding/compiler/granite.nim'])
        cases = [('iteration', source, EXPECTED),
                 ('havlak_repro', ROOT / 'benchmark/awfy/havlak/blocked_integer_iteration.hrd',
                  '3\n2\n1\n'),
                 ('empty_range', ROOT / 'benchmark/awfy/havlak/blocked_empty_range.hrd',
                  'ok\n'),
                 ('reduced_union', ROOT / 'benchmark/awfy/havlak/reduced_union.hrd',
                  'UnionFindNode\ndirect union passed\nok\n')]
        for mm in ('arc', 'orc'):
            interpreter = WORK / ('harding-' + mm)
            self.build('interpreter-' + mm, ['nim', 'c', '--mm:' + mm, '-p:external',
                '--nimcache:' + str(WORK / ('interpreter-cache-' + mm)),
                '-o:' + str(interpreter), 'src/harding/repl/harding.nim'])
            for name, path, expected in cases:
                directory = WORK / name
                directory.mkdir(exist_ok=True)
                self.build(name + '-generate', [str(compiler), 'compile', str(path),
                    '--dir:' + str(directory), '-o:' + name])
                binary = directory / (name + '-' + mm)
                self.build(name + '-' + mm, ['nim', 'c', '--mm:' + mm,
                    '--nimcache:' + str(directory / ('cache-' + mm)),
                    '-o:' + str(binary), str(directory / (name + '.nim'))])
                for command in ([str(interpreter), str(path)], [str(binary)]):
                    with self.subTest(mm=mm, case=name, command=command):
                        run = subprocess.run(command, cwd=ROOT, capture_output=True,
                                             text=True, timeout=30)
                        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                        self.assertEqual(run.stderr, '')
                        self.assertEqual(run.stdout, expected)


if __name__ == '__main__':
    unittest.main()
