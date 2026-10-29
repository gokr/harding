#!/usr/bin/env python3
"""Checked Richards/DeltaBlue comparisons: Harding, Granite, Cog and pinned Node source.

Cog uses a mechanical adaptation of the Harding source including its arithmetic
helpers and graph cleanup. Node runs pinned Octane source: differences are
recorded, so the Node measurements are reference context, not exact port parity.
GPL DeltaBlue sources generated under build/ retain the benchmark's license.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import urllib.request

from bench_compare import ROOT, SQUEAK_DEFAULT, execute, sha
from bench_richards import expected
from cog_benchmark_source import driver

PIN = '570ad1ccfe86e3eecba0636c8f932ac08edec517'
HASHES = {'richards': '1246a64a24b931158bf01c24640343259fa74b0226e73bad630bd1f686aa0fa7',
          'deltablue': '6c4784e82f3e8f5c18306d289653d08b17b38838f1bac16b38611d7318fa5a36'}


def node_driver(case, count, source):
    body = f'''
const run = new Function('BenchmarkSuite', 'Benchmark', 'alert',
  {json.dumps(source)} + '\\nfor (let iteration = 0; iteration < {count}; iteration++) {{ {"runRichards" if case == "richards" else "deltaBlue"}(); }}');
run(function(){{}}, function(){{}}, function(message){{throw Error(message)}});
console.log({count});
'''
    return '// Generated reference runner; source license notice follows.\n' + source.split('var ')[0] + '\n' + body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cases', nargs='*', help='richards and/or deltablue; default both')
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--mm', choices=('arc', 'orc'), default='arc')
    parser.add_argument('--cog-vm', type=Path, default=SQUEAK_DEFAULT)
    parser.add_argument('--cog-image', type=Path, default=ROOT / 'build/squeak/bench.image')
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    cases = args.cases or list(HASHES)
    if set(cases) - set(HASHES) or args.trials < 1:
        parser.error('valid cases and positive trials required')
    base = ROOT / 'build/bench-compare-classic'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    image_dir = work / 'image'
    image_dir.mkdir()
    image = image_dir / 'bench.image'
    shutil.copy2(args.cog_image, image)
    for path in [args.cog_image.with_suffix('.changes'), *args.cog_image.parent.glob('*.sources')]:
        if path.exists():
            shutil.copy2(path, image_dir / path.name)
    flags = ['nim', 'c', '-d:release', '--mm:' + args.mm, '-p:' + str(ROOT / 'external')]
    interpreter, compiler = work / 'harding', work / 'granite'
    for label, binary, source in [('interpreter', interpreter, 'src/harding/repl/harding.nim'),
                                   ('compiler', compiler, 'src/harding/compiler/granite.nim')]:
        execute(flags + ['--nimcache:' + str(work / (label + '-cache')), '-o:' + str(binary), str(ROOT / source)], work, label + '-build', 240)
    results = {'metadata': {'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'mm': args.mm, 'trials': args.trials, 'pin': PIN,
        'dirtyStatus': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'cogVm': subprocess.check_output([str(args.cog_vm), '-version'], text=True),
        'node': subprocess.check_output(['node', '--version'], text=True),
        'nim': subprocess.check_output(['nim', '--version'], text=True),
        'gcc': subprocess.check_output(['gcc', '--version'], text=True).splitlines()[0],
        'cpu': next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), ''),
        'cogImageSha256': sha(image), 'cogVmSha256': sha(args.cog_vm),
        'interpreterSha256': sha(interpreter), 'graniteSha256': sha(compiler),
        'caveats': 'Cog HBArray zero-based adapter uses OrderedCollection storage; Harding cleanup and arithmetic bit helpers retained. Node uses original reference with native bit ops and no explicit ownership cleanup; not an exact port comparison or Octane score.'}, 'results': []}
    report = work / 'results.json'
    print('Artifacts:', work, flush=True)
    for case in cases:
        directory = work / case
        directory.mkdir()
        source = directory / (case + '.hrd')
        source.write_bytes((ROOT / 'benchmark' / (case + '.hrd')).read_bytes())
        cached = ROOT / 'build' / ('octane-' + case + '.js')
        if cached.exists():
            reference = cached.read_bytes()
        else:
            with urllib.request.urlopen(f'https://raw.githubusercontent.com/chromium/octane/{PIN}/{case}.js', timeout=30) as response:
                reference = response.read()
        if hashlib.sha256(reference).hexdigest() != HASHES[case]:
            raise RuntimeError('Reference hash mismatch: ' + case)
        (directory / 'reference.js').write_bytes(reference)
        for license_path in (ROOT / 'benchmark/licenses').iterdir():
            if license_path.is_file():
                shutil.copy2(license_path, directory / license_path.name)
        binary = directory / 'program'
        execute([str(compiler), 'compile', str(source), '--dir:' + str(directory), '-o:' + str(binary)], directory, 'generate', 180)
        execute(flags + ['--nimcache:' + str(directory / 'native-cache'), '-o:' + str(binary), str(binary) + '.nim'], directory, 'native-build', 240)
        reps = {'Interpreter': 5, 'Granite': 20, 'Cog adapted': 300, 'Node reference': 300}
        engines = {
            'Interpreter': {n: [str(interpreter), str(source), '--', str(n)] for n in [0, reps['Interpreter']]},
            'Granite': {n: [str(binary), str(n)] for n in [0, reps['Granite']]},
            'Cog adapted': {}, 'Node reference': {},
        }
        output = directory / 'cog-result.txt'
        for name in ['Cog adapted', 'Node reference']:
            for count in [0, reps[name]]:
                script = directory / (('cog-' if name == 'Cog adapted' else 'node-') + str(count) + ('.st' if name == 'Cog adapted' else '.js'))
                if name == 'Cog adapted':
                    script.write_text(driver(case, count, output, source.read_text()))
                    engines[name][count] = [str(args.cog_vm), '-nodisplay', '-nosound', str(image), str(script)]
                else:
                    script.write_text(node_driver(case, count, reference.decode()))
                    engines[name][count] = ['node', str(script)]
        rows = {name: {'engine': name, 'case': case, 'reps': reps[name], 'samples': [], 'commands': commands}
                for name, commands in engines.items()}
        for trial in range(args.trials + 1):
            for name in list(engines)[::1 if trial % 2 == 0 else -1]:
                times = {}
                for count in ([0, reps[name]] if trial % 2 else [reps[name], 0]):
                    answer = expected(count, case).strip() if name in ['Interpreter', 'Granite'] else count
                    times[count] = execute(engines[name][count], directory, f'{name}-{trial}-{count}', args.timeout,
                                           answer, output if name == 'Cog adapted' else None)
                if trial:
                    rows[name]['samples'].append({'workMs': times[reps[name]], 'baselineMs': times[0],
                        'netMsPerPass': (times[reps[name]] - times[0]) / reps[name]})
        for name, row in rows.items():
            row['medianNetMsPerPass'] = statistics.median(s['netMsPerPass'] for s in row['samples'])
            row['medianWorkMs'] = statistics.median(s['workMs'] for s in row['samples'])
            row['medianBaselineMs'] = statistics.median(s['baselineMs'] for s in row['samples'])
            if row['medianNetMsPerPass'] <= 0:
                raise RuntimeError('Below timing resolution: ' + name)
            results['results'].append(row)
            print(f"{case:10} {name:16} {row['medianNetMsPerPass']:10.4f} ms/pass ({reps[name]} reps)", flush=True)
        results.setdefault('hashes', {})[case] = {p.name: sha(p) for p in directory.iterdir() if p.is_file() and p.suffix in ['.hrd', '.nim', '.js', '.st']}
        report.write_text(json.dumps(results, indent=2) + '\n')
    print('Results:', report, flush=True)


if __name__ == '__main__':
    main()
