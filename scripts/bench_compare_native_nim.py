#!/usr/bin/env python3
"""Compare Granite, CPython and hand-written native Nim on identical work.

The native Nim ports under benchmark/native/ are the reference for what an
idiomatic implementation costs. Reports per-pass times for all three, so the
gap can be attributed to translation rather than to the algorithm.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def timed(command, cpu, timeout=300):
    start = time.perf_counter_ns()
    done = subprocess.run(['taskset', '-c', str(cpu)] + command, cwd=ROOT,
                          capture_output=True, text=True, timeout=timeout)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    if done.returncode:
        raise RuntimeError(f'{command} failed: {done.stderr[-2000:]}')
    return elapsed, done.stdout


def build_native(work):
    results = {}
    for case in ['richards', 'deltablue']:
        source = ROOT / 'benchmark' / 'native' / f'{case}.nim'
        binary = work / f'native-{case}'
        subprocess.run(['nim', 'c', '-d:release', '--mm:arc',
                        '--nimcache:' + str(work / f'nimcache-{case}'),
                        '-o:' + str(binary), str(source)],
                       cwd=ROOT, check=True, capture_output=True, text=True)
        results[case] = binary
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path, help='retained Granite profile run')
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--trials', type=int, default=9)
    parser.add_argument('--repetitions', type=int, default=300)
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0):
        parser.error('CPU outside affinity mask')
    args.run = args.run.resolve()
    work = ROOT / 'build' / 'native-compare'
    work.mkdir(parents=True, exist_ok=True)
    natives = build_native(work)

    sys.path.insert(0, str(ROOT / 'scripts'))
    from python_benchmark_source import driver
    from profile_granite import expected

    report = {'cpu': args.cpu, 'trials': args.trials,
              'repetitions': args.repetitions,
              'graniteRun': str(args.run),
              'loadAtStart': Path('/proc/loadavg').read_text().strip(), 'cases': {}}
    for case in ['richards', 'deltablue']:
        directory = args.run / case
        binary = directory / 'program'
        programs = {}
        for count in [0, args.repetitions]:
            path = work / f'{case}-{count}.py'
            path.write_text(driver(case, count, (directory / f'{case}.hrd').read_text()))
            programs[count] = path
        samples = {e: [] for e in ['Granite', 'CPython', 'NativeNim']}
        commands = {
            'Granite': lambda c: [str(binary), str(c)],
            'CPython': lambda c: [sys.executable, str(programs[c])],
            'NativeNim': lambda c: [str(natives[case]), str(c)],
        }
        for trial in range(args.trials + 1):
            order = ['Granite', 'CPython', 'NativeNim']
            if trial % 2:
                order = order[::-1]
            for engine in order:
                elapsed, _ = timed(commands[engine](args.repetitions), args.cpu)
                if trial:
                    samples[engine].append(elapsed / args.repetitions)
        medians = {e: statistics.median(v) for e, v in samples.items()}
        report['cases'][case] = {'samples': samples, 'medians': medians}
        native = medians['NativeNim']
        print(f"{case:10} Granite {medians['Granite']:8.3f}  "
              f"CPython {medians['CPython']:8.3f}  NativeNim {native:8.3f} ms/pass")
        print(f"{'':10} Granite/Native {medians['Granite']/native:5.2f}x   "
              f"CPython/Native {medians['CPython']/native:5.2f}x")
    (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Artifacts:', work)


if __name__ == '__main__':
    main()
