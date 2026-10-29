#!/usr/bin/env python3
"""Checked comparisons of current Harding/Granite, Cog, and host languages.

Builds precede timing. Every workload and zero-work observation is checked.
Use an idle host; these are paired process wall times, not VM-internal scores.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import statistics
import subprocess
import tempfile
import time

from bench_objects import NIM_SOURCE
from bench_sieve_languages import SOURCES

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {'sieve': 669, 'queens': 92, 'towers': 8191}
SQUEAK_DEFAULT = Path('/home/gokr/squeak/Squeak6.0-22148-64bit-202312181441-Linux-x64/bin/squeak')

SQUEAK_OBJECTS = r'''
Object subclass: #HBQueenPlacement instanceVariableNames: 'row column previous' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.
HBQueenPlacement compile: 'setupRow: r column: c previous: p row := r. column := c. previous := p. ^self'.
HBQueenPlacement compile: 'row ^row'.
HBQueenPlacement compile: 'column ^column'.
HBQueenPlacement compile: 'previous ^previous'.
Object subclass: #HBQueens instanceVariableNames: '' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.
HBQueens compile: 'canPlaceRow: r column: c after: head
  | current distance delta valid |
  current := head. valid := true.
  [current notNil] whileTrue: [
    distance := r - current row. delta := c - current column.
    ((delta = 0) | (delta = distance) | (delta = (0 - distance))) ifTrue: [valid := false].
    current := current previous]. ^valid'.
HBQueens compile: 'searchRow: r after: head
  | column total placement |
  total := 0.
  r = 8 ifTrue: [total := 1] ifFalse: [
    column := 0.
    [column < 8] whileTrue: [
      (self canPlaceRow: r column: column after: head) ifTrue: [
        placement := HBQueenPlacement new setupRow: r column: column previous: head.
        total := total + (self searchRow: r + 1 after: placement)].
      column := column + 1]]. ^total'.
HBQueens compile: 'benchmark ^self searchRow: 0 after: nil'.
Object subclass: #HBDisk instanceVariableNames: 'diskSize nextDisk' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.
HBDisk compile: 'setup: size diskSize := size. nextDisk := nil. ^self'.
HBDisk compile: 'diskSize ^diskSize'.
HBDisk compile: 'nextDisk ^nextDisk'.
HBDisk compile: 'nextDisk: disk nextDisk := disk'.
Object subclass: #HBPeg instanceVariableNames: 'heldDisk' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.
HBPeg compile: 'heldDisk ^heldDisk'.
HBPeg compile: 'push: disk
  heldDisk notNil ifTrue: [disk diskSize < heldDisk diskSize ifFalse: [self error: ''Illegal disk move'']].
  disk nextDisk: heldDisk. heldDisk := disk. ^self'.
HBPeg compile: 'pop | disk |
  disk := heldDisk. disk isNil ifTrue: [self error: ''Empty source peg''].
  heldDisk := disk nextDisk. disk nextDisk: nil. ^disk'.
HBPeg compile: 'verify: count | disk expected valid |
  disk := heldDisk. expected := 1. valid := true.
  [disk notNil] whileTrue: [disk diskSize = expected ifFalse: [valid := false].
    expected := expected + 1. disk := disk nextDisk].
  ^valid ifTrue: [expected = (count + 1)] ifFalse: [false]'.
Object subclass: #HBTowers instanceVariableNames: 'moves' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.
HBTowers compile: 'move: count from: source to: destination using: helper
  count > 0 ifTrue: [
    self move: count - 1 from: source to: helper using: destination.
    destination push: source pop. moves := moves + 1.
    self move: count - 1 from: helper to: destination using: source]. ^self'.
HBTowers compile: 'benchmark | source destination helper size |
  moves := 0. source := HBPeg new. destination := HBPeg new. helper := HBPeg new.
  size := 13.
  [size > 0] whileTrue: [source push: (HBDisk new setup: size). size := size - 1].
  self move: 13 from: source to: destination using: helper.
  (destination verify: 13) ifFalse: [self error: ''Invalid destination peg''].
  source heldDisk notNil ifTrue: [self error: ''Nonempty source peg''].
  helper heldDisk notNil ifTrue: [self error: ''Nonempty helper peg'']. ^moves'.
'''

SQUEAK_SIEVE = r'''
| answer repetition stream |
answer := 0. repetition := 0.
[repetition < REPS] whileTrue: [
  | primeCount i d isPrime |
  primeCount := 0. i := 2.
  [i <= 5000] whileTrue: [
    isPrime := true. d := 2.
    [d * d <= i] whileTrue: [
      (i \\ d) = 0 ifTrue: [isPrime := false. d := i]. d := d + 1].
    isPrime ifTrue: [primeCount := primeCount + 1]. i := i + 1].
  answer := primeCount.
  answer = 669 ifFalse: [self error: 'Incorrect sieve result'].
  repetition := repetition + 1].
stream := FileStream forceNewFileNamed: 'OUTPATH'.
stream nextPutAll: answer printString; close.
Smalltalk snapshot: false andQuit: true.
'''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def execute(command, directory, label, timeout, expected=None, result_file=None):
    if result_file:
        result_file.unlink(missing_ok=True)
    start = time.perf_counter_ns()
    environment = dict(os.environ, HARDING_HOME=str(ROOT))
    with subprocess.Popen(command, cwd=directory, env=environment, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, start_new_session=True) as child:
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            stdout, stderr = child.communicate()
            (directory / (label + '.stdout')).write_text(stdout)
            (directory / (label + '.stderr')).write_text(stderr + '\nTIMEOUT\n')
            raise RuntimeError(f'Timeout: {label}; {directory}')
    elapsed = (time.perf_counter_ns() - start) / 1e6
    (directory / (label + '.stdout')).write_text(stdout)
    (directory / (label + '.stderr')).write_text(stderr)
    if child.returncode:
        raise RuntimeError(f'Exit {child.returncode}: {label}; {directory}')
    if expected is not None:
        observed = result_file.read_text() if result_file and result_file.exists() else stdout
        if observed.strip() != str(expected) or (stderr and not result_file):
            raise RuntimeError(f'Wrong output: {label}: {observed!r}, {stderr!r}; {directory}')
    return elapsed


def hrd(case, count):
    if case == 'sieve':
        return SOURCES['sieve_template.hrd'].replace('{REPS}', str(count))
    definitions = (ROOT / f'benchmark/{case}.hrd').read_text().split('# Benchmark driver')[0]
    solver = 'Queens' if case == 'queens' else 'Towers'
    return definitions + f'''
solver := {solver} new.
answer := 0.
{count} timesRepeat: [
  answer := solver benchmark.
  (answer = {EXPECTED[case]}) ifFalse: [Error signal: "Wrong benchmark result"]
].
answer println.
'''


def cog(case, count, output):
    if case == 'sieve':
        text = SQUEAK_SIEVE
    else:
        solver = 'HBQueens' if case == 'queens' else 'HBTowers'
        # Definitions run via Compiler evaluate: so newly created class bindings
        # are visible when the driver is compiled after them.
        statements = []
        quoted = False
        start = 0
        index = 0
        while index < len(SQUEAK_OBJECTS):
            character = SQUEAK_OBJECTS[index]
            if character == "'":
                if quoted and index + 1 < len(SQUEAK_OBJECTS) and SQUEAK_OBJECTS[index + 1] == "'":
                    index += 2
                    continue
                quoted = not quoted
            if character == '.' and not quoted:
                statements.append(SQUEAK_OBJECTS[start:index])
                start = index + 1
            index += 1
        definitions = '\n'.join("Compiler evaluate: '" + statement.strip().replace("'", "''") + "'."
                                for statement in statements if statement.strip())
        driver = f'''| answer solver stream |
answer := 0. solver := {solver} new.
REPS timesRepeat: [answer := solver benchmark.
  answer = {EXPECTED[case]} ifFalse: [self error: 'Incorrect object result']].
stream := FileStream forceNewFileNamed: 'OUTPATH'.
stream nextPutAll: answer printString; close.
Smalltalk snapshot: false andQuit: true.'''
        return "Utilities authorInitials: 'HB'.\n" + definitions + "\nCompiler evaluate: '" + driver.replace('REPS', str(count)).replace('OUTPATH', str(output).replace("'", "''")).replace("'", "''") + "'.\n"
    return text.replace('REPS', str(count)).replace('OUTPATH', str(output).replace("'", "''"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cases', nargs='*', help='sieve, queens, towers (default all)')
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--mm', choices=('arc', 'orc'), default='arc')
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--cog-vm', type=Path, default=SQUEAK_DEFAULT)
    parser.add_argument('--cog-image', type=Path, default=ROOT / 'build/squeak/bench.image')
    args = parser.parse_args()
    cases = args.cases or list(EXPECTED)
    if set(cases) - set(EXPECTED) or args.trials < 1 or args.timeout < 1:
        parser.error('valid cases, positive trials and timeout required')
    if not args.cog_vm.is_file() or not args.cog_image.is_file():
        parser.error('provide --cog-vm and --cog-image')
    base = ROOT / 'build/bench-compare'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    image_dir = work / 'image'
    image_dir.mkdir()
    image = image_dir / 'bench.image'
    shutil.copy2(args.cog_image, image)
    changes = args.cog_image.with_suffix('.changes')
    if changes.exists():
        shutil.copy2(changes, image.with_suffix('.changes'))
    for sources in args.cog_image.parent.glob('*.sources'):
        shutil.copy2(sources, image_dir / sources.name)
    interpreter, granite = work / 'harding', work / 'granite'
    flags = ['nim', 'c', '-d:release', '--mm:' + args.mm, '-p:' + str(ROOT / 'external')]
    for label, target, source in [('interpreter', interpreter, 'src/harding/repl/harding.nim'),
                                   ('compiler', granite, 'src/harding/compiler/granite.nim')]:
        execute(flags + ['--nimcache:' + str(work / (label + '-cache')), '-o:' + str(target),
                         str(ROOT / source)], work, label + '-build', 240)
    versions = {}
    for name, command in {'nim': ['nim', '--version'], 'gcc': ['gcc', '--version'],
                          'go': ['go', 'version'], 'node': ['node', '--version'],
                          'ruby': ['ruby', '--version'], 'python': ['python3', '--version'],
                          'cog': [str(args.cog_vm), '-version']}.items():
        value = subprocess.run(command, capture_output=True, text=True, timeout=15)
        versions[name] = value.stdout + value.stderr
    results = {'metadata': {'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'dirtyStatus': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'mm': args.mm, 'trials': args.trials, 'platform': platform.platform(),
        'versions': versions, 'cogImageSha256': sha(image), 'cogVmSha256': sha(args.cog_vm),
        'interpreterSha256': sha(interpreter), 'graniteSha256': sha(granite),
        'method': 'fresh processes, checked warm-up, paired zero-work baseline; alternate engine and work/baseline order',
        'cpu': next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), '')}, 'results': []}
    report = work / 'results.json'
    report.write_text(json.dumps(results, indent=2) + '\n')
    print('Artifacts:', work, flush=True)
    for case in cases:
        directory = work / case
        directory.mkdir()
        reps = {'Interpreter': 3, 'Granite': 20, 'Nim': 1000, 'Cog': 1000}
        if case == 'sieve':
            reps = {'Interpreter': 10, 'Granite': 500, 'Nim': 10000, 'Cog': 10000,
                    'C': 10000, 'Go': 10000, 'Node': 10000, 'Ruby': 1000, 'Python': 1000}
        engines = {}
        for name in ['Interpreter', 'Granite']:
            commands = {}
            for count in [0, reps[name]]:
                source = directory / f'{name}-{count}.hrd'
                source.write_text(hrd(case, count))
                if name == 'Granite':
                    binary = directory / f'program{count}'
                    execute([str(granite), 'compile', str(source), '--dir:' + str(directory), '-o:' + str(binary)], directory, f'granite-{count}-generate', 180)
                    execute(flags + ['--nimcache:' + str(directory / f'native-cache-{count}'), '-o:' + str(binary), str(binary) + '.nim'], directory, f'granite-{count}-build', 240)
                    commands[count] = [str(binary)]
                else:
                    commands[count] = [str(interpreter), str(source)]
            engines[name] = commands
        nim_source = directory / 'reference.nim'
        nim_source.write_text(SOURCES['sieve.nim'] if case == 'sieve' else NIM_SOURCE)
        nim_binary = directory / 'reference'
        execute(flags + ['--nimcache:' + str(directory / 'nim-cache'), '-d:' + case, '-o:' + str(nim_binary), str(nim_source)], directory, 'nim-build', 180)
        engines['Nim'] = {n: [str(nim_binary), str(n)] for n in [0, reps['Nim']]}
        output = directory / 'cog-result.txt'
        engines['Cog'] = {}
        for count in [0, reps['Cog']]:
            script = directory / f'cog-{count}.st'
            script.write_text(cog(case, count, output))
            engines['Cog'][count] = [str(args.cog_vm), '-nodisplay', '-nosound', str(image), str(script)]
        if case == 'sieve':
            for extension in ['c', 'go', 'js', 'rb', 'py']:
                (directory / ('sieve.' + extension)).write_text(SOURCES['sieve.' + extension])
            execute(['gcc', '-O3', '-o', str(directory / 'sieve_c'), str(directory / 'sieve.c')], directory, 'c-build', 60)
            execute(['go', 'build', '-o', str(directory / 'sieve_go'), str(directory / 'sieve.go')], directory, 'go-build', 120)
            for name, command in {'C': [str(directory / 'sieve_c')], 'Go': [str(directory / 'sieve_go')],
                'Node': ['node', str(directory / 'sieve.js')], 'Ruby': ['ruby', str(directory / 'sieve.rb')],
                'Python': ['python3', str(directory / 'sieve.py')]}.items():
                engines[name] = {n: command + [str(n)] for n in [0, reps[name]]}
        # Sources and binary hashes identify exactly what was measured.
        rows = {name: {'case': case, 'engine': name, 'reps': reps[name], 'samples': [],
                       'commands': commands} for name, commands in engines.items()}
        for trial in range(args.trials + 1):
            for name in list(engines)[::1 if trial % 2 == 0 else -1]:
                times = {}
                for count in ([0, reps[name]] if trial % 2 else [reps[name], 0]):
                    times[count] = execute(engines[name][count], directory, f'{name}-{trial}-{count}',
                        args.timeout, EXPECTED[case] if count else 0, output if name == 'Cog' else None)
                if trial:
                    rows[name]['samples'].append({'workMs': times[reps[name]], 'baselineMs': times[0],
                        'netMsPerPass': (times[reps[name]] - times[0]) / reps[name]})
        for name, row in rows.items():
            row['medianWorkMs'] = statistics.median(s['workMs'] for s in row['samples'])
            row['medianBaselineMs'] = statistics.median(s['baselineMs'] for s in row['samples'])
            row['medianNetMsPerPass'] = statistics.median(s['netMsPerPass'] for s in row['samples'])
            if row['medianNetMsPerPass'] <= 0:
                raise RuntimeError('Below timing resolution: ' + name)
            results['results'].append(row)
            print(f"{case:8} {name:12} {row['medianNetMsPerPass']:10.4f} ms/pass ({reps[name]} reps)", flush=True)
        results.setdefault('artifactHashes', {})[case] = {p.name: sha(p) for p in directory.iterdir() if p.is_file() and p.suffix in ['.hrd', '.st', '.nim', '.c', '.go', '.js', '.rb', '.py']}
        report.write_text(json.dumps(results, indent=2) + '\n')
    print('Results:', report, flush=True)


if __name__ == '__main__':
    main()
