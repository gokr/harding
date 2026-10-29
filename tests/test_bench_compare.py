import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('bench_compare', ROOT / 'scripts/bench_compare.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class BenchmarkComparisonSources(unittest.TestCase):
    def test_cog_drivers_set_author_and_do_not_save_images(self):
        for case in ['queens', 'towers']:
            source = bench.cog(case, 3, Path('/owned/result.txt'))
            self.assertIn("Utilities authorInitials: 'HB'", source)
            self.assertIn('snapshot: false andQuit: true', source)
            self.assertIn('3 timesRepeat:', source)
            self.assertIn(str(bench.EXPECTED[case]), source)
            self.assertNotIn('REPS', source)
            self.assertNotIn('OUTPATH', source)

    def test_baselines_keep_definitions_and_skip_work(self):
        for case in bench.EXPECTED:
            source = bench.hrd(case, 0)
            if case != 'sieve':
                self.assertIn('0 timesRepeat:', source)
                self.assertIn('Object derive', source)
            self.assertNotIn('{REPS}', source)

    def test_squeak_compiles_each_definition_after_its_class_creation(self):
        source = bench.cog('queens', 1, Path('/owned/result.txt'))
        self.assertIn("Compiler evaluate: 'Object subclass:", source)
        self.assertIn("Compiler evaluate: 'HBQueenPlacement compile:", source)
        self.assertLess(source.index('#HBQueenPlacement'), source.index('HBQueenPlacement compile:'))


class ClassicBenchmarkAdapter(unittest.TestCase):
    def test_definitions_preserve_checked_algorithms_and_translate_array_protocol(self):
        import cog_benchmark_source as adapter
        for case in ['richards', 'deltablue']:
            source = (ROOT / 'benchmark' / (case + '.hrd')).read_text()
            generated = adapter.driver(case, 2, Path('/owned/result.txt'), source)
            self.assertIn('HBArray', generated)
            self.assertIn('2 timesRepeat:', generated)
            self.assertIn('snapshot: false', generated)
            self.assertNotIn('derivePublic:', generated)
            self.assertIn('license', (adapter.__doc__ or '').lower())
            if case == 'deltablue':
                self.assertIn('GPL-2.0-or-later', generated)
                self.assertIn('nextWeaker', generated)
            else:
                self.assertIn('xor16:', generated)
                self.assertIn('2322', generated)

    def test_spelling_keeps_strings_and_method_work_intact(self):
        import cog_benchmark_source as adapter
        self.assertEqual(adapter.spelling('array := Array new: 4. x <> y. x & "unused"'),
                         'array := HBArray new: 4. x ~= y. x , "unused"')
        self.assertEqual(adapter.spelling("label := 'a & b <> c'."), "label := 'a & b <> c'.")

    def test_node_runner_executes_repetitions_in_one_compiled_function(self):
        from bench_compare_classic import node_driver
        source = node_driver('richards', 3, 'var test = 1;')
        self.assertIn('new Function', source)
        self.assertIn('iteration < 3', source)
        self.assertIn('runRichards();', source)
        self.assertNotIn('vm.runInContext', source)

    def test_smalltalk_statements_do_not_treat_symbols_as_comments(self):
        import cog_benchmark_source as adapter
        self.assertEqual(len(adapter.statements(adapter.ARRAY_ADAPTER, smalltalk=True)), 10)


if __name__ == '__main__':
    unittest.main()
