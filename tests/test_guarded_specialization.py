"""Guarded specialization must never change an answer, only speed.

The profile is collected from a run that only ever writes Integers. The compiled
program is then executed *without* that restriction, so a Float reaches the
specialized slot and the guard must fall back to the dynamic path. Interpreter and
every build must agree.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

SOURCE = '''
Box := Object derivePublic: #(value).
Box>>initialize [value := 0. ^self].
Box>>addOne [value := value + 1. ^self].
Box>>get [^value].
mode := System arguments at: 0.
b := Box new.
i := 0.
[i < 50] whileTrue: [b addOne. i := i + 1].
Stdout writeline: b get.
"Only the untrained run reaches these kinds."
(mode = "int") ifFalse: [
  b value: 2.5.
  b addOne.
  Stdout writeline: b get.
  b value: "text".
  Stdout writeline: b get
].
'''

EXPECTED = '50\n3.5\ntext\n'
INT_PROFILE_OUTPUT = '50\n'


def run(command, cwd):
    return subprocess.run(command, cwd=cwd, env=dict(os.environ, HARDING_HOME=str(ROOT)),
                          capture_output=True, text=True, timeout=300)


class GuardedSpecialization(unittest.TestCase):
    def test_float_in_an_integer_specialized_slot_falls_back(self):
        base = ROOT / 'build/guarded-specialization'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'guarded.hrd'
            source.write_text(SOURCE)
            for mm in ['arc', 'orc']:
                with self.subTest(mm=mm):
                    interpreter = work / ('harding-' + mm)
                    run(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('vm-' + mm)),
                         '-o:' + str(interpreter), str(ROOT / 'src/harding/repl/harding.nim')], work)
                    expected = run([str(interpreter), str(source)], work)
                    self.assertEqual(expected.returncode, 0, expected.stderr)
                    self.assertEqual(expected.stdout, EXPECTED)
                    self.assertEqual(expected.stderr, '')

                    # Profile only the Integer path by passing the trailing mode.
                    profile = work / ('profile-' + mm + '.json')
                    collect = run([str(interpreter), '--type-feedback', str(profile),
                                   str(source), '--', 'int'], work)
                    self.assertEqual(collect.returncode, 0, collect.stderr)
                    self.assertEqual(collect.stdout, INT_PROFILE_OUTPUT)

                    builds = {}
                    for variant, extra in [('plain', []),
                                           ('specialized', ['--type-feedback:' + str(profile)])]:
                        out = work / (variant + '-' + mm)
                        out.mkdir()
                        generated = run([str(ROOT / 'granite'), 'compile', str(source),
                                         '--dir:' + str(out), '-o:program'] + extra, work)
                        self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
                        binary = out / 'bin'
                        built = run(['nim', 'c', '-d:release', '--mm:' + mm,
                                     '--nimcache:' + str(out / 'cache'), '-o:' + str(binary),
                                     str(out / 'program.nim')], work)
                        self.assertEqual(built.returncode, 0, built.stderr[-800:])
                        builds[variant] = (binary, (out / 'program.nim').read_text())

                    guarded = builds['specialized'][1]
                    self.assertIn('kind == vkInt', guarded, 'no fast path emitted')
                    self.assertIn('nt_plus', guarded, 'fallback path was lost')
                    self.assertNotIn('kind == vkInt', builds['plain'][1],
                                     'specialization must require observations')

                    for variant, (binary, _) in builds.items():
                        result = run([str(binary)], work,
                                     )
                        self.assertEqual(result.returncode, 0, result.stderr[-500:])
                        self.assertEqual(result.stdout, EXPECTED,
                                         f'{variant} diverged from interpreter')
                        self.assertEqual(result.stderr, '')

    def test_module_analysis_alone_does_not_specialize(self):
        base = ROOT / 'build/guarded-specialization'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'static.hrd'
            source.write_text('Quiet := Object derivePublic: #(n).\n'
                              'Quiet>>bump [n := n + 1. ^self].\nQuiet>>get [^n].\n')
            out = work / 'out'
            out.mkdir()
            generated = run([str(ROOT / 'granite'), 'compile', str(source),
                             '--dir:' + str(out), '-o:program'], work)
            self.assertEqual(generated.returncode, 0, generated.stdout)
            self.assertNotIn('kind == vkInt', (out / 'program.nim').read_text())


if __name__ == '__main__':
    unittest.main()
