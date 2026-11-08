#!/usr/bin/env python3
"""Answer-checked, CPU-pinned paired comparison of retained Granite and CPython.

Uses a retained profile_granite.py run; never rebuilds the timed Granite binary.
Python is a restricted mechanical translation, not the upstream AWFY program.
Reports raw process times and paired zero-work subtraction separately.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time

from profile_granite import expected
from python_benchmark_source import driver

ROOT = Path(__file__).resolve().parents[1]


def timed(command, answer, cpu):
    start = time.perf_counter_ns()
    done = subprocess.run(['taskset', '-c', str(cpu)] + command, cwd=ROOT,
                          capture_output=True, text=True, timeout=180)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    if done.returncode or done.stderr or done.stdout != answer:
        raise RuntimeError(f'Incorrect result: {command}: {done.returncode}, '
                           f'{done.stdout!r}, {done.stderr!r}')
    return elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path, help='retained Granite profile run')
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--trials', type=int, default=15)
    parser.add_argument('--repetitions', type=int, default=30)
    args = parser.parse_args()
    if args.trials < 3 or args.repetitions < 1:
        parser.error('at least three trials and positive repetitions required')
    if args.cpu not in os.sched_getaffinity(0):
        parser.error('CPU is outside this process affinity mask')
    args.run = args.run.resolve()
    saved = json.loads((args.run / 'results.json').read_text())
    base = ROOT / 'build/python-pinned'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    report = {'cpu': args.cpu, 'trials': args.trials,
              'repetitions': args.repetitions, 'graniteRun': str(args.run),
              'python': subprocess.check_output([sys.executable, '--version'], text=True).strip(),
              'loadAtStart': Path('/proc/loadavg').read_text().strip(), 'cases': {}}
    print('Artifacts:', work, flush=True)
    for case in ['richards', 'deltablue', 'queens']:
        directory = args.run / case
        binary = directory / 'program'
        binary_sha = hashlib.sha256(binary.read_bytes()).hexdigest()
        if binary_sha != saved['cases'][case]['binarySha256']:
            raise RuntimeError('retained binary changed: ' + case)
        source = (directory / (case + '.hrd')).read_text()
        source_sha = hashlib.sha256(source.encode()).hexdigest()
        if source_sha != saved['cases'][case]['sourceSha256']:
            raise RuntimeError('retained source changed: ' + case)
        programs = {}
        for count in [0, args.repetitions]:
            path = work / f'{case}-{count}.py'
            path.write_text(driver(case, count, source))
            programs[count] = path
        samples = {engine: {'rawMsPerPass': [], 'netMsPerPass': [], 'zeroMs': []}
                   for engine in ['Granite', 'CPython']}
        for trial in range(args.trials + 1):
            order = ['Granite', 'CPython'] if trial % 2 == 0 else ['CPython', 'Granite']
            for engine in order:
                times = {}
                counts = [0, args.repetitions] if trial % 2 else [args.repetitions, 0]
                for count in counts:
                    command = ([str(binary), str(count)] if engine == 'Granite' else
                               [sys.executable, str(programs[count])])
                    answer = expected(case, count) if engine == 'Granite' else str(count) + '\n'
                    times[count] = timed(command, answer, args.cpu)
                if trial:
                    row = samples[engine]
                    row['rawMsPerPass'].append(times[args.repetitions] / args.repetitions)
                    row['netMsPerPass'].append((times[args.repetitions] - times[0]) / args.repetitions)
                    row['zeroMs'].append(times[0])
        row = {'samples': samples, 'binarySha256': binary_sha,
               'sourceSha256': source_sha,
               'medians': {engine: {key: statistics.median(values) for key, values in data.items()}
                           for engine, data in samples.items()}}
        for measure in ['rawMsPerPass', 'netMsPerPass']:
            ratios = [x / y for x, y in zip(samples['Granite'][measure], samples['CPython'][measure])]
            if min(samples['CPython'][measure]) <= 0 or min(samples['Granite'][measure]) <= 0:
                raise RuntimeError('timing below resolution: ' + case)
            row[measure + 'Ratio'] = statistics.median(ratios)
        report['cases'][case] = row
        g, p = row['medians']['Granite'], row['medians']['CPython']
        print(f"{case:10} raw {g['rawMsPerPass']:.3f}/{p['rawMsPerPass']:.3f} ms "
              f"({row['rawMsPerPassRatio']:.2f}x CPython time); "
              f"net {g['netMsPerPass']:.3f}/{p['netMsPerPass']:.3f} ms "
              f"({row['netMsPerPassRatio']:.2f}x)", flush=True)
        (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
