"""Load pinned upstream AWFY Smalltalk through its own SOM loader in Squeak.

Only image compatibility is supplied here: upstream's own loader
(`SomLoader-Compiler.st`) reads its own `.som` sources, and every workload
method, fixture and SOM collection is loaded unchanged. Deliberately different
from the Harding ports in `benchmark/awfy/<case>/` — those are separate ports,
and Json's upstream benchmark verifies its own fixture rather than running the
port's extra parser checks. Timings from this adapter must therefore be reported
as AWFY-upstream workloads, not as the Harding ports run on Cog.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / 'benchmark/awfy/smalltalk/upstream'
CASES = ('bounce', 'json', 'havlak')
REVISION = '74306fec151070fd07157cefeacf19e7e0bcdc89'
CLASSES = {'bounce': 'Bounce', 'json': 'Json', 'havlak': 'Havlak'}


def provenance():
    """The vendored manifest, re-verified against every file on disk."""
    manifest = json.loads((UPSTREAM / 'provenance.json').read_text())
    if manifest['commit'] != REVISION:
        raise ValueError('unexpected AWFY revision')
    for entry in manifest['files']:
        path = UPSTREAM / entry['path']
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('AWFY source hash mismatch: ' + entry['path'])
    return manifest


def st_string(value):
    return "'" + str(value).replace("'", "''") + "'"


def source_files(case):
    """The upstream units one workload needs, in load order."""
    if case not in CASES:
        raise ValueError('unsupported AWFY workload: ' + case)
    names = ['Benchmark']
    if case == 'bounce':
        names += ['Ball', 'SomRandom', 'Bounce']
    else:
        # Core is shared by Json and Havlak (SOM dictionaries/sets and Vector).
        names += [p.stem for p in sorted(UPSTREAM.glob('*.som'))
                  if p.name not in ('Ball', 'SomRandom', 'Bounce', 'Benchmark')]
    return [UPSTREAM / (name + '.som') for name in names]


def driver(case, repetitions, output):
    """A checked Squeak program: load upstream, run it N times, verify each."""
    if repetitions < 0:
        raise ValueError('negative repetition count')
    if case not in CLASSES:
        raise ValueError('unsupported AWFY workload: ' + case)
    files = source_files(case)
    # Upstream's own image-compatibility shims (build-image-squeak.st); no
    # generated VM or benchmark source is patched, and the image is never saved.
    bootstrap = """Utilities authorInitials: 'AWFY'.
Behavior compile: 'subclass: a instanceVariableNames: b classVariableNames: c package: d
 ^ self subclass: a instanceVariableNames: b classVariableNames: c poolDictionaries: '''' category: d'.
Character compile: 'canBeGlobalVarInitial ^ self isLetter'.
SmallInteger methodDict at: #'&' put: (SmallInteger >> #bitAnd:).
SmallInteger methodDict at: #'%' put: (SmallInteger >> #\\\\).
"""
    bootstrap += '(FileStream fileNamed: ' + st_string(UPSTREAM / 'SomLoader-Compiler.st') + ') fileIn.\n'
    # Replace only directory-walking and stream construction: Squeak 6.1 has no
    # FileReference and SomParser's TextStream class is Pharo-specific. The
    # loader's parser, class generation and method installation stay upstream's.
    selectors = '''SomParser class compile: 'textStreamCls ^ ReadWriteStream'.
SomCompiler compile: 'sourceOfClassFile: path
 ^ (FileStream readOnlyFileNamed: path) contentsOfEntireFile readStream'.
SomLoader compile: 'loadFiles: paths
 classDefinitions := paths collect: [:path | SomCompiler new load: path]'.
'''
    load = '| loader | loader := SomLoader new.\n'
    load += 'loader loadFiles: #(' + ' '.join(st_string(p) for p in files) + ').\n'
    load += '''loader classDefinitions do: [:definition | | existing |
 existing := Smalltalk at: definition theName asSymbol ifAbsent: [nil].
 existing ifNotNil: [existing rename: ('AWFYOriginal', definition theName) asSymbol]].
loader createClasses; createMethods.
'''
    if case == 'havlak':
        # Havlak's own verifier ties the loop/node counts to innerIterations = 1,
        # which is upstream's full-size checked graph.
        check = "(solver innerBenchmarkLoop: 1) ifFalse: [self error: 'Wrong Havlak result']"
    else:
        check = ("answer := solver benchmark. "
                 "(solver verifyResult: answer) ifFalse: [self error: 'Wrong AWFY result']")
    work = f'''| solver answer done stream |
solver := {CLASSES[case]} new. done := 0.
{repetitions} timesRepeat: [
{check}.
done := done + 1].
stream := FileStream forceNewFileNamed: {st_string(output)}.
stream nextPutAll: done printString; close.
Smalltalk snapshot: false andQuit: true'''
    load += 'Compiler evaluate: ' + st_string(work) + '.\n'
    # A GUI image can open an invisible notifier on an unhandled error and never
    # exit, so record an explicit marker the host rejects even at exit status 0.
    return '[\n' + bootstrap + 'Compiler evaluate: ' + st_string(selectors) + '.\n' + \
        'Compiler evaluate: ' + st_string(load) + '.\n' + '''] on: Error do: [:ex | | stream |
stream := FileStream forceNewFileNamed: ''' + st_string(output) + '''.
stream nextPutAll: 'ERROR: ', ex printString; close.
Smalltalk snapshot: false andQuit: true].
'''
