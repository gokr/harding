#!/usr/bin/env python3
"""Build Oil with GCC instead of clang, to test whether failures are clang-only.

Run `scripts/setup_benchmark_osvm.py` first: it clones the pinned tree and builds
the default (clang) Oil and stock Cog. This script derives a GCC variant from the
same generated build script without editing generated VM sources -- it only
replaces the compiler-selection line, so the comparison stays source-identical.

Produces build/osvm/repo/products/sqoilspur64linuxht-gcc/... alongside the clang
product, and logs to build/osvm/oil-gcc-build.log.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / 'build/osvm/repo'
BUILD = REPO / 'building/linux64x64/squeak.oil.spur/build.gcc'
SOURCE = REPO / 'building/linux64x64/squeak.oil.spur/build/mvm'
SELECTION = ('if [ -n "$(command -v clang || true)" ]; then CC=clang; '
             'else CC=gcc; fi')


def main() -> int:
    if not SOURCE.exists():
        print(f"missing {SOURCE}; run scripts/setup_benchmark_osvm.py first",
              file=sys.stderr)
        return 2
    source = SOURCE.read_text()
    if SELECTION not in source:
        print("unexpected build script: compiler selection line not found",
              file=sys.stderr)
        return 2
    BUILD.mkdir(parents=True, exist_ok=True)
    script = BUILD / 'mvm'
    script.write_text(source.replace(SELECTION, 'CC=gcc'))
    script.chmod(0o755)
    with (ROOT / 'build/osvm/oil-gcc-build.log').open('w') as log:
        subprocess.run(['./mvm', 'sqoilspur64linuxht-gcc'], cwd=BUILD,
                       input='n\n', text=True, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    print(REPO / 'products/sqoilspur64linuxht-gcc')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
