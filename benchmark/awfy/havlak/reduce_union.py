"""Build a reduction from exact port definitions; no method renaming."""
from pathlib import Path
import re
HERE = Path(__file__).resolve().parent
text = (HERE / 'havlak.hrd').read_text()
classes = ['Vector', 'BasicBlock', 'UnionFindNode']
parts = []
for cls in classes:
    start = text.index(cls + ' :=')
    tail = text[start:]
    end = re.search(r'\n\w+ := \w+ derive:', tail[1:])
    parts.append(tail[:end.start() + 1] if end else tail)
# Vector needs the exact compatibility definitions too.
parts.insert(0, (HERE / 'compat.hrd').read_text())
parts.append('''HavlakChecks := Object derive.
HavlakChecks class>>run [
    | left right node root |
    left := BasicBlock new: 42. right := BasicBlock new: 42.
    root := UnionFindNode new. root initNode: left dfs: 1.
    node := UnionFindNode new. node initNode: right dfs: 2.
    node className println.
    node union: root.
    "direct union passed" println.
    node findSet.
    "ok" println
].
HavlakChecks run.
''')
(HERE / 'reduced_union.hrd').write_text('\n'.join(parts))
