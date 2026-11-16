"""Link inventory for docs/.

Walks every Markdown file under docs/ recursively, plus the root documents and
the website content, and reports inbound links, documents with no inbound link,
and links whose target does not exist. Relative links are resolved against the
containing file; links inside fenced code blocks are ignored. External URLs,
absolute paths and pure fragments are skipped.
"""

import collections
import os
import re

LINK = re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
CODE = re.compile(r'`[^`]*`')
ROOT_DOCS = ('README.md', 'AGENTS.md', 'PLAN.md', 'CHANGELOG.md',
             'CONTRIBUTING.md', 'DOCS_CONSOLIDATION_PLAN.md')
SKIP_DIRS = {'.git', 'build', 'external', 'nimcache', 'node_modules',
             'worktrees', '__pycache__', 'vscode-harding', 'website/dist'}


def markdown_files():
    found = []
    for root, dirs, files in os.walk('.'):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if name.endswith('.md'):
                found.append(os.path.normpath(os.path.join(root, name)))
    for name in ROOT_DOCS:
        if os.path.exists(name):
            found.append(os.path.normpath(name))
    return sorted(set(found))


def links_in(path):
    inside_fence = False
    for number, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
        if line.lstrip().startswith('```'):
            inside_fence = not inside_fence
            continue
        if inside_fence:
            continue
        line = CODE.sub('', line)
        for match in LINK.finditer(line):
            target = match.group(1)
            if re.match(r'^[a-z][a-z0-9+.-]*:', target) or target.startswith(('#', '/')):
                continue
            target = target.split('#')[0]
            if target:
                yield number, target


def main():
    files = markdown_files()
    known = set(files)
    inbound = collections.defaultdict(set)
    broken = []

    for path in files:
        for number, target in links_in(path):
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if os.path.exists(resolved):
                if resolved in known and resolved != path:
                    inbound[resolved].add(path)
            else:
                broken.append((path, number, target))

    print('=== NO INBOUND LINK ===')
    for path in files:
        if path.startswith('docs/') and path not in inbound:
            print('  ', path)

    print('\n=== BROKEN LINKS ===')
    for path, number, target in broken:
        print(f'  {path}:{number} -> {target}')

    print(f'\n{len(files)} files, {len(broken)} broken links')


if __name__ == '__main__':
    main()
