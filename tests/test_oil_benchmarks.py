"""Checked Cog/Oil source generation and optional locally built VM smoke tests."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from bench_compare_oil import checked_driver, vm_path
from bench_compare import execute
from setup_benchmark_osvm import REVISION


class OilBenchmarkTests(unittest.TestCase):
    def test_setup_pins_full_upstream_revision(self):
        self.assertRegex(REVISION, r'^[0-9a-f]{40}$')
        self.assertIn(REVISION, (ROOT / 'docs/OPENSMALLTALK_OIL_COMPARISON.md').read_text())

    def test_wrapped_sources_keep_verification_and_never_save_image(self):
        for case in ('richards', 'deltablue', 'queens'):
            code = checked_driver(case, 5000, Path('/owned/result.txt'),
                                  (ROOT / 'benchmark' / (case + '.hrd')).read_text())
            self.assertIn('on: Error do:', code)
            self.assertIn("'ERROR: '", code)
            self.assertIn('snapshot: false andQuit: true', code)
            self.assertNotIn('snapshot: true', code)
            self.assertIn('5000 timesRepeat:', code)
            self.assertIn({'richards': '2322', 'deltablue': '223305', 'queens': '92'}[case], code)
            self.assertIn('/owned/result.txt', code)

    def test_addons_are_explicit_and_paths_are_quoted(self):
        code = checked_driver('queens', 0, Path('/owned/result.txt'), '',
                              [Path("/owned/author's patch.st")])
        self.assertIn("'/owned/author''s patch.st'", code)
        self.assertIn('fileIn', code)
        self.assertLess(code.index('fileIn'), code.index('HBQueenPlacement'))
        self.assertNotIn('fileIn', checked_driver('queens', 0, Path('/owned/out'), ''))
        with self.assertRaises(ValueError): checked_driver('queens', -1, Path('/owned/out'), '')
        with self.assertRaises(ValueError): checked_driver('unknown', 1, Path('/owned/out'), '')

    def test_error_output_is_rejected_even_with_exit_zero(self):
        base = ROOT / 'build/oil-benchmark-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            output = work / 'result.txt'
            script = work / 'fake.py'
            script.write_text('from pathlib import Path\nPath(' + repr(str(output)) +
                              ').write_text("ERROR: Wrong receiver")\n')
            with self.assertRaises(RuntimeError):
                execute([sys.executable, str(script)], work, 'invalid-result', 10, 5000, output)

    def test_local_vm_smoke_and_wrong_result_reporting(self):
        products = ROOT / 'build/osvm/repo/products'
        try:
            vms = [vm_path(products / name) for name in ('sqcogspur64linuxht', 'sqoilspur64linuxht')]
        except ValueError:
            if os.environ.get('REQUIRE_OSVM') == '1': self.fail('required Cog/Oil builds absent')
            self.skipTest('optional Cog/Oil not built')
        image = ROOT / 'build/osvm/image/Squeak6.1-23976-64bit.image'
        self.assertTrue(image.is_file())
        base = ROOT / 'build/oil-benchmark-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            shutil.copy2(image, work / 'bench.image')
            shutil.copy2(image.with_suffix('.changes'), work / 'bench.changes')
            for source in image.parent.glob('*.sources'): shutil.copy2(source, work / source.name)
            for vm in vms:
                for case in ('richards', 'deltablue', 'queens'):
                    output, script = work / 'result.txt', work / 'test.st'
                    script.write_text(checked_driver(case, 1, output,
                                      (ROOT / 'benchmark' / (case + '.hrd')).read_text()))
                    execute([str(vm), '-nodisplay', '-nosound', str(work / 'bench.image'), str(script)],
                            work, vm.parent.parent.name + '-' + case, 30, 92 if case == 'queens' else 1, output)
                script.write_text(checked_driver('queens', 1, output, '').replace('answer = 92', 'answer = 0'))
                with self.assertRaises(RuntimeError):
                    execute([str(vm), '-nodisplay', '-nosound', str(work / 'bench.image'), str(script)],
                            work, 'wrong-result', 30, 92, output)
                self.assertIn('ERROR:', output.read_text())


if __name__ == '__main__':
    unittest.main()
