#!/usr/bin/env python3
"""Pinned, checked A/B measurement for source-derived native Boolean results.

Both variants compile the same literal-argument call site with their own retained
compiler (the parent compiler versus the current one). Output and stderr are
checked on every run; all paired samples are retained in the JSON report. This is
a focused dispatch/representation measurement, not an application benchmark.
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


def source(argument):
    # A literal argument reaches the native bool path; a dynamic parameter does
    # not, and is kept as the control shape (`--argument bound`).
    return f'''| iterations answer |
BoolMeasure := Object derive: #().
BoolMeasure>>below: n limit: bound [ ^n < bound ].
BoolMeasure>>run: bound [ | i | i := 0. [self below: i limit: {argument}] whileTrue: [i := i + 1]. ^i ].
iterations := (System arguments at: 0) asInteger.
answer := BoolMeasure new run: iterations.
answer println.
'''


def execute(command, log, timeout=300):
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    log.write_text(done.stdout + done.stderr)
    if done.returncode:
        raise RuntimeError(f'{command}: see {log}')


def timed(binary, repetitions, cpu):
    start = time.perf_counter_ns()
    done = subprocess.run(['taskset', '-c', str(cpu), str(binary), str(repetitions)],
                          cwd=ROOT, capture_output=True, text=True, timeout=180)
    elapsed = time.perf_counter_ns() - start
    if done.returncode or done.stderr or done.stdout != f'{repetitions}\n':
        raise RuntimeError(f'{binary}: {done.returncode}, {done.stdout!r}, {done.stderr!r}')
    return elapsed / 1e6


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-compiler', type=Path, required=True)
    parser.add_argument('--argument', default='2000000', help='literal, or "bound" (control)')
    parser.add_argument('--repetitions', type=int, default=2000000)
    parser.add_argument('--trials', type=int, default=21)
    parser.add_argument('--mm', choices=['arc', 'orc'], default='arc')
    parser.add_argument('--cpu', type=int, default=min(os.sched_getaffinity(0)))
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0) or args.trials < 3 or args.repetitions < 1:
        parser.error('valid CPU, at least three trials and positive repetitions required')
    base = ROOT / 'build/boolean-return-measure'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    report = {'cpu': args.cpu, 'trials': args.trials, 'mm': args.mm,
              'repetitions': args.repetitions, 'argument': args.argument,
              'baselineCompiler': str(args.baseline_compiler),
              'currentCompilerSha256': hashlib.sha256((ROOT / 'granite').read_bytes()).hexdigest(),
              'method': 'alternating paired wall time; one warmup; startup included; exact stdout and empty stderr required'}
    for variant, compiler in [('before', args.baseline_compiler), ('after', ROOT / 'granite')]:
        directory = work / variant
        directory.mkdir()
        hrd = directory / 'case.hrd'
        hrd.write_text(source(args.argument))
        execute([str(compiler), 'compile', str(hrd), '--home:' + str(ROOT),
                 '--dir:' + str(directory), '-o:program'], directory / 'generate.log')
        execute(['nim', 'c', '-d:release', '--mm:' + args.mm,
                 '--nimcache:' + str(directory / 'cache'),
                 '-o:' + str(directory / 'program'), str(directory / 'program.nim')],
                directory / 'build.log')
        report[variant + 'SourceSha256'] = hashlib.sha256(hrd.read_bytes()).hexdigest()
        report[variant + 'NativeBoolCall'] = ('while booleanCall_' in
                                              (directory / 'program.nim').read_text())
    report['loadBeforeTiming'] = Path('/proc/loadavg').read_text().strip()
    samples = {'before': [], 'after': []}
    for trial in range(args.trials + 1):
        for variant in ['before', 'after'][::1 if trial % 2 == 0 else -1]:
            elapsed = timed(work / variant / 'program', args.repetitions, args.cpu)
            if trial:
                samples[variant].append(elapsed)
    ratios = [100 * (1 - after / before) for before, after in zip(samples['before'], samples['after'])]
    report.update(samples=samples, medianFasterPct=statistics.median(ratios),
                  improvedPairs=sum(ratio > 0 for ratio in ratios))
    (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Artifacts: {work}")
    print(f"native bool call site: before={report['beforeNativeBoolCall']} after={report['afterNativeBoolCall']}")
    print(f"faster by {report['medianFasterPct']:+.2f}% ({report['improvedPairs']}/{args.trials})")


if __name__ == '__main__':
    main()
