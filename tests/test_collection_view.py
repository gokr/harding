"""Collection shape queries must not copy the collection (native runtime parity).

The compiled runtime once answered `size` (and every other selector not handled
explicitly) by building an "ephemeral value view" of an instance collection:

    NodeValue(kind: vkArray, arrayVal: storage.elements)

`NodeValue`'s array variant owns a `seq`, so that conversion deep-copied the whole
element sequence on every message send. `size` was therefore O(n), and the AWFY
Havlak port spent 43% of its time in the resulting `eqdup`/`setLen`/`eqdestroy`
calls (309k copies; cost scaled linearly with array length).

These tests pin both halves of the contract:

* correctness — `size`, `isEmpty`, `notEmpty`, `first`, `last` answer the same
  values the interpreter does, for instance Arrays and Tables, including empty
  ones and after mutation;
* cost — the answers must NOT be proportional to element count. This is measured
  by work per query as the collection grows: a copying implementation shows a
  linear increase, the fixed one stays flat. The bound is deliberately loose
  because it runs on a shared machine; it catches an O(n) regression, not noise.

A negative control is included: the same measurement against a genuinely O(n)
operation (`includes:` on a missing element, which must scan) is expected to grow,
proving the measurement can detect copying at all.
"""
from pathlib import Path
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/test-collection-view'


def nim(args, log):
    run = subprocess.run([str(a) for a in args], cwd=ROOT, capture_output=True,
                         text=True, timeout=600)
    (BUILD / log).write_text(run.stdout + run.stderr)
    if run.returncode:
        raise AssertionError(f'{log}: {run.stdout}{run.stderr}')
    return run


class CollectionViewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        cls.compiler = BUILD / 'granite'
        nim(['nim', 'c', '-p:' + str(ROOT / 'external'),
             '--nimcache:' + str(BUILD / 'compiler-cache'),
             '-o:' + str(cls.compiler), ROOT / 'src/harding/compiler/granite.nim'],
            'compiler-build.log')

    def build_program(self, name, source):
        # Nim module names must be identifiers, so no hyphens in the file name.
        name = name.replace('-', '_')
        directory = BUILD / name
        directory.mkdir(exist_ok=True)
        hrd = directory / (name + '.hrd')
        hrd.write_text(source)
        nim([str(self.compiler), 'compile', str(hrd), '--dir:' + str(directory),
             '-o:' + str(directory / name)], name + '-generate.log')
        nim(['nim', 'c', '-d:release', '--mm:arc',
             '--nimcache:' + str(directory / 'cache'), '-o:' + str(directory / name),
             str(directory / (name + '.nim'))], name + '-build.log')
        return directory / name

    def run_both(self, name, source, expected):
        binary = self.build_program(name, source)
        native = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=300)
        self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
        self.assertEqual(native.stderr, '')
        self.assertEqual(native.stdout, expected)
        interpreter = nim(['nim', 'c', '--mm:arc', '-d:release',
                           '-p:' + str(ROOT / 'external'),
                           '--nimcache:' + str(BUILD / 'interpreter-cache'),
                           '-o:' + str(BUILD / 'harding-arc'),
                           ROOT / 'src/harding/repl/harding.nim'], 'interpreter-build.log')
        source_path = BUILD / 'shape.hrd'
        source_path.write_text(source)
        interpreted = subprocess.run([str(BUILD / 'harding-arc'), str(source_path)],
                                     cwd=ROOT, capture_output=True, text=True, timeout=300)
        self.assertEqual(interpreted.returncode, 0, interpreted.stdout + interpreted.stderr)
        self.assertEqual(interpreted.stdout, expected,
                         'native and interpreter disagree on collection shape queries')

    def test_shape_queries_agree_with_interpreter(self):
        # Values only: the label is printed separately so precedence of `&` and
        # `asString` cannot make the comparison about string building.
        source = '''a := Array new: 3 withAll: 0.
a at: 0 put: 7. a at: 2 put: 9.
a size println.
a isEmpty println.
a notEmpty println.
a first println.
a last println.
a add: 11.
a size println.
a last println.
e := Array new.
e size println.
e isEmpty println.
e notEmpty println.
t := Table new.
t at: "k" put: 5.
t size println.
t isEmpty println.
s := Set new.
s isEmpty println.
'''
        expected = ('3\nfalse\ntrue\n7\n9\n4\n11\n0\ntrue\nfalse\n1\nfalse\ntrue\n')
        self.run_both('shape', source, expected)

    def scale_program(self, name, operation, length, queries):
        """One program: build an array of `length`, run `queries` operations."""
        source = f'''a := Array new: {length} withAll: 1.
i := 0.
[ i < {queries} ] whileTrue: [ {operation} i := i + 1 ].
"done" println.
'''
        return self.build_program(name, source)

    def measure(self, name, operation, length, queries):
        """Wall time of the whole process, in seconds.

        There is no in-language clock, so the harness measures the process. The
        program itself is identical across lengths, so the difference isolates the
        per-query cost from array construction.
        """
        binary = self.scale_program(f'{name}_{length}', operation, length, queries)
        start = time.perf_counter()
        run = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=600)
        elapsed = time.perf_counter() - start
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(run.stdout, 'done\n')
        return elapsed

    def test_size_cost_is_independent_of_length(self):
        # 20000 `size` sends: O(1) is milliseconds at any length, while a copying
        # implementation is ~0.5s at 4000 elements and grows from there.
        queries = 20000
        small = self.measure('scale_size', 'a size.', 10, queries)
        large = self.measure('scale_size', 'a size.', 4000, queries)
        self.assertLess(large, max(small, 0.05) * 20,
                        f'size took {large:.3f}s at 4000 elements vs {small:.3f}s at 10: '
                        'the query is copying the collection')

    def test_includes_missing_element_still_scans(self):
        # Negative control: `includes:` over a value that is absent must examine
        # every element, so cost grows with length. If this stays flat, the
        # measurement above proves nothing.
        small = self.measure('scale_includes', 'a includes: 2.', 10, 2000)
        large = self.measure('scale_includes', 'a includes: 2.', 4000, 2000)
        self.assertGreater(large, small * 2,
                           f'includes: on a missing element did not scale '
                           f'({small:.3f}s at 10 vs {large:.3f}s at 4000); '
                           'the timing harness cannot detect linear work')


if __name__ == '__main__':
    unittest.main()
