#!/usr/bin/env python3
"""Both-engine parity for slot declaration types and declared defaults.

Every case runs through the release interpreter and a Granite build, and must
produce identical stdout. Includes an explicit-`nil` slot so the dynamic case is
covered, and a case proving a declared default is overridden by `initialize`.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CASES = {
    "declared primitive defaults seed at allocation": '''
P := Object derivePublic: #{#x -> 0, #y -> 5.0, #s -> "hi", #b -> true, #z -> nil}.
p := P new.
Stdout writeline: (p x).
Stdout writeline: (p y).
Stdout writeline: (p s).
Stdout writeline: (p b).
Stdout writeline: (p z isNil).
''',
    "declared object class constrains the slot": '''
Banana := Object derivePublic: #(ripeness).
Banana>>initialize [ ripeness := 7. ^ self ].
Holder := Object derivePublic: #{#fruit -> Banana}.
Holder>>setup [ fruit := Banana new. ^ self ].
h := Holder new setup.
Stdout writeline: (h fruit ripeness).
''',
    "initialize overrides a declared default": '''
P := Object derivePublic: #{#x -> 0}.
P>>initialize [ x := 42. ^ self ].
p := P new.
Stdout writeline: (p x).
''',
    "untyped declaration keeps nil": '''
P := Object derivePublic: #(x).
p := P new.
Stdout writeline: (p x isNil).
''',
    "type-only declaration reports the zero value": '''
P := Object derivePublic: #{#x -> Integer}.
p := P new.
Stdout writeline: (p x).
''',
    "mixed declared and untyped slots coexist": '''
P := Object derivePublic: #{#n -> 0, #obj -> nil}.
P>>setup [ obj := "text". ^ self ].
p := P new setup.
Stdout writeline: (p n).
Stdout writeline: (p obj).
''',
    "subclass inherits a declared default": '''
Base := Object derivePublic: #{#n -> 5}.
Derived := Base derivePublic: #(extra).
d := Derived new.
Stdout writeline: (d n).
Stdout writeline: (d extra isNil).
''',
}


def run(command, cwd, timeout=180):
    # The interpreter resolves its bootstrap relative to HARDING_HOME, and the
    # cases run in a scratch directory rather than the repository root.
    environment = dict(os.environ, HARDING_HOME=str(ROOT))
    completed = subprocess.run(command, cwd=cwd, text=True, timeout=timeout,
                               env=environment,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return completed


def main():
    interp = ROOT / "harding"
    granite = ROOT / "granite"
    for binary in (interp, granite):
        if not binary.exists():
            print(f"missing binary: {binary}; run nimble harding and build granite", file=sys.stderr)
            return 1
    failures = 0
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as workdir:
        work = Path(workdir)
        for index, (name, source) in enumerate(CASES.items()):
            script = work / f"case{index}.hrd"
            script.write_text(source)
            interpreted = run([str(interp), str(script)], work)
            if interpreted.returncode != 0 or interpreted.stderr.strip():
                print(f"FAIL {name}: interpreter: {interpreted.stderr.strip()[:200]}")
                failures += 1
                continue
            outdir = work / f"out{index}"
            outdir.mkdir()
            compiled = run([str(granite), "build", str(script), "-d:" + str(outdir),
                            "-o:" + str(outdir / "prog")], work, timeout=300)
            if compiled.returncode != 0:
                print(f"FAIL {name}: granite build: {compiled.stderr.strip()[-300:]}")
                failures += 1
                continue
            native = run([str(outdir / "prog")], outdir)
            if native.returncode != 0 or native.stderr.strip():
                print(f"FAIL {name}: native run: {native.stderr.strip()[:200]}")
                failures += 1
                continue
            if native.stdout != interpreted.stdout:
                print(f"FAIL {name}: interpreter {interpreted.stdout!r} != native {native.stdout!r}")
                failures += 1
                continue
            print(f"PASS {name} -> {interpreted.stdout.strip().splitlines()}")
    if failures:
        print(f"{failures} case(s) failed")
        return 1
    print(f"{len(CASES)} cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
