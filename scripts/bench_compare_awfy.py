#!/usr/bin/env python3
"""Checked cross-engine comparison of the AWFY ports.

Times the same upstream AWFY workloads in Granite (native through this
compiler), CPython and, where available, GNU Smalltalk, and reports paired
zero-work-subtracted milliseconds per pass.

Every timed run is answer-checked: a run that fails verification, exits non-zero,
or writes to stderr is a hard failure, never a score. A zero-repetition run of
the same program is subtracted from the N-repetition run, so process startup is
measured rather than estimated. One warmup trial precedes alternating engine
order per trial and alternating reps/zero order within a trial; the reported
figure is the median of the per-trial paired differences.

Coverage is stated, not implied. GNU Smalltalk covers Bounce only: Json's
fixture is escape-heavy string data that GST's escape-free literal syntax cannot
receive without a real Harding-to-GST compiler, and Havlak is written against SOM
`Core` collections this adapter does not translate. Json and Havlak are therefore
compared against CPython alone; a missing engine is reported as uncovered and is
never presented as a number.
"""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import awfy_engines as engines      # noqa: E402
import awfy_repeat as repeat        # noqa: E402
from bench_compare import execute, sha   # noqa: E402


def nim_flags(root, mm, nimcache):
    return ['nim', 'c', '-d:release', '--mm:' + mm, '-p:' + str(root / 'external'),
            '--nimcache:' + str(nimcache)]


