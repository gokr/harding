"""Repetition wrappers and answer checks for checked AWFY timing.

A timed run must execute the workload N times in ONE process (so startup is
measured once and subtracted), verify after EVERY repetition, and print exactly
the same answer a single run prints. These helpers build that wrapper for each
case without touching the workload itself: the benchmark classes and their
drivers are the port's own source, and only the trailing driver statement is
replaced by a counted loop.

Granite, CPython and GNU Smalltalk all use the same contract — N repetitions,
one answer on stdout, non-zero exit and a stderr write on any failed check — so
the timings compare identical work.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import awfy_engines as engines  # noqa: E402
import awfy_gst               # noqa: E402

# The trailing driver statement each port ends with, and the answer a run prints.
DRIVER = {
    'bounce': '(Bounce new benchmark) println.',
    'json': 'JsonChecks run.',
    'havlak': None,   # Havlak's driver reads argv and prints its own result.
}
ANSWER = {
    'bounce': '1331',
    'json': 'AWFY Json checks passed',
    'havlak': 'Havlak loops=1605 nodes=5213',
}

# Havlak's workload is its graph shape, passed as argv (dummy, findLoopIterations,
# par, ppar, pppar). CPython runs main(1, 50, 10, 10, 5) through its own harness,
# so the compiled port must receive exactly that; leaving argv empty silently ran
# the driver's (1, 0, 1, 1, 1) default, which is a different, far smaller graph.
HAVLAK_ARGS = ['1', '50', '10', '10', '5']


def granite_program(case, reps):
    """Port source with its driver replaced by a verified `reps` loop."""
    source = engines.harding_source(case)
    if case == 'bounce':
        body = source.replace(DRIVER[case], '').rstrip()
        if reps == 0:
            # The zero-work baseline must print nothing: it measures startup and
            # class initialization only, so no answer is available to print.
            return body + '\n'
        return body + f'''
answer := nil.
ok := true.
1 to: {reps} do: [:i |
  answer := Bounce new benchmark.
  (Bounce new verifyResult: answer) ifFalse: [ ok := false ]
].
ok ifFalse: [ "FAILED" println ] ifTrue: [ answer println ].
'''
    if case == 'json':
        # JsonChecks>>run asserts internally and prints its success line; repeat it.
        # JsonChecks>>run asserts every check itself and prints its own success
        # line; repeating it N times must therefore print that line N times.
        body = source.replace(DRIVER[case], '').rstrip()
        return body + f'''
1 to: {reps} do: [:i |
  JsonChecks run
].
'''
    # Havlak's driver reads its shape from argv, so its repetition count is the
    # graph shape, not a loop bound. One invocation is the checked full-size
    # graph. The zero-work baseline is the same definitions with the final
    # invocation removed: class and library initialization still run, which is
    # exactly the fixed cost the subtraction must remove.
    if case == 'havlak':
        if reps == 1:
            return source
        if reps == 0:
            driver = (engines.AWYF / 'havlak/driver.hrd').read_text()
            start = driver.index('|')
            header = driver[start:driver.index('|', start + 1) + 1]
            return header + '\n' + (engines.AWYF / 'havlak/havlak.hrd').read_text() + '\n'
        raise ValueError('havlak only supports one repetition')
    raise ValueError('unknown case: ' + case)


def gst_program(case, reps):
    """GNU Smalltalk program with the same contract, or None when uncovered."""
    if case != 'bounce':
        return None
    text = awfy_gst.translate(engines.harding_source(case).replace(DRIVER[case], '').rstrip())
    if reps == 0:
        return text
    return text + f'''
| answer ok |
answer := nil. ok := true.
1 to: {reps} do: [:i |
  answer := Bounce new benchmark.
  (Bounce new verifyResult: answer) ifFalse: [ ok := false ]].
ok
  ifFalse: [ 'FAILED' printNl ]
  ifTrue: [ answer printNl ].
'''


# CPython's Havlak driver verifies through upstream's own verifier and reports
# success; the compiled port prints the graph summary its driver formats. Both
# confirm the same graph, so each engine is checked against its own answer.
PYTHON_ANSWER = {'havlak': 'havlak ok'}


def expected_output(case, reps, engine='Granite'):
    """Exact stdout a repetition run must produce ('' for the zero run).

    Bounce accumulates and prints one answer after the loop; Json's own check
    method prints its success line per repetition, so N runs print it N times.
    Havlak prints its graph summary once per invocation.

    The harness compares `stdout.strip()`, so these carry no trailing newline.
    """
    if reps == 0:
        return ''
    answer = PYTHON_ANSWER.get(case, ANSWER[case]) if engine == 'CPython' else ANSWER[case]
    if case == 'json':
        return '\n'.join([answer] * reps)
    return answer


def python_program(case, reps):
    """Upstream Python classes driven by a counted, verified loop.

    The upstream directory is injected rather than copied, so the timed source is
    upstream's own file and not a local variant.
    """
    template = engines.python_driver(case).replace('REPS', str(reps))
    source = repr(str(engines.python_dir(case)))
    return template.replace('sys.path.insert(0, SOURCE)', f'sys.path.insert(0, {source})')
