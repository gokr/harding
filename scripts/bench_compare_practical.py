#!/usr/bin/env python3
"""Checked CPython/GNU Smalltalk/native Nim/Granite comparison of matched workloads.

Reports raw process wall times and paired zero-work-subtracted milliseconds per
pass. Uses restricted mechanical Python/GST ports; native Nim is an explicit
static representation reference, not a byte-for-byte dynamic-language port.
"""
import argparse
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import tempfile

from bench_compare import ROOT, execute, sha
from bench_objects import NIM_SOURCE
from profile_granite import snapshot, expected
from python_benchmark_source import driver as python_driver
from gst_benchmark_source import driver as gst_driver


def native_source(case):
    if case == 'queens':
        return NIM_SOURCE.replace('let reps = parseInt(paramStr(1))',
                                  'let reps = parseInt(paramStr(1))\ndoAssert reps >= 0').replace(
                                      'answer = search(0, nil)',
                                      'answer = search(0, nil)\n    doAssert answer == 92')
    return (ROOT / 'benchmark/native' / (case + '.nim')).read_text()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=7)
    parser.add_argument('--mm', choices=('arc', 'orc'), default='arc')
    parser.add_argument('--python', default=sys.executable)
    parser.add_argument('--gst', type=Path, default=ROOT / 'build/gnu-smalltalk/install/bin/gst')
    parser.add_argument('--skip-gst', action='store_true', help='explicitly omit optional GST')
    args = parser.parse_args()
    if args.trials < 3: parser.error('at least three trials required')
    args.gst = args.gst.resolve()
    if not args.skip_gst and not args.gst.is_file(): parser.error('build GST first or use --skip-gst')
    base = ROOT / 'build/bench-compare-practical'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    flags = ['nim', 'c', '-d:release', '--mm:' + args.mm, '-p:' + str(ROOT / 'external')]
    compiler = work / 'granite'
    execute(flags + ['--nimcache:' + str(work / 'compiler-cache'), '-o:' + str(compiler),
                     str(ROOT / 'src/harding/compiler/granite.nim')], work, 'compiler-build', 240)
    metadata = {'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'dirtyStatus': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
                'mm': args.mm, 'trials': args.trials, 'python': subprocess.check_output([args.python, '--version'], text=True),
                'nim': subprocess.check_output(['nim', '--version'], text=True),
                'gcc': subprocess.check_output(['gcc', '--version'], text=True).splitlines()[0],
                'cpu': next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),
                'gst': 'explicitly skipped' if args.skip_gst else subprocess.check_output([str(args.gst), '--version'], text=True),
                'method': 'checked warmup, alternating engines and work/zero-work order; median paired difference per pass',
                'nativeCaveats': 'Richards embeds task variants and fixed arrays, no scheduler back-reference. DeltaBlue uses Float64 values and integer strength ranks. Both retain workload checks and explicit ownership teardown.'}
    report = {'metadata': metadata, 'results': []}
    if not args.skip_gst: metadata['gstSha256'] = sha(args.gst)
    print('Artifacts:', work, flush=True)
    for case in ('richards', 'deltablue', 'queens'):
        directory = work / case
        directory.mkdir()
        source = directory / (case + '.hrd')
        source.write_text(snapshot(case))
        original = (ROOT / 'benchmark' / (case + '.hrd')).read_text()
        for license_path in (ROOT / 'benchmark/licenses').iterdir():
            if license_path.is_file(): shutil.copy2(license_path, directory / license_path.name)
        binary = directory / 'granite_program'
        execute([str(compiler), 'compile', str(source), '--dir:' + str(directory), '-o:' + str(binary)],
                directory, 'generate', 180)
        execute(flags + ['--nimcache:' + str(directory / 'granite-cache'), '-o:' + str(binary), str(binary) + '.nim'],
                directory, 'granite-build', 240)
        native_path = directory / 'native.nim'
        native_path.write_text(native_source(case))
        native = directory / 'native'
        execute(flags + ['--nimcache:' + str(directory / 'native-cache'), '-d:' + case,
                         '-o:' + str(native), str(native_path)], directory, 'native-build', 240)
        reps = {'Granite': 30, 'CPython': 300, 'Native Nim': 2000}
        engines = {'Granite': {n: [str(binary), str(n)] for n in (0, reps['Granite'])},
                   'Native Nim': {n: [str(native), str(n)] for n in (0, reps['Native Nim'])},
                   'CPython': {}}
        if not args.skip_gst:
            reps['GNU Smalltalk'] = 1000
            engines['GNU Smalltalk'] = {}
        for engine, generate, suffix in [('CPython', python_driver, '.py'), ('GNU Smalltalk', gst_driver, '.st')]:
            if engine not in engines: continue
            for count in (0, reps[engine]):
                script = directory / (engine.replace(' ', '-') + '-' + str(count) + suffix)
                script.write_text(generate(case, count, original))
                engines[engine][count] = ([args.python, str(script)] if engine == 'CPython' else
                                         [str(args.gst), '--no-user-files', '-q', str(script)])
        rows = {engine: {'engine': engine, 'case': case, 'reps': reps[engine], 'samples': [],
                         'commands': commands} for engine, commands in engines.items()}
        for trial in range(args.trials + 1):
            for engine in list(engines)[::1 if trial % 2 == 0 else -1]:
                times = {}
                for count in ([0, reps[engine]] if trial % 2 else [reps[engine], 0]):
                    answer = expected(case, count).strip() if engine in ('Granite', 'Native Nim') else count
                    if case == 'queens' and engine == 'Native Nim': answer = 92 if count else 0
                    times[count] = execute(engines[engine][count], directory, f'{engine}-{trial}-{count}', 180, answer)
                if trial:
                    rows[engine]['samples'].append({'workMs': times[reps[engine]], 'baselineMs': times[0],
                        'netMsPerPass': (times[reps[engine]] - times[0]) / reps[engine]})
        for engine, row in rows.items():
            for field in ('workMs', 'baselineMs', 'netMsPerPass'):
                row['median' + field[0].upper() + field[1:]] = statistics.median(s[field] for s in row['samples'])
            if row['medianNetMsPerPass'] <= 0: raise RuntimeError('below timing resolution: ' + engine)
            report['results'].append(row)
            print(f"{case:10} {engine:14} {row['medianNetMsPerPass']:10.4f} ms/pass total {row['medianWorkMs']/1000:.3f} s/{row['reps']} passes", flush=True)
        report.setdefault('hashes', {})[case] = {p.name: sha(p) for p in directory.iterdir()
                                                if p.is_file() and p.suffix in ('.nim', '.hrd', '.py', '.st')}
        (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Results:', work / 'results.json', flush=True)


if __name__ == '__main__':
    main()
