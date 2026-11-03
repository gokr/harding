#!/usr/bin/env python3
"""Compare stock Cog and Oil on the same disposable Squeak image and workloads.

Two workload families are supported and must not be confused in a report:

* `richards`, `deltablue`, `queens` — the mechanically adapted Harding programs
  under `benchmark/`.
* `bounce`, `json`, `havlak` — AWFY upstream's own SOM sources, loaded by its own
  loader (`scripts/awfy_cog.py`). These are not the Harding AWFY ports, and
  upstream Json verifies its fixture rather than running the ports' extra
  parser checks.

Optional image add-ons are a separate variant; they never modify the input image
and apply to the benchmark/ workloads only.
"""
import argparse
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile

from bench_compare import ROOT, cog, execute, sha
from cog_benchmark_source import driver
import awfy_cog

CASES = ('richards', 'deltablue', 'queens') + awfy_cog.CASES

# AWFY workloads differ by orders of magnitude, so one global repetition count
# either measures startup for Havlak or skips too little work for Bounce.
# Per-pass timing makes the counts comparable; --repetitions overrides them all.
# Havlak repeats upstream's checked full-size graph (three passes) rather than
# timing a single 0.7 s run, whose per-pass figure is mostly noise.
DEFAULT_REPETITIONS = {'bounce': 2000, 'json': 200, 'havlak': 3}


def st_string(text):
    return "'" + str(text).replace("'", "''") + "'"


def checked_driver(case, repetitions, output, source, addons=()):
    if repetitions < 0:
        raise ValueError('negative repetition count')
    if case not in CASES:
        raise ValueError('unsupported workload: ' + case)
    if case in awfy_cog.CASES:
        if addons:
            raise ValueError('AWFY add-on variants are not supported')
        return awfy_cog.driver(case, repetitions, output)
    code = (cog(case, repetitions, output) if case == 'queens' else
            driver(case, repetitions, output, source))
    prefix = ''.join(f'(FileStream fileNamed: {st_string(path)}) fileIn.\n' for path in addons)
    # Squeak may open an invisible notifier on an unhandled error and never exit.
    # Record an explicit failure marker; the host checks output AND exit status.
    return '[\n' + prefix + code + '''
] on: Error do: [:ex | | stream |
stream := FileStream forceNewFileNamed: ''' + st_string(output) + '''.
stream nextPutAll: 'ERROR: ', ex printString; close.
Smalltalk snapshot: false andQuit: true].
'''


