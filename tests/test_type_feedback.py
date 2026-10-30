"""Interpreter feedback, stale-input rejection and unchanged compiled semantics."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def run(command, cwd=ROOT):
    return subprocess.run(command, cwd=cwd, env=dict(os.environ, HARDING_HOME=str(ROOT)),
                          capture_output=True, text=True, timeout=180)


class TypeFeedback(unittest.TestCase):
    def test_profile_and_compiler_report(self):
        base = ROOT / 'build/type-feedback-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'program.hrd'
            source.write_text('''Box := Object derivePublic: #(value, next).
Box>>set: item [ value := item. next := nil. ^self ].
box := Box new.
Stdout writeline: box value isNil.
box set: 3.
box set: 2.5.
Stdout writeline: box value.
''')
            profile = work / 'profile.json'
            report = work / 'report.json'
            plain = run([str(ROOT / 'harding'), str(source)])
            observed = run([str(ROOT / 'harding'), '--type-feedback', str(profile), str(source)])
            self.assertEqual(observed.returncode, 0, observed.stderr)
            self.assertEqual((observed.stdout, observed.stderr), (plain.stdout, plain.stderr))
            data = json.loads(profile.read_text())
            self.assertEqual(data['schema'], 1)
            self.assertIn(str(source), data['sources'])
            slot = data['slots']['Box#value']
            self.assertGreater(slot['initial:Nil'], 0)
            self.assertGreater(slot['read:Nil'], 0)
            self.assertGreater(slot['write:Integer'], 0)
            self.assertGreater(slot['write:Float'], 0)
            self.assertGreater(data['slots']['Box#next']['write:Nil'], 0)
            arguments = [str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work), '-o:program']
            first = run(arguments)
            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            nativeSource = (work / 'program.nim').read_text()
            second = run(arguments + ['--type-feedback:' + str(profile), '--inference-report:' + str(report)])
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertEqual((work / 'program.nim').read_text(), nativeSource)
            merged = json.loads(report.read_text())['slots']['Box#value']
            self.assertEqual(merged['observations'], slot)
            self.assertTrue(merged['requiresGuard'])
            self.assertEqual(merged['staticCandidate'], 'skDynamic')
            source.write_text(source.read_text() + '\n# source drift\n')
            stale = run(arguments + ['--type-feedback:' + str(profile), '--inference-report:' + str(report)])
            self.assertNotEqual(stale.returncode, 0)
            self.assertIn('Stale type feedback', stale.stdout)

    def test_failed_run_does_not_leave_profile(self):
        base = ROOT / 'build/type-feedback-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'bad.hrd'
            source.write_text('1 noSuchMethod')
            profile = work / 'profile.json'
            profile.write_text('old success')
            observed = run([str(ROOT / 'harding'), '--type-feedback', str(profile), str(source)])
            self.assertNotEqual(observed.returncode, 0)
            self.assertFalse(profile.exists())

    def test_loaded_source_is_hashed_and_changes_rejected(self):
        base = ROOT / 'build/type-feedback-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            loaded = work / 'loaded.hrd'
            loaded.write_text('Box := Object derivePublic: #(value).\nBox>>set: v [value := v].')
            source = work / 'test.hrd'
            source.write_text(f'Harding load: "{loaded}".\nBox new set: 1.')
            profile = work / 'profile.json'
            observed = run([str(ROOT / 'harding'), '--type-feedback', str(profile), str(source)])
            self.assertEqual(observed.returncode, 0, observed.stderr)
            self.assertIn(str(loaded), json.loads(profile.read_text())['sources'])
            loaded.write_text(loaded.read_text() + '\n# drift')
            compiled = run([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work),
                            '--type-feedback:' + str(profile), '--inference-report:' + str(work / 'report.json')])
            self.assertNotEqual(compiled.returncode, 0)
            self.assertIn('Stale type feedback', compiled.stdout)


if __name__ == '__main__':
    unittest.main()
