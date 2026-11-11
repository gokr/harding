#!/usr/bin/env python3
"""Compare Granite, CPython and hand-written Nim on matched workloads.

Native ports are explicit representation references, not language-parity ports:
Richards embeds task variants/fixed arrays, and DeltaBlue uses Float64 values.
Every execution checks output and stderr; raw wall time includes startup.
"""
import argparse
import json
import hashlib
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def timed(command, cpu, timeout=300):
    start = time.perf_counter_ns()
    done = subprocess.run(['taskset', '-c', str(cpu)] + command, cwd=ROOT,
                          capture_output=True, text=True, timeout=timeout)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    if done.returncode or done.stderr:
        raise RuntimeError(f'{command} failed: {done.returncode}, {done.stderr[-2000:]}')
    return elapsed, done.stdout


# Cases with a hand-written Nim port. shapes/tree were added with their ports so the
# floor is available for the workloads the specialization actually targets.
NATIVE_CASES = ('richards', 'deltablue', 'shapes', 'tree')


def build_native(work, cases):
    results = {}
    for case in cases:
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
    if args.trials < 3 or args.repetitions < 1:
        parser.error('at least three trials and positive repetitions required')
    if args.cpu not in os.sched_getaffinity(0):
        parser.error('CPU outside affinity mask')
    args.run = args.run.resolve()
    base = ROOT / 'build' / 'native-compare'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    saved = json.loads((args.run / 'results.json').read_text())
    cases = [c for c in NATIVE_CASES if c in saved['cases']]
    if not cases:
        sys.exit('retained run has none of: ' + ', '.join(NATIVE_CASES))
    natives = build_native(work, cases)
    print('Artifacts:', work, flush=True)

    sys.path.insert(0, str(ROOT / 'scripts'))
    from python_benchmark_source import driver
    from profile_granite import expected

    report = {'cpu': args.cpu, 'trials': args.trials,
              'repetitions': args.repetitions,
              'graniteRun': str(args.run),
              'method': 'raw process wall time, checked outputs, pinned alternating engines; startup included',
              'nativeCaveats': 'Representation reference, not semantic parity: Richards embeds task variants and fixed arrays; DeltaBlue uses Float64 values and rank integers. Native ports retain workload checks and teardown.',
              'loadAtStart': Path('/proc/loadavg').read_text().strip(), 'cases': {}}
    for case in cases:
        directory = args.run / case
        binary = directory / 'program'
        source = directory / f'{case}.hrd'
        for path, field in [(binary, 'binarySha256'), (source, 'sourceSha256')]:
            if hashlib.sha256(path.read_bytes()).hexdigest() != saved['cases'][case][field]:
                raise RuntimeError('retained artifact changed: ' + str(path))
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
                elapsed, answer = timed(commands[engine](args.repetitions), args.cpu)
                wanted = (str(args.repetitions) + '\n' if engine == 'CPython'
                          else expected(case, args.repetitions))
                if answer != wanted:
                    raise RuntimeError(f'{case} {engine}: expected {wanted!r}, got {answer!r}')
                if trial:
                    samples[engine].append(elapsed / args.repetitions)
        medians = {e: statistics.median(v) for e, v in samples.items()}
        paired = {engine: statistics.median(x / y for x, y in zip(values, samples['NativeNim']))
                  for engine, values in samples.items() if engine != 'NativeNim'}
        report['cases'][case] = {'samples': samples, 'medians': medians,
                                 'pairedNativeTimeRatios': paired,
                                 'nativeSourceSha256': hashlib.sha256((ROOT / 'benchmark/native' / f'{case}.nim').read_bytes()).hexdigest()}
        native = medians['NativeNim']
        print(f"{case:10} Granite {medians['Granite']:8.3f}  "
              f"CPython {medians['CPython']:8.3f}  NativeNim {native:8.3f} ms/pass")
        print(f"{'':10} Granite/Native {paired['Granite']:5.2f}x   "
              f"CPython/Native {paired['CPython']:5.2f}x", flush=True)
    (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Artifacts:', work)


if __name__ == '__main__':
    main()
