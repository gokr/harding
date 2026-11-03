"""Reproduce the mechanical SOM syntax adaptation from the pinned checkout.
Run: python3 benchmark/awfy/havlak/port.py build/awfy-havlak/upstream
The checked-in .hrd is executable; this script needs no third-party packages.
"""
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
PIN = '74306fec151070fd07157cefeacf19e7e0bcdc89'
CORE = ['Vector', 'DictEntry', 'DictIdEntry', 'SomDictionary',
        'SomIdentityDictionary', 'SomSet', 'SomIdentitySet']
HAVLAK = ['BasicBlock', 'BasicBlockEdge', 'ControlFlowGraph', 'SimpleLoop',
          'LoopStructureGraph', 'UnionFindNode', 'HavlakLoopFinder', 'LoopTesterApp', 'Havlak']

def adapt(source):
    notices = []
    def comment(match):
        notices.append(match.group()[1:-1])
        return ' '
    text = re.sub(r'"[^"]*"', comment, source, flags=re.S)
    text = re.sub(r'\b(\w+)_\b', r'\1State', text)
    text = text.replace('Unvisited', 'unvisited').replace('MaxNonBackPreds', 'maxNonBackPreds')
    match = re.search(r'(\w+)\s*=\s*(\w+)?\s*\(', text)
    assert match is not None
    name, parent = match[1], match[2] or 'Object'
    if parent == 'Benchmark':
        parent = 'Object'
    text = text[match.end():].strip()[:-1].strip()
    slots = ''
    if text.startswith('|'):
        _, slots, text = text.split('|', 2)
    output = '\n'.join('# ' + line for line in notices[0].strip().splitlines()) + '\n'
    output += f'{name} := {parent} derive: #(' + ', '.join(slots.split()) + ').\n'
    class_side = False
    while text.strip():
        text = text.lstrip()
        if text.startswith('----'):
            text = re.sub(r'^-+', '', text)
            class_side = True
            continue
        signature, text = re.split(r'\s*=\s*\(', text, maxsplit=1)
        depth, end = 1, 0
        quoted = False
        while depth:
            ch = text[end]
            if ch == "'": quoted = not quoted
            if not quoted:
                if ch == '(': depth += 1
                if ch == ')': depth -= 1
            end += 1
        body, text = text[:end-1].strip(), text[end:]
        # Unused Vector sorting depends on SOM's defaultSort; not part of Havlak.
        if name == 'Vector' and signature.strip().startswith('sort:'):
            continue
        if name == 'SomIdentityDictionary' and signature.strip() == 'new: size':
            # Upstream has an infinitely recursive unused constructor. Inherit instead.
            continue
        body = re.sub(r"'([^']*)'", lambda m: '"' + m[1] + '"', body)
        body = re.sub(r'\bArray\b', 'HavlakArray', body)
        body = re.sub(r'ifNotNil:\s*\[', 'ifNotNil: [:ignored |', body)
        # Keep ~= for ordinary object inequality (Object does not define <>).
        body = body.replace('(w <= v) && (v <= (last at: w))', '(w <= v) and: [v <= (last at: w)]')
        body = body.replace('size downTo: 1 do:', 'size to: 1 by: (0 - 1) do:')
        body = body.replace('hash bitXor: (hash >>> 16)', 'HavlakBits xor: hash with: (hash // 65536)')
        body = body.replace('((buckets length - 1) & hash)', '(hash \\\\ buckets length)')
        body = body.replace('(current hash & (buckets length - 1))', '(current hash \\\\ buckets length)')
        body = body.replace('(current hash & oldStorage length)', '(HavlakBits and: current hash with: oldStorage length)')
        # SOM + concatenates strings; Harding uses &.
        if name == 'Havlak':
            body = body.replace(' + ', ' & ')
        body = body.rstrip().rstrip('.')
        output += f'{name}' + (' class' if class_side else '') + '>>' + signature.strip() + ' [\n' + body + '.\n    ^self\n].\n'
    return output

if __name__ == '__main__':
    upstream = Path(sys.argv[1]).resolve()
    import subprocess
    assert subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip() == PIN
    parts = ['# SOM Havlak port; see README.md for provenance and adaptation details.\n',
             (HERE / 'compat.hrd').read_text()]
    for directory, classes in [('Core', CORE), ('Havlak', HAVLAK)]:
        for cls in classes:
            parts.append(adapt((upstream / 'benchmarks/SOM' / directory / (cls + '.som')).read_text()))
    (HERE / 'havlak.hrd').write_text('\n'.join(parts))
    licenses = HERE / 'upstream'
    licenses.mkdir(exist_ok=True)
    for directory, classes in [('Core', CORE), ('Havlak', HAVLAK)]:
        for cls in classes:
            (licenses / (cls + '.som')).write_bytes((upstream / 'benchmarks/SOM' / directory / (cls + '.som')).read_bytes())
    for filename in ['AUTORS.md', 'LICENSE.md']:
        if (upstream / filename).exists():
            (licenses / filename).write_bytes((upstream / filename).read_bytes())