def vm_path(product):
    matches = list((product / 'lib/squeak').glob('*/squeak'))
    if len(matches) != 1:
        raise ValueError('Provide an explicit VM path; product missing or ambiguous: ' + str(product))
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cog-vm', type=Path)
    parser.add_argument('--oil-vm', type=Path)
    parser.add_argument('--image', type=Path,
                        default=ROOT / 'build/osvm/image/Squeak6.1-23976-64bit.image')
    parser.add_argument('--addons', nargs='+', type=Path, default=[],
                        help='optional file-ins for a separately labelled Oil+add-ons variant')
    parser.add_argument('cases', nargs='*',
                        help='richards deltablue queens (default) or bounce json havlak (AWFY upstream)')
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--repetitions', type=int,
                        help='passes per measurement; default 3000, or the AWFY per-case default')
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    if args.trials < 3:
        parser.error('at least three trials required')
    if args.repetitions is not None and args.repetitions < 1:
        parser.error('positive repetitions required')
    cases = args.cases or ('richards', 'deltablue', 'queens')
    if set(cases) - set(CASES): parser.error('unknown workload')
    if args.addons and set(cases) & set(awfy_cog.CASES):
        parser.error('AWFY add-on variants are not supported')
    if set(cases) & set(awfy_cog.CASES):
        awfy_cog.provenance()
    products = ROOT / 'build/osvm/repo/products'
    cog_vm = (args.cog_vm or vm_path(products / 'sqcogspur64linuxht')).resolve()
    oil_vm = (args.oil_vm or vm_path(products / 'sqoilspur64linuxht')).resolve()
    image = args.image.resolve()
    addons = [p.resolve() for p in args.addons]
    for path in [cog_vm, oil_vm, image, *addons]:
        if not path.is_file(): parser.error('missing input: ' + str(path))
    base = ROOT / 'build/bench-compare-oil'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    variants = {'Cog': (cog_vm, []), 'Oil': (oil_vm, [])}
    if addons: variants['Oil+add-ons'] = (oil_vm, addons)
    versions = {}
    for name, (vm, _) in variants.items():
        result = subprocess.run([str(vm), '-version'], capture_output=True, text=True,
                                check=True, timeout=20)
        versions[name] = {'path': str(vm), 'sha256': sha(vm),
                          'version': result.stdout + result.stderr}
    source_hashes = {str(p): sha(p) for p in [image, *addons]}
    counts = {case: args.repetitions or DEFAULT_REPETITIONS.get(case, 3000) for case in cases}
    report = {'metadata': {'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'],
        cwd=ROOT, text=True).strip(), 'versions': versions, 'inputHashes': source_hashes,
        'trials': args.trials, 'repetitions': counts,
        'method': 'fresh processes; discarded warm-up; alternating engines and work/baseline order; checked output; median paired difference',
        'cpu': next(line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
                    if line.startswith('model name'))}, 'status': 'running', 'results': []}
    if set(cases) & set(awfy_cog.CASES):
        report['metadata']['awfy'] = awfy_cog.provenance()
        report['metadata']['awfyJsonWorkload'] = 'upstream fixture parse and verifier; excludes Harding JsonChecks'
    report_path = work / 'results.json'
    def save_report():
        report_path.write_text(json.dumps(report, indent=2) + '\n')
    save_report()
    print('Artifacts:', work, flush=True)
    images = {}
    for name in variants:
        directory = work / name
        directory.mkdir()
        images[name] = directory / 'bench.image'
        shutil.copy2(image, images[name])
        if image.with_suffix('.changes').exists():
            shutil.copy2(image.with_suffix('.changes'), directory / 'bench.changes')
        for path in image.parent.glob('*.sources'): shutil.copy2(path, directory / path.name)
    for case in cases:
        directory = work / case
        directory.mkdir()
        source = '' if case in awfy_cog.CASES else (ROOT / 'benchmark' / (case + '.hrd')).read_text()
        if source:
            (directory / (case + '.hrd')).write_text(source)
        for license_path in (ROOT / 'benchmark/licenses').iterdir():
            if license_path.is_file(): shutil.copy2(license_path, directory / license_path.name)
        output = directory / 'result.txt'
        commands = {}
        for name, (vm, file_ins) in variants.items():
            commands[name] = {}
            for count in [0, counts[case]]:
                script = directory / (name + '-' + str(count) + '.st')
                script.write_text(checked_driver(case, count, output, source, file_ins))
                commands[name][count] = [str(vm), '-nodisplay', '-nosound', str(images[name]), str(script)]
        report.setdefault('sourceHashes', {})[case] = {p.name: sha(p) for p in directory.iterdir()
                                                      if p.suffix in ('.st', '.hrd')}
        save_report()
        samples = {name: [] for name in variants}
        reps = counts[case]
        for trial in range(args.trials + 1):
            for name in list(variants)[::1 if trial % 2 else -1]:
                times = {}
                for count in ([0, reps] if trial % 2 else [reps, 0]):
                    answer = (92 if count else 0) if case == 'queens' else count
                    try:
                        times[count] = execute(commands[name][count], directory,
                            f'{name}-{trial}-{count}', args.timeout, answer, output)
                    except RuntimeError as failure:
                        report['status'] = 'failed'
                        report['failure'] = {'case': case, 'engine': name, 'trial': trial,
                            'repetitions': count, 'command': commands[name][count],
                            'error': str(failure),
                            'observed': output.read_text() if output.exists() else None}
                        save_report()
                        raise
                if trial:
                    samples[name].append({'workMs': times[reps], 'baselineMs': times[0],
                        'netMsPerPass': (times[reps] - times[0]) / reps})
        for name in variants:
            row = {'case': case, 'engine': name, 'reps': reps,
                   'commands': commands[name], 'samples': samples[name]}
            for field in ['workMs', 'baselineMs', 'netMsPerPass']:
                row['median' + field[0].upper() + field[1:]] = statistics.median(s[field] for s in samples[name])
            if row['medianNetMsPerPass'] <= 0: raise RuntimeError('below timing resolution: ' + name)
            report['results'].append(row)
            print(f"{case:10} {name:13} {row['medianNetMsPerPass']:.4f} ms/pass; total {row['medianWorkMs']/1000:.3f}s", flush=True)
        save_report()
    for path, digest in source_hashes.items():
        if sha(Path(path)) != digest: raise RuntimeError('Input changed: ' + path)
    report['status'] = 'passed'
    save_report()
    print('Results:', report_path, flush=True)


if __name__ == '__main__':
    main()
