#!/usr/bin/env python3
"""Build release engines and record checked, paired Richards process timings.

No performance threshold: run on an idle host. Zero-run subtraction is approximate
and excludes startup/parsing from neither raw measurement; both are recorded.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def expected(count, benchmark='richards'):
    if benchmark == 'deltablue':
        return f'DeltaBlue runs={count} verified\n'
    return f'Richards queued={2322 * count} held={928 * count}\n'


def run(command, work, label, timeout, output=None):
    started = time.perf_counter_ns()
    with subprocess.Popen(command, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, start_new_session=True) as child:
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            stdout, stderr = child.communicate()
            (work / (label + '.stderr')).write_text(stderr + '\nTIMEOUT\n')
            raise RuntimeError(f'timeout: {label}; artifacts: {work}')
    elapsed = (time.perf_counter_ns() - started) / 1e6
    (work / (label + '.stdout')).write_text(stdout)
    (work / (label + '.stderr')).write_text(stderr)
    if child.returncode or (output is not None and (stdout != output or stderr)):
        raise RuntimeError(f'incorrect result: {label}; artifacts: {work}')
    return elapsed


def main(benchmark='richards'):
    parser = argparse.ArgumentParser(description=f'Checked release-engine timings for {benchmark}.')
    parser.add_argument('--mm', choices=('arc', 'orc'), default='arc')
    parser.add_argument('--repetitions', type=int, default=10)
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    if args.repetitions < 1 or args.trials < 3 or args.timeout < 1:
        parser.error('positive repetitions/timeout and at least three trials required')
    base = ROOT / ('build/' + benchmark + '-bench')
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    source = work / (benchmark + '.hrd')
    source.write_bytes((ROOT / 'benchmark' / (benchmark + '.hrd')).read_bytes())
    interpreter = work / 'harding'
    compiler = work / 'granite'
    native = work / benchmark
    common = ['nim', 'c', '-d:release', '--mm:' + args.mm, '-p:external']
    commands = [
        common + ['--nimcache:' + str(work / 'interp-cache'), '-o:' + str(interpreter),
                  'src/harding/repl/harding.nim'],
        common + ['--nimcache:' + str(work / 'compiler-cache'), '-o:' + str(compiler),
                  'src/harding/compiler/granite.nim'],
        [str(compiler), 'compile', str(source), '--dir:' + str(work), '-o:' + benchmark],
        common + ['--nimcache:' + str(work / 'native-cache'), '-o:' + str(native), str(work / (benchmark + '.nim'))],
    ]
    for index, command in enumerate(commands):
        run(command, work, 'build-' + str(index), max(240, args.timeout))
    engines = {'interpreter': [str(interpreter), str(source), '--'], 'granite': [str(native)]}
    metadata = {
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'dirtyStatus': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'nim': subprocess.check_output(['nim', '--version'], text=True),
        'cCompiler': subprocess.check_output(['cc', '--version'], text=True).splitlines()[0],
        'platform': platform.platform(), 'cpu': platform.processor(), 'cpuCount': os.cpu_count(),
        'benchmark': benchmark, 'mm': args.mm, 'repetitions': args.repetitions, 'trials': args.trials,
        'buildCommands': commands, 'engineCommands': engines,
        'sourceSha256': digest(source),
        'binarySha256': {name: digest(path) for name, path in
                         [('interpreter', interpreter), ('compiler', compiler), ('granite', native)]},
        'clock': 'perf_counter_ns process wall time',
        'notes': 'Single process per observation; includes startup/source loading. Paired 0-run subtraction is approximate; not an Octane score. Benchmark-specific adaptations and cleanup costs are included.',
    }
    cpuinfo = Path('/proc/cpuinfo')
    if cpuinfo.exists():
        metadata['cpuModel'] = next((line.split(':', 1)[1].strip() for line in cpuinfo.read_text().splitlines()
                                     if line.startswith('model name')), '')
    rows = {name: {'workMs': [], 'baselineMs': [], 'pairedNetMsPerRun': []} for name in engines}
    for trial in range(args.trials + 1):
        # First pair is checked warm-up and excluded from statistics.
        for name in list(engines)[::1 if trial % 2 == 0 else -1]:
            pair = {}
            counts = [args.repetitions, 0] if trial % 2 == 0 else [0, args.repetitions]
            for count in counts:
                pair[count] = run(engines[name] + [str(count)], work,
                                  f'{name}-{trial}-{count}', args.timeout, expected(count, benchmark))
            if trial:
                rows[name]['workMs'].append(pair[args.repetitions])
                rows[name]['baselineMs'].append(pair[0])
                rows[name]['pairedNetMsPerRun'].append((pair[args.repetitions] - pair[0]) / args.repetitions)
    for name, row in rows.items():
        row['medianWorkMs'] = statistics.median(row['workMs'])
        row['medianBaselineMs'] = statistics.median(row['baselineMs'])
        row['medianNetMsPerRun'] = statistics.median(row['pairedNetMsPerRun'])
        print(f"{name}: {row['medianWorkMs']:.3f} ms total / {args.repetitions} runs; "
              f"{row['medianBaselineMs']:.3f} ms zero-run baseline; "
              f"{row['medianNetMsPerRun']:.3f} ms/run paired net", flush=True)
    (work / 'results.json').write_text(json.dumps({'metadata': metadata, 'engines': rows}, indent=2) + '\n')
    print('Artifacts:', work.relative_to(ROOT))


if __name__ == '__main__':
    main()
