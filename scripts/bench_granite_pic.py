#!/usr/bin/env python3
"""Pinned, checked A/B dispatch-shape experiment; not an application benchmark.

Build both variants first. --baseline-runtime is a retained runtime.nim from the
parent revision; a private runtime module lets both binaries coexist without
editing repository sources during builds or tests. Current compiler generation is
held constant to isolate the runtime PIC change. JSON retains all paired samples.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def source(width, skew):
    definitions = '\n'.join(f'PicShape{i} := Object derive: #().\nPicShape{i}>>cost [ ^{i + 1} ].'
                            for i in range(width))
    sequence = list(range(width))
    if skew:
        sequence = [0] * 9 + sequence
    values = ', '.join(f'PicShape{i} new' for i in sequence)
    code = f'''| shapes repetitions total |
{definitions}
PicDriver := Object derive: #().
PicDriver class>>run: collection times: count [
    | total index size |
    total := 0. size := collection size.
    count timesRepeat: [
        index := 0.
        [index < size] whileTrue: [
            total := total + (collection at: index) cost.
            index := index + 1
        ]
    ].
    ^total
].
shapes := array{{{values}}}.
repetitions := (System arguments at: 0) asInteger.
total := PicDriver run: shapes times: repetitions.
total println.
'''
    return code, sum(i + 1 for i in sequence)


def execute(command, log):
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
    log.write_text(done.stdout + done.stderr)
    if done.returncode:
        raise RuntimeError(f'{command}: see {log}')


def timed(binary, repetitions, expected, cpu):
    start = time.perf_counter_ns()
    done = subprocess.run(['taskset', '-c', str(cpu), str(binary), str(repetitions)],
                          cwd=ROOT, capture_output=True, text=True, timeout=180)
    elapsed = time.perf_counter_ns() - start
    if done.returncode or done.stderr or done.stdout != f'{expected * repetitions}\n':
        raise RuntimeError(f'{binary}: {done.returncode}, {done.stdout!r}, {done.stderr!r}')
    return elapsed / 1e6


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-runtime', type=Path, required=True)
    parser.add_argument('--widths', type=int, nargs='+', default=[1, 2, 3, 4, 5, 6])
    parser.add_argument('--skew', action='store_true', help='add nine uses of class zero per cycle')
    parser.add_argument('--trials', type=int, default=15)
    parser.add_argument('--repetitions', type=int, default=200000)
    parser.add_argument('--cpu', type=int, default=min(os.sched_getaffinity(0)))
    parser.add_argument('--mm', choices=['arc', 'orc'], default='arc')
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0) or args.trials < 3 or args.repetitions < 1:
        parser.error('valid CPU, at least three trials and positive repetitions required')
    if any(width < 1 or width > 32 for width in args.widths):
        parser.error('widths must be between 1 and 32')
    base = ROOT / 'build/pic-experiments'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    # Keep the baseline's runtime globals consistent across primitive helpers
    # and block support. Core/VM dependencies remain identical in both builds.
    baseline = work / 'baseline'
    baseline.mkdir()
    for module in (ROOT / 'src/harding/runtime').glob('*.nim'):
        text = args.baseline_runtime.read_text() if module.name == 'runtime.nim' else module.read_text()
        text = text.replace('import ../', 'import "' + str(ROOT / 'src/harding') + '/')
        text = '\n'.join(line + '"' if line.startswith('import "') else line for line in text.splitlines())
        (baseline / module.name).write_text(text + '\n')
    report = {'cpu': args.cpu, 'trials': args.trials, 'mm': args.mm,
              'repetitions': args.repetitions, 'skew': args.skew,
              'baselineRuntimeSha256': hashlib.sha256(args.baseline_runtime.read_bytes()).hexdigest(),
              'candidateRuntimeSha256': hashlib.sha256((ROOT / 'src/harding/runtime/runtime.nim').read_bytes()).hexdigest(),
              'method': 'alternating paired wall time; one warmup; startup included; exact stdout and empty stderr required',
              'loadAtStart': Path('/proc/loadavg').read_text().strip(), 'cases': {}}
    print('Artifacts:', work, flush=True)
    # Complete all compilation before timing.
    for width in args.widths:
        directory = work / str(width)
        directory.mkdir()
        code, answer = source(width, args.skew)
        hrd = directory / 'case.hrd'
        hrd.write_text(code)
        execute([str(ROOT / 'granite'), 'compile', str(hrd), '--home:' + str(ROOT),
                 '--dir:' + str(directory), '-o:program'], directory / 'generate.log')
        generated = (directory / 'program.nim').read_text()
        for module in ['compiled_support', 'primitive_impls']:
            generated = '\n'.join(f'import ../baseline/{module}' if line.startswith('import ') and line.rstrip().endswith('/' + module) else line
                                  for line in generated.splitlines())
        (directory / 'before.nim').write_text(generated + '\n')
        for engine, module in [('before', 'before'), ('after', 'program')]:
            execute(['nim', 'c', '-d:release', '--mm:' + args.mm,
                     '--nimcache:' + str(directory / (engine + '-cache')),
                     '-o:' + str(directory / engine), str(directory / (module + '.nim'))],
                    directory / (engine + '.log'))
        report['cases'][str(width)] = {
            'expectedPerPass': answer,
            'sourceSha256': hashlib.sha256(hrd.read_bytes()).hexdigest(),
            'binarySha256': {engine: hashlib.sha256((directory / engine).read_bytes()).hexdigest()
                             for engine in ['before', 'after']}}
    report['loadBeforeTiming'] = Path('/proc/loadavg').read_text().strip()
    for width in args.widths:
        directory = work / str(width)
        row = report['cases'][str(width)]
        samples = {'before': [], 'after': []}
        for trial in range(args.trials + 1):
            order = ['before', 'after'][::1 if trial % 2 == 0 else -1]
            for engine in order:
                elapsed = timed(directory / engine, args.repetitions, row['expectedPerPass'], args.cpu)
                if trial:
                    samples[engine].append(elapsed)
        ratios = [100 * (1 - after / before) for before, after in zip(samples['before'], samples['after'])]
        row.update(samples=samples, medianFasterPct=statistics.median(ratios),
                   improvedPairs=sum(ratio > 0 for ratio in ratios))
        print(f'{width} classes: faster by {row["medianFasterPct"]:+.2f}% ({row["improvedPairs"]}/{args.trials})', flush=True)
    (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
