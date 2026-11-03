#!/usr/bin/env python3
"""Assemble and execute Havlak with an existing interpreter (no root builds)."""
from pathlib import Path
import argparse
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, default=ROOT / 'harding')
    parser.add_argument('--assemble-only', action='store_true')
    parser.add_argument('workload', nargs='*', type=int,
                        help='dummy loops, extra iterations, parallel, middle, inner')
    args = parser.parse_args()
    if len(args.workload) > 5 or any(n < 0 for n in args.workload):
        parser.error('Expected at most five nonnegative workload parameters')
    directory = ROOT / 'build/awfy-havlak'
    directory.mkdir(parents=True, exist_ok=True)
    driver = (HERE / 'driver.hrd').read_text()
    start = driver.index('|')
    end = driver.index('|', start + 1) + 1
    source = directory / 'standalone.hrd'
    source.write_text(driver[start:end] + '\n' + (HERE / 'havlak.hrd').read_text()
                      + '\n' + driver[end:])
    if args.assemble_only:
        print(source)
        return 0
    return subprocess.call([str(args.engine.resolve()), str(source), '--',
                            *map(str, args.workload)], cwd=ROOT)


if __name__ == '__main__':
    raise SystemExit(main())
