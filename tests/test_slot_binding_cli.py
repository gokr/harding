"""Method declaration errors agree in interpreted and compiled Harding."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SlotBindingCliTest(unittest.TestCase):
    def test_all_method_definition_forms_reject_slot_collisions(self):
        prefix = 'BindingBase := Object derive: #(payload). BindingChild := BindingBase derive: #().\n'
        forms = [
            'BindingChild>>probe [| payload | ^payload].',
            'BindingChild>>probe: payload [^payload].',
            'BindingChild>>probe [true ifTrue: [| payload | payload := 1]].',
            'BindingChild>>probe [^[:payload | payload]].',
            'BindingChild selector: #probe put: [| payload | payload := 1].',
            'BindingChild extend: [self >> probe [| payload | payload := 1]].',
        ]
        base = ROOT / 'build/slot-binding-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            for index, form in enumerate(forms):
                source = work / ('rejected' + str(index) + '.hrd')
                source.write_text(prefix + form + '\n"UNREACHABLE" println.\n')
                for engine in ('harding', 'granite'):
                    with self.subTest(form=form, engine=engine):
                        command = [str(ROOT / engine)]
                        if engine == 'granite':
                            command += ['compile', '--dir:' + str(work), '-o:rejected']
                        command += [str(source)]
                        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
                        self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
                        self.assertIn("Local binding 'payload' shadows slot", run.stdout + run.stderr)
                        self.assertNotIn('UNREACHABLE', run.stdout)
                        self.assertFalse((work / 'rejected.nim').exists())

    def test_class_factories_and_unrelated_caller_locals_remain_legal(self):
        base = ROOT / 'build/slot-binding-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            source = work / 'allowed.hrd'
            source.write_text('''BindingBase := Object derivePublic: #(payload).
BindingBase class>>with: payload [^self new payload: payload].
BindingBase>>sample [true ifTrue: [^payload]. ^nil].
BindingCaller := Object derive: #().
BindingCaller>>sampleFrom: target [| payload | payload := 77. ^target sample].
(BindingCaller new sampleFrom: (BindingBase with: 5)) println.
''')
            interpreted = subprocess.run([str(ROOT / 'harding'), str(source)], cwd=ROOT,
                                         capture_output=True, text=True, timeout=30)
            self.assertEqual(interpreted.returncode, 0, interpreted.stdout + interpreted.stderr)
            self.assertEqual(interpreted.stdout, '5\n')
            binary = work / 'allowed'
            built = subprocess.run([str(ROOT / 'granite'), 'build', str(source),
                                    '--dir:' + str(work), '-o:' + str(binary)], cwd=ROOT,
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            native = subprocess.run([str(binary)], cwd=work, capture_output=True, text=True, timeout=30)
            self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
            self.assertEqual(native.stdout, interpreted.stdout)


if __name__ == '__main__':
    unittest.main()
