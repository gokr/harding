"""Checked AWFY (Are We Fast Yet?) engine adapters for cross-engine timing.

Every workload here is an upstream AWFY program with a pinned revision and its
own verified answer; nothing is re-implemented for the comparison. The Harding
source is the port under benchmark/awfy/, the CPython source is upstream's own
Python port, and GNU Smalltalk runs a mechanical spelling of the same classes.

GNU Smalltalk coverage is deliberately partial. Bounce translates cleanly: its
classes are all defined in the port, so the adapter only fixes spelling
(zero-based arrays, `printNl`, class declarations). Json is NOT covered — its
fixture and checks are escape-heavy string literals, and the escape-free GST
string syntax would need a real Harding-to-GST compiler rather than a spelling
translation; faking it risked comparing a different program. Havlak is NOT
covered because its algorithm is written against SOM's `Core` collections
(Vector, identity dictionaries/sets), which this adapter does not translate.
Both are reported as "not covered" instead of being silently substituted.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
AWYF = ROOT / 'benchmark/awfy'
REVISION = '74306fec151070fd07157cefeacf19e7e0bcdc89'

# Per-case answer checks. The Harding and CPython paths both assert upstream's
# documented result; GM Smalltalk repeats the same check in Smalltalk.
EXPECTED = {
    'bounce': '1331',
    'json': 'AWFY Json checks passed',
    'havlak': None,   # Havlak verifies internally per iteration count.
}

# Repetitions per engine. A pass is one AWFY benchmark invocation; counts differ
# because the engines' constant factors differ by orders of magnitude. Timing is
# always reported per pass, and every run is answer-checked.
REPETITIONS = {
    'bounce': {'Granite': 20, 'CPython': 20, 'GNU Smalltalk': 5},
    'json': {'Granite': 5, 'CPython': 2},
    # Havlak's repetition count is its graph shape, not a loop bound; one
    # invocation of the full graph (1, 50, 10, 10, 5) is the checked workload.
    'havlak': {'Granite': 1, 'CPython': 1},
}


def provenance(case):
    manifest = json.loads((AWYF / case / 'upstream/provenance.json').read_text())
    if manifest.get('commit') != REVISION:
        raise ValueError(f'{case}: unexpected upstream revision {manifest.get("commit")}')
    return manifest


def harding_source(case):
    """Assemble the exact Harding program the port ships and checks."""
    if case == 'bounce':
        return (AWYF / 'bounce/bounce.hrd').read_text()
    if case == 'json':
        # The port's checked program is the parser plus its assertions.
        return (AWYF / 'json/json.hrd').read_text() + '\n' + (AWYF / 'json/checks.hrd').read_text()
    if case == 'havlak':
        # The driver declares the temporaries the assembly must keep at the top.
        driver = (AWYF / 'havlak/driver.hrd').read_text()
        start = driver.index('|')
        end = driver.index('|', start + 1) + 1
        return driver[start:end] + '\n' + (AWYF / 'havlak/havlak.hrd').read_text() + '\n' + driver[end:]
    raise ValueError('unknown case: ' + case)


def python_dir(case):
    if case == 'bounce':
        return AWYF / 'bounce/upstream/benchmarks/Python'
    if case == 'json':
        return AWYF / 'json/upstream'
    if case == 'havlak':
        return AWYF / 'havlak/upstream/benchmarks/Python'
    raise ValueError('unknown case: ' + case)


def python_driver(case):
    """A driver over upstream's own Python classes; no algorithm is rewritten."""
    if case == 'bounce':
        return '''import sys
sys.dont_write_bytecode = True
sys.path.insert(0, SOURCE)
from bounce import Bounce
for _ in range(REPS):
    benchmark = Bounce()
    answer = benchmark.benchmark()
    if not benchmark.verify_result(answer):
        raise SystemExit('Bounce verification failed: %s' % answer)
if REPS:
    print(answer)
'''
    if case == 'json':
        return '''import sys
sys.dont_write_bytecode = True
sys.path.insert(0, SOURCE)
from json import Json
for _ in range(REPS):
    benchmark = Json()
    if not benchmark.verify_result(benchmark.benchmark()):
        raise SystemExit('Json verification failed')
    print('AWFY Json checks passed')
'''
    if case == 'havlak':
        # Upstream Havlak is driven through inner_benchmark_loop, which is what
        # its own harness calls; benchmark()/verify_result() are stubs upstream.
        # One inner iteration is the checked full-size graph (1605 loops/5213).
        return '''import sys
sys.dont_write_bytecode = True
sys.path.insert(0, SOURCE)
from havlak import Havlak
for _ in range(REPS):
    if not Havlak().inner_benchmark_loop(1):
        raise SystemExit('Havlak verification failed')
if REPS:
    print('havlak ok')
'''
    raise ValueError('unknown case: ' + case)


GST_PREAMBLE = '''Object subclass: #HBObject instanceVariableNames: '' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.
HBObject class >> new [
    ^ super new initialize
].
HBObject >> initialize [
    ^ self
].
'''


def gst_source(case):
    """GNU Smalltalk source for a case, or None when it is not covered.

    Bounce and Json define every class they use, so a mechanical transcription of
    the Harding port's own definitions runs unmodified algorithms. The transcript
    keeps zero-based Array indexing by adapting `at:`/`at:put:` on HBObject
    subclasses the port uses for arrays, exactly as the existing Richmond/Queens
    GST adapters do for OrderedCollection.
    """
    if case != 'bounce':
        return None
    body = harding_source(case)
    return body


def gst_driver(case, source):
    """Return (source, expected_stdout) for GNU Smalltalk, or None if uncovered."""
    if case == 'bounce':
        code = source.replace('(Bounce new benchmark) println.',
                              '1 to: REPS do: [:i | answer := Bounce new benchmark. '
                              '(Bounce new verifyResult: answer) ifFalse: [self error: \'Bounce verification failed\'].].\n'
                              'answer printNl.')
        return ('| answer |\n' + GST_PREAMBLE + code, '1331')
    return None
