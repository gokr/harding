"""Class-method call-site specialization must observe overrides and replacement.

A class-side native entry is only used when the call site can prove the receiver
is that exact class object and the registered class method is still the one baked
into the guard. Anything else must fall back to the ordinary send.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''Bits := Object derive: #().
Bits class>>xor16: left with: right [
    | a b place value abit bbit |
    a := left. b := right. place := 1. value := 0.
    [place < 65536] whileTrue: [
        abit := a - ((a // 2) * 2).
        bbit := b - ((b // 2) * 2).
        abit <> bbit ifTrue: [value := value + place].
        a := a // 2. b := b // 2. place := place * 2
    ].
    ^value
].
Bits class>>plain: n [ ^n + 1 ].
User := Object derivePublic: #{#control -> Integer}.
User>>spin: n [ | i | i := 0.
[i < n] whileTrue: [control := Bits xor16: (control // 2) with: 53256. i := i + 1]. ^control ].
User>>plainUse: n [ ^Bits plain: n ].
'''


class ClassSiteRegions(unittest.TestCase):
    def checked(self, command):
        p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=240)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return p

    def test_class_site_guard(self):
        base = ROOT / 'build/class-site-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'site.hrd'
            source.write_text(SOURCE)
            self.checked([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work)])
            code = (work / 'site.nim').read_text()

            native = 'integerClassCall_Class_42697473_hardingUser786F7231363A776974683A_native'
            self.assertIn('proc ' + native + '*(left, right: int): int', code)
            start = code.index('proc ' + native + '*(left')
            end = code.index('\nproc ', start)
            body = code[start:end]
            # Pure int arithmetic: no NodeValue, no argument sequences.
            self.assertNotIn('NodeValue', body)
            self.assertNotIn('@[', body)
            # Integer division keeps Harding's error, not a Nim Defect.
            self.assertIn('compiledIntegerDiv(', body)
            # The guard covers the class object and the registration.
            self.assertIn('guardStatic_Class_42697473_hardingUser786F7231363A776974683A()', code)
            self.assertIn('resolveCompiledClassMethod("Bits", "xor16:with:")', code)
            # A non-Integer argument (a dynamic slot) must not specialize.
            self.assertNotIn('plain: n [ ^n + 1 ]', code)

            imports = '\n'.join('import "' + str(ROOT / p) + '"' for p in
                                ['src/harding/core/types', 'src/harding/runtime/runtime',
                                 'src/harding/runtime/compiled_support'])
            host = work / 'host.nim'
            host.write_text('import std/tables\n' + imports + '\nimport ./site\n' + '''
registerCompiledMethods()
registerSuperclassHierarchy()
proc spin(n: int): int =
  sendMessage(nil, newClass_55736572().toValue(), "spin:", @[toValue(n)]).intVal
# Native path agrees with the reference value and handles the zero case.
doAssert spin(0) == 0
doAssert spin(3) == 35854
# Replacing the class method must be observed through the guard.
proc replaced(self: NodeValue, args: seq[NodeValue]): NodeValue = toValue(7)
registerCompiledClassMethod("Bits", "xor16:with:", replaced)
doAssert spin(3) == 7
''')
            for mm in ('arc', 'orc'):
                with self.subTest(mm=mm):
                    binary = work / ('host_' + mm)
                    self.checked(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('cache_' + mm)),
                                  '-o:' + str(binary), str(host)])
                    self.checked([str(binary)])


if __name__ == '__main__':
    unittest.main()
