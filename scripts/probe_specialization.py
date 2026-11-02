#!/usr/bin/env python3
"""Report how much compiled dispatch a native-parameter specialization could reach.

Builds each benchmark with Granite, then runs it with HARDING_SPEC_PROBE=1 and
forwards the SPECPROBE summary. See docs/GRANITE_SPECIALIZATION_PROBE.md.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = ('richards', 'deltablue', 'queens')
REPETITIONS = '30'


def main() -> int:
    work = Path(tempfile.mkdtemp(dir=ROOT / 'build', prefix='specprobe-'))
    granites = [ROOT / 'granite', ROOT / 'build/granite240']
    granite = next((g for g in granites if g.exists()), None)
    if granite is None:
        print('build Granite first: nim c -p:external -o:granite '
              'src/harding/compiler/granite.nim', file=sys.stderr)
        return 2
    for case in CASES:
        source = ROOT / 'benchmark' / (case + '.hrd')
        if not source.exists():
            print(f'{case}: missing source, skipped')
            continue
        directory = work / case
        directory.mkdir()
        copied = directory / (case + '.hrd')
        copied.write_text(source.read_text())
        build = subprocess.run([str(granite), 'build', str(copied),
                                '-d:' + str(directory), '-o:' + str(directory / 'program')],
                               capture_output=True, text=True, timeout=300)
        if build.returncode:
            print(f'{case}: build failed')
            print((build.stdout + build.stderr)[-400:])
            continue
        ran = subprocess.run([str(directory / 'program'), REPETITIONS],
                             capture_output=True, text=True, timeout=300,
                             env=dict(os.environ, HARDING_SPEC_PROBE='1'))
        lines = [l for l in ran.stderr.splitlines() if l.startswith('SPECPROBE')]
        print(f'{case}:')
        for line in lines:
            print('  ' + line)
        if not lines:
            print(f'  no probe output (exit {ran.returncode})')
    print('artifacts:', work)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
