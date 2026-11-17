#!/usr/bin/env python3
"""Inventory Markdown code fences and run explicitly annotated Harding examples.

This executes repository code, not a sandbox. Only run trusted documentation.
"""
import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})(.*)$')
HEADER = re.compile(r'^\s*(harding|smalltalk)\s+test=([a-zA-Z0-9_-]+)\s+stdout=("(?:[^"\\]|\\.)*")\s*$')


@dataclass(frozen=True)
class Fence:
    path: Path
    line: int
    info: str
    body: str


def fences(path):
    lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
    index = 0
    while index < len(lines):
        match = FENCE.match(lines[index].rstrip('\r\n'))
        if not match:
            index += 1
            continue
        marker, info = match.groups()
        start = index + 1
        index += 1
        body = []
        closing = re.compile(r'^ {0,3}' + re.escape(marker[0]) + '{' + str(len(marker)) + r',}\s*$')
        while index < len(lines) and not closing.match(lines[index].rstrip('\r\n')):
            body.append(lines[index])
            index += 1
        if index == len(lines):
            raise ValueError(f'{path}:{start}: unclosed fence')
        yield Fence(path, start, info.strip(), ''.join(body))
        index += 1


def command(args, cwd, timeout):
    env = os.environ.copy()
    env['HARDING_HOME'] = str(ROOT)
    process = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    try:
        out, err = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise RuntimeError(f'timed out: {args[0]}') from None
    if process.returncode:
        raise RuntimeError(f'exit {process.returncode}: {args[0]}\n{err.decode(errors="replace")}')
    return out.decode('utf-8'), err.decode('utf-8', errors='replace')


def run_case(fence, name, expected, harding, granite, timeout):
    (ROOT / 'build').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='markdown-example-', dir=ROOT / 'build') as temp:
        directory = Path(temp)
        source = directory / (name + '.hrd')
        source.write_text(fence.body, encoding='utf-8')
        # Work in the isolated directory so workspace files cannot affect the repo.
        actual, _ = command([str(harding), str(source)], directory, timeout)
        if actual != expected:
            raise RuntimeError(f'interpreter stdout: expected {expected!r}, got {actual!r}')
        binary = directory / 'program'
        command([str(granite), 'build', str(source), '-d:' + str(directory),
                 '-o:' + str(binary)], ROOT, timeout)
        actual, _ = command([str(binary)], directory, timeout)
        if actual != expected:
            raise RuntimeError(f'Granite stdout: expected {expected!r}, got {actual!r}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='inventory all Harding/Smalltalk fences')
    parser.add_argument('--harding', type=Path, default=ROOT / 'harding')
    parser.add_argument('--granite', type=Path, default=ROOT / 'granite')
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('paths', nargs='*', type=Path, default=[ROOT / 'docs'])
    options = parser.parse_args()
    paths = sorted({p for item in options.paths for p in (item.rglob('*.md') if item.is_dir() else [item])})
    seen = set()
    total = executed = failures = 0
    for path in paths:
        for fence in fences(path):
            language = fence.info.split(maxsplit=1)[0] if fence.info else ''
            if language not in ('harding', 'smalltalk'):
                continue
            total += 1
            header = HEADER.fullmatch(fence.info)
            if not header:
                if 'test=' in fence.info:
                    print(f'{path}:{fence.line}: invalid test annotation', file=sys.stderr)
                    failures += 1
                elif options.list:
                    print(f'{path}:{fence.line}: unclassified')
                continue
            _, name, expected_json = header.groups()
            if name in seen:
                print(f'{path}:{fence.line}: duplicate test name {name}', file=sys.stderr)
                failures += 1
                continue
            seen.add(name)
            if options.list:
                print(f'{path}:{fence.line}: test {name}')
                continue
            try:
                run_case(fence, name, json.loads(expected_json), options.harding.resolve(),
                         options.granite.resolve(), options.timeout)
            except (OSError, RuntimeError, ValueError) as error:
                print(f'FAIL {path}:{fence.line} {name}: {error}', file=sys.stderr)
                failures += 1
            else:
                print(f'PASS {path}:{fence.line} {name}')
                executed += 1
    print(f'{total} Harding/Smalltalk fences; {len(seen)} annotated; {executed} passed; {failures} failed')
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
