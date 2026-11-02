"""Executed Boolean helper parity, including eager and exactly-once effects."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''
Probe := Object derive: #().
Probe>>either: left with: right [ ^left | right ].
Probe>>invert: target [ ^target not ].
Probe>>effects: action [ ^action value | action value ].
Probe>>catchRight: action [ ^[true | action value] on: Error do: [:error | 73] ].
Custom := Object derive: #().
Custom>>| other [ ^other ].
Custom>>not [ ^nil ].
p := Probe new.
Stdout writeline: (p either: false with: false).
Stdout writeline: (p either: false with: true).
Stdout writeline: (p either: true with: false).
Stdout writeline: (p either: true with: true).
Stdout writeline: (p invert: false).
Stdout writeline: (p invert: true).
Stdout writeline: (p either: Custom new with: 17).
Stdout writeline: (p invert: Custom new) isNil.
Calls := 0.
Stdout writeline: (p effects: [Calls := Calls + 1. Calls = 1]).
Stdout writeline: Calls.
Order := "".
Stdout writeline: ([Order := Order & "L". true] value | [Order := Order & "R". false] value).
Stdout writeline: Order.
Stdout writeline: (p catchRight: [Error signal: "rhs executed"]).
'''
EXPECTED = 'false\ntrue\ntrue\ntrue\ntrue\nfalse\n17\ntrue\ntrue\n2\ntrue\nLR\n73\n'


def execute(command):
    p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                       env=dict(os.environ, HARDING_HOME=str(ROOT)), timeout=240)
    if p.returncode:
        raise AssertionError(str(command) + '\n' + p.stdout + p.stderr)
    return p


class BooleanHelpers(unittest.TestCase):
    def test_boolean_helpers_in_both_engines(self):
        base = ROOT / 'build/boolean-helper-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'boolean.hrd'
            source.write_text(SOURCE)
            execute([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work)])
            generated = (work / 'boolean.nim').read_text()
            self.assertIn('nt_pipe(hardingBuiltinReceiver, hardingBuiltinArg0)', generated)
            self.assertIn('nt_not(hardingBuiltinReceiver)', generated)
            self.assertIn('hostedBuiltinDeferred', generated)
            for mm in ('arc', 'orc'):
                with self.subTest(mm=mm):
                    interpreter = work / ('harding_' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('vm_' + mm)),
                             '-o:' + str(interpreter), str(ROOT / 'src/harding/repl/harding.nim')])
                    interpreted = execute([str(interpreter), str(source)])
                    self.assertEqual(interpreted.stdout, EXPECTED)
                    self.assertEqual(interpreted.stderr, '')
                    binary = work / ('native_' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('native_cache_' + mm)),
                             '-o:' + str(binary), str(work / 'boolean.nim')])
                    native = execute([str(binary)])
                    self.assertEqual(native.stdout, EXPECTED)
                    self.assertEqual(native.stderr, '')


if __name__ == '__main__':
    unittest.main()
