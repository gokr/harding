#!/usr/bin/env python3
"""Retain checked release binaries, optional gprof profiles and paired comparisons.

Before editing runtime code: --profile. After a change: --compare saved-run-dir.
No kernel profiling permissions or system configuration changes are required.
"""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = ('richards', 'deltablue', 'queens')


def expected(case, repetitions):
    if case == 'richards':
        return f'Richards queued={2322 * repetitions} held={928 * repetitions}\n'
    if case == 'deltablue':
        return f'DeltaBlue runs={repetitions} verified\n'
    return '92\n' if repetitions else '0\n'


def snapshot(case):
    source = (ROOT / 'benchmark' / (case + '.hrd')).read_text()
    if case != 'queens':
        return source
    definitions = source.split('# Benchmark driver')[0]
    return '| repetitions solver answer |\n' + definitions + '''
repetitions := (System arguments at: 0) asInteger.
solver := Queens new. answer := 0.
repetitions timesRepeat: [
  answer := solver benchmark.
  (answer = 92) ifFalse: [Error signal: "Wrong Queens result"]
].
answer println.
'''


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, directory, label, timeout, answer=None):
    start = time.perf_counter_ns()
    try:
        completed = subprocess.run(command, cwd=directory, capture_output=True,
                                   text=True, timeout=timeout)
    except subprocess.TimeoutExpired as failure:
        raise RuntimeError(f'Timeout: {label}; artifacts: {directory}') from failure
    elapsed = (time.perf_counter_ns() - start) / 1e6
    (directory / (label + '.stdout')).write_text(completed.stdout)
    (directory / (label + '.stderr')).write_text(completed.stderr)
    if completed.returncode or (answer is not None and
                               (completed.stdout != answer or completed.stderr)):
        raise RuntimeError(f'Failed or incorrect result: {label}; artifacts: {directory}')
    return elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', action='store_true', help='also build/run -pg and save gprof output')
    parser.add_argument('--compare', type=Path, help='previous run directory to compare, using its exact sources')
    parser.add_argument('--mm', choices=('arc', 'orc'), default='arc')
    parser.add_argument('--repetitions', type=int, default=30)
    parser.add_argument('--trials', type=int, default=7)
    args = parser.parse_args()
    if args.repetitions < 1 or args.trials < 3:
        parser.error('positive repetitions and at least three trials required')
    previous = None
    if args.compare:
        args.compare = args.compare.resolve()
        previous = json.loads((args.compare / 'results.json').read_text())
        if previous['metadata']['mm'] != args.mm:
            parser.error('memory manager must match baseline')
    base = ROOT / 'build/granite-profiles'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    compiler = work / 'granite'
    run(['nim', 'c', '-d:release', '--mm:' + args.mm, '-p:' + str(ROOT / 'external'),
         '--nimcache:' + str(work / 'compiler-cache'), '-o:' + str(compiler),
         str(ROOT / 'src/harding/compiler/granite.nim')], work, 'compiler-build', 240)
    report = {'metadata': {
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'dirtyStatus': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'nim': subprocess.check_output(['nim', '--version'], text=True),
        'cc': subprocess.check_output(['cc', '--version'], text=True),
        'mm': args.mm, 'repetitions': args.repetitions, 'trials': args.trials,
        'baseline': str(args.compare) if previous else None,
        'cpu': next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
                     if line.startswith('model name')), '')}, 'cases': {}}
    for case in CASES:
        directory = work / case
        directory.mkdir()
        source = directory / (case + '.hrd')
        source.write_bytes((args.compare / case / (case + '.hrd')).read_bytes() if previous
                           else snapshot(case).encode())
        run([str(compiler), 'compile', str(source), '--home:' + str(ROOT),
             '--dir:' + str(directory), '-o:program'], ROOT, str(directory / 'generate'), 180)
        common = ['nim', 'c', '-d:release', '--mm:' + args.mm]
        binary = directory / 'program'
        run(common + ['--nimcache:' + str(directory / 'native-cache'), '-o:' + str(binary),
                      str(directory / 'program.nim')], directory, 'build', 240)
        row = {'sourceSha256': digest(source), 'binarySha256': digest(binary)}
        if previous and row['sourceSha256'] != previous['cases'][case]['sourceSha256']:
            raise RuntimeError('Baseline source drift: ' + case)
        report['cases'][case] = row
        if args.profile:
            profiled = directory / 'profile'
            run(common + ['--passC:-pg', '--passL:-pg', '--nimcache:' + str(directory / 'profile-cache'),
                          '-o:' + str(profiled), str(directory / 'program.nim')], directory, 'profile-build', 240)
            run([str(profiled), str(args.repetitions)], directory, 'profile-run', 180,
                expected(case, args.repetitions))
            run(['gprof', '-b', str(profiled), str(directory / 'gmon.out')], directory, 'gprof', 60)
        run([str(binary), str(args.repetitions)], directory, 'check', 180, expected(case, args.repetitions))
    for case, row in report['cases'].items():
        directory = work / case
        variants = {'after': directory / 'program'}
        if previous:
            baseline = args.compare / case / 'program'
            if digest(baseline) != previous['cases'][case]['binarySha256']:
                raise RuntimeError('Baseline binary changed: ' + case)
            variants['before'] = baseline
        samples = {name: [] for name in variants}
        for trial in range(args.trials + 1):
            for name in list(variants)[::1 if trial % 2 == 0 else -1]:
                elapsed = run([str(variants[name]), str(args.repetitions)], directory,
                              f'timing-{trial}-{name}', 180, expected(case, args.repetitions))
                if trial:
                    samples[name].append(elapsed / args.repetitions)
        row['samplesMsPerPass'] = samples
        row['mediansMsPerPass'] = {name: statistics.median(values) for name, values in samples.items()}
        print(case, row['mediansMsPerPass'], flush=True)
    (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Artifacts:', work, flush=True)


if __name__ == '__main__':
    main()
