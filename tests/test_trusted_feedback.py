"""Observed contracts are opt-in and reject mismatches, not unchecked casts."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''Box := Object derivePublic: #(value, nullable, mixed).
Box>>put: argument [ value := argument. ^self ].
Box>>prepare [ nullable := nil. nullable := 3. mixed := 1. mixed := 2.5. ^self ].
Child := Box derive: #().
b := Box new.
b prepare.
b put: 7.
Stdout writeline: b value.
'''


def run(args):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True,
                          env=dict(os.environ, HARDING_HOME=str(ROOT)), timeout=240)


class TrustedFeedback(unittest.TestCase):
    def checked(self, args):
        p = run(args)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return p

    def test_profile_to_storage_and_checked_setters(self):
        base = ROOT / 'build/trusted-feedback-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'program.hrd'
            source.write_text(SOURCE)
            profile = work / 'feedback.json'
            self.checked([str(ROOT / 'harding'), '--type-feedback', str(profile), str(source)])
            args = [str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work),
                    '--type-feedback:' + str(profile)]
            self.checked(args)
            conservative = (work / 'program.nim').read_text()
            self.assertIn('value*: NodeValue', conservative)
            missing = run(args[:-1] + ['--trust-observed-types'])
            self.assertNotEqual(missing.returncode, 0)
            mixed = run(args + ['--mixed', '--trust-observed-types'])
            self.assertNotEqual(mixed.returncode, 0)
            report = work / 'report.json'
            self.checked(args + ['--trust-observed-types', '--inference-report:' + str(report)])
            generated = (work / 'program.nim').read_text()
            self.assertIn('value*: int', generated)
            self.assertIn('nullable*: NodeValue', generated)
            self.assertIn('mixed*: NodeValue', generated)
            self.assertTrue(json.loads(report.read_text())['slots']['Box#value']['storageNarrowed'])
            host = work / 'host.nim'
            host.write_text('import "' + str(ROOT / 'src/harding/runtime/runtime') + '"\n' +
                            'import "' + str(ROOT / 'src/harding/core/types') + '"\nimport ./program\n' + '''
registerCompiledMethods()
registerSuperclassHierarchy()
let receiver = newClass_4368696C64().toValue()
discard setSlotValue(receiver, "value", toValue(17))
doAssert getSlotValue(receiver, "value").intVal == 17
for wrong in [nilValue(), toValue("wrong"), toValue(2.5)]:
  var rejected = false
  try:
    discard setSlotValue(receiver, "value", wrong)
  except CatchableError:
    rejected = true
  doAssert rejected
  doAssert getSlotValue(receiver, "value").intVal == 17
''')
            for mm in ('arc', 'orc'):
                with self.subTest(mm=mm):
                    binary = work / ('host_' + mm)
                    self.checked(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('cache_' + mm)),
                                  '-o:' + str(binary), str(host)])
                    self.checked([str(binary)])
            source.write_text(SOURCE + '\n# stale\n')
            stale = run(args + ['--trust-observed-types'])
            self.assertNotEqual(stale.returncode, 0)
            self.assertIn('Stale type feedback', stale.stdout)

    def test_narrowed_build_keeps_reflected_library_slot_layout(self):
        # Regression: a prebuilt-only class model dropped reflected stdlib classes,
        # so their methods emitted `self.slots[i]` for a NodeValue receiver and the
        # generated Nim did not compile. Any program that pulls in a library class
        # with slots (Array/Bag/...) exercised it.
        base = ROOT / 'build/trusted-feedback-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'library.hrd'
            source.write_text(SOURCE + '''\nbag := Bag new.
bag add: 5.
Stdout writeline: bag size.
''')
            profile = work / 'feedback.json'
            self.checked([str(ROOT / 'harding'), '--type-feedback', str(profile), str(source)])
            args = [str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work),
                    '--type-feedback:' + str(profile), '--trust-observed-types']
            result = self.checked(args)
            generated = (work / 'library.nim').read_text()
            # Narrowing still applies to the application slot...
            self.assertIn('value*: int', generated)
            # ...and library methods use the checked accessors, never raw indexing
            # on a boxed receiver.
            self.assertNotIn('self.slots[', generated)
            binary = work / 'program'
            self.checked(['nim', 'c', '-d:release', '--nimcache:' + str(work / 'cache'),
                          '-o:' + str(binary), str(work / 'library.nim')])
            run = self.checked([str(binary)])
            self.assertIn('7', run.stdout)
            self.assertIn('1', run.stdout)


if __name__ == '__main__':
    unittest.main()
