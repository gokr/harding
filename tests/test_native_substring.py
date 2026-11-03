"""Native String from:to: follows VM byte-slice semantics and ordinary dispatch."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/awfy-json'
GRANITE = BUILD / 'private-granite'

CASES = '''
SubstringChecks := Object derive.
SubstringChecks class>>assert: condition [ condition ifFalse: [ self error: "substring mismatch" ] ]
SubstringChecks class>>run [
    self assert: ((#abcdef from: 0 to: 1) = "ab").
    self assert: (("abcdef" from: 0 to: 1) = "ab").
    self assert: (("abcdef" from: 2 to: 2) = "c").
    self assert: (("abcdef" from: 0 to: 5) = "abcdef").
    self assert: (("abcdef" from: 5 to: 5) = "f").
    self assert: (("abc" from: -1 to: 1) = "").
    self assert: (("abc" from: 0 to: -1) = "").
    self assert: (("abc" from: 2 to: 1) = "").
    self assert: (("abc" from: 0 to: 3) = "").
    self assert: (("abc" from: 3 to: 3) = "").
    self assert: (("" from: 0 to: 0) = "").
    self assert: (("abc" from: "0" to: 1) = "").
    self assert: (("abc" from: 0 to: 1.0) = "").
    self assert: (("abc" from: nil to: 1) = "").
    self assert: (("abc" from: true to: 1) = "").
    self assert: (("abc" perform: #"from:to:") = "").
    self assert: (("abc" perform: #"from:to:" with: 0) = "").
    self assert: (("abc" perform: #"from:to:" with: 0 with: 1) = "ab").
    self assert: (("é" from: 0 to: 0) size = 1).
    self assert: ((("é" from: 0 to: 0) & ("é" from: 1 to: 1)) = "é").
    "substring passed" println.
]
SubstringChecks run.
'''
OVERRIDE = '''
SubstringOverride := Object derive.
SubstringOverride>>from: start to: finish [ ^ "override" ]
((SubstringOverride new from: 0 to: 1) = "override") ifFalse: [ Object error: "override lost" ].
((SubstringOverride new perform: #"from:to:" with: 0 with: 1) = "override") ifFalse: [ Object error: "dynamic override lost" ].
"substring passed" println.
'''


class NativeSubstringTest(unittest.TestCase):
    def checked(self, command):
        run = subprocess.run([str(x) for x in command], cwd=ROOT,
                             capture_output=True, text=True, timeout=240)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        return run.stdout

    def test_substring(self):
        BUILD.mkdir(parents=True, exist_ok=True)
        self.checked(['nim', 'c', '-p:external',
            '--nimcache:' + str(BUILD / 'compiler-cache'), '-o:' + str(GRANITE),
            ROOT / 'src/harding/compiler/granite.nim'])
        for mm in ('arc', 'orc'):
            interpreter = BUILD / ('harding-' + mm)
            self.checked(['nim', 'c', '--mm:' + mm, '-d:release', '-p:external',
                '--nimcache:' + str(BUILD / ('interpreter-cache-' + mm)),
                '-o:' + str(interpreter), ROOT / 'src/harding/repl/harding.nim'])
            for name, source in [('substring', CASES), ('override', OVERRIDE)]:
                with self.subTest(mm=mm, case=name):
                    program = BUILD / (name + '.hrd')
                    program.write_text(source)
                    self.assertEqual(self.checked([interpreter, program]), 'substring passed\n')
                    directory = BUILD / ('substring-' + mm)
                    directory.mkdir(exist_ok=True)
                    self.checked([GRANITE, 'compile', program, '--dir:' + str(directory), '-o:' + name])
                    native = directory / name
                    self.checked(['nim', 'c', '--mm:' + mm, '-d:release',
                        '--nimcache:' + str(BUILD / ('substring-cache-' + mm)),
                        '-o:' + str(native), directory / (name + '.nim')])
                    self.assertEqual(self.checked([native]), 'substring passed\n')


if __name__ == '__main__':
    unittest.main()