def build_granite(compiler, root, mm, directory, name, source_text, log):
    # Nim module names must be identifiers, so hyphens are not allowed here.
    name = name.replace('-', '_')
    source = directory / (name + '.hrd')
    source.write_text(source_text)
    binary = directory / name
    execute([str(compiler), 'compile', str(source), '--dir:' + str(directory), '-o:' + str(binary)],
            directory, log + '-generate', 240)
    execute(nim_flags(root, mm, directory / (name + '-cache')) +
            ['-o:' + str(binary), str(binary) + '.nim'], directory, log + '-build', 300)
    return binary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--mm', choices=('arc', 'orc'), default='arc')
    parser.add_argument('--python', default=sys.executable)
    parser.add_argument('--gst', type=Path,
                        default=engines.ROOT / 'build/gnu-smalltalk/install/bin/gst')
    parser.add_argument('--skip-gst', action='store_true', help='explicitly omit optional GST')
    parser.add_argument('--cases', nargs='+', default=['bounce', 'json', 'havlak'],
                        choices=['bounce', 'json', 'havlak'],
                        help='which AWFY workloads to time (default: all three)')
    parser.add_argument('--havlak-shape', nargs=5, type=int, metavar=('DUMMY', 'ITER', 'PAR', 'PPAR', 'PPP'),
                        default=[int(x) for x in repeat.HAVLAK_ARGS],
                        help='Havlak graph shape; defaults to the checked (1 50 10 10 5)')
    args = parser.parse_args()
    if args.trials < 3:
        parser.error('at least three trials required')
    root = engines.ROOT
    args.gst = args.gst.resolve()
    gst_available = not args.skip_gst and args.gst.is_file()
    if not args.skip_gst and not gst_available:
        parser.error('build GST first (scripts/setup_benchmark_gst.py) or use --skip-gst')

    base = root / 'build/awfy-compare'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    compiler = work / 'granite'
    execute(nim_flags(root, args.mm, work / 'compiler-cache') +
            ['-o:' + str(compiler), str(root / 'src/harding/compiler/granite.nim')],
            work, 'compiler-build', 300)

    report = {
        'metadata': {
            'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'dirtyStatus': subprocess.check_output(['git', 'status', '--short'], cwd=root, text=True),
            'awfyRevision': engines.REVISION,
            'mm': args.mm,
            'trials': args.trials,
            'python': subprocess.check_output([args.python, '--version'], text=True).strip(),
            'nim': subprocess.check_output(['nim', '--version'], text=True).splitlines()[0],
            'cpu': next(line.split(':', 1)[1].strip()
                        for line in Path('/proc/cpuinfo').read_text().splitlines()
                        if line.startswith('model name')),
            'loadAtStart': Path('/proc/loadavg').read_text().strip(),
            'gst': (subprocess.check_output([str(args.gst), '--version'], text=True).splitlines()[0]
                    if gst_available else 'explicitly skipped'),
            'method': 'answer-checked warmup, alternating engine and reps/zero order; '
                      'median of per-trial paired difference per pass',
            'coverage': {'bounce': ['Granite', 'CPython'] + (['GNU Smalltalk'] if gst_available else []),
                         'json': ['Granite', 'CPython'],
                         'havlak': ['Granite', 'CPython']},
            'notCovered': {'json': 'GNU Smalltalk: escape-heavy fixture; needs a real compiler, not spelling',
                           'havlak': 'GNU Smalltalk: algorithm uses SOM Core collections'},
        },
        'results': [],
    }
    if gst_available:
        report['metadata']['gstSha256'] = sha(args.gst)
    print('Artifacts:', work, flush=True)

    for case in args.cases:
        provenance = engines.provenance(case)
        directory = work / case
        directory.mkdir()
        reps = dict(engines.REPETITIONS[case])
        commands = {}

        # Granite: one program built for N reps, one for zero reps (startup only).
        binary = build_granite(compiler, root, args.mm, directory, 'granite-work',
                               repeat.granite_program(case, reps['Granite']), 'granite-work')
        baseline = build_granite(compiler, root, args.mm, directory, 'granite-zero',
                                 repeat.granite_program(case, 0), 'granite-zero')
        # Havlak takes its graph shape from argv; passing none silently ran the
        # driver's tiny default graph instead of the checked workload.
        shape = [str(n) for n in args.havlak_shape] if case == 'havlak' else []
        commands['Granite'] = {0: [str(baseline)] + shape, reps['Granite']: [str(binary)] + shape}

        # CPython: upstream's own classes, counted and verified locally.
        for count in (0, reps['CPython']):
            script = directory / f'cpython-{count}.py'
            script.write_text(repeat.python_program(case, count))
            commands.setdefault('CPython', {})[count] = [args.python, '-B', str(script)]

        # GNU Smalltalk, where the port translates.
        if gst_available and case == 'bounce':
            for count in (0, reps['GNU Smalltalk']):
                script = directory / f'gst-{count}.st'
                script.write_text(repeat.gst_program(case, count))
                commands.setdefault('GNU Smalltalk', {})[count] = [
                    str(args.gst), '--no-user-files', '-q', str(script)]

        # A repetition run must print exactly its own answer; a zero run prints
        # nothing. CPython's Json driver prints per repetition like Granite's,
        # so its expectation comes from the same rule; Bounce accumulates one
        # answer in both engines.
        checks = {}
        for engine in commands:
            checks[engine] = {0: '',
                              reps[engine]: repeat.expected_output(case, reps[engine], engine)}

        rows = {engine: {'engine': engine, 'case': case, 'reps': reps[engine], 'samples': [],
                         'commands': {str(k): v for k, v in per_count.items()}}
                for engine, per_count in commands.items()}
        for trial in range(args.trials + 1):
            for engine in list(commands)[::1 if trial % 2 == 0 else -1]:
                counts = [0, reps[engine]] if trial % 2 else [reps[engine], 0]
                times = {}
                for count in counts:
                    times[count] = execute(commands[engine][count], directory,
                                           f'{engine.replace(" ", "-")}-{trial}-{count}',
                                           600, checks[engine][count])
                if trial:
                    rows[engine]['samples'].append({
                        'workMs': times[reps[engine]], 'baselineMs': times[0],
                        'netMsPerPass': (times[reps[engine]] - times[0]) / reps[engine]})
        for engine, row in rows.items():
            for field in ('workMs', 'baselineMs', 'netMsPerPass'):
                row['median' + field[0].upper() + field[1:]] = statistics.median(
                    sample[field] for sample in row['samples'])
            if row['medianNetMsPerPass'] <= 0:
                raise RuntimeError(f'below timing resolution: {case}/{engine}')
            report['results'].append(row)
            print(f"{case:8} {engine:14} {row['medianNetMsPerPass']:10.4f} ms/pass "
                  f"total {row['medianWorkMs'] / 1000:.3f} s/{row['reps']} passes", flush=True)
        report.setdefault('provenance', {})[case] = {
            'awfyCommit': provenance.get('commit'),
            'vendoredFiles': len(provenance.get('files', []))}
        (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Results:', work / 'results.json', flush=True)


if __name__ == "__main__":
    main()
