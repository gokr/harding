#!/usr/bin/env python3
"""Build and execute focused interpreter/Granite parity cases with time limits."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    ("captured_block", """
Counter := Object derivePublic: #(total).
Counter>>add: xs [ xs do: [:each | total := total + each]. ^ total ].
c := Counter new.
c total: 0.
(c add: #(1, 2, 3, 4)) println.
scale := 10.
blk := [:n | n * scale].
(blk value: 7) println.
""", "10\n70\n"),
    ("non_local_return", """
Finder := Object derive: #().
Finder>>first: xs [ xs do: [:n | (n > 0) ifTrue: [^ n]]. ^ nil ].
(Finder new first: #(-5, -3, 7, 2)) println.
""", "7\n"),
]


def run(command, timeout, log):
    try:
        completed = subprocess.run(command, cwd=ROOT, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        log.write_text(output + "\nTIMEOUT\n")
        raise RuntimeError(f"timeout after {timeout}s: {command}") from error
    log.write_text(completed.stdout)
    if completed.returncode:
        raise RuntimeError(f"exit {completed.returncode}: {command}; see {log}")
    return completed.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=int, default=30,
                        help="execution limit per engine, in seconds")
    parser.add_argument("--build-timeout", type=int, default=120)
    options = parser.parse_args()
    for binary in ("harding", "granite"):
        if not (ROOT / binary).is_file():
            parser.error(f"missing {binary}; build both engines before running")
    artifact_root = ROOT / "build" / "parity"
    artifact_root.mkdir(parents=True, exist_ok=True)
    build_dir = Path(tempfile.mkdtemp(prefix="run-", dir=artifact_root))
    failures = 0
    for name, source, expected in CASES:
        case_dir = build_dir / name
        case_dir.mkdir()
        source_file = case_dir / f"{name}.hrd"
        source_file.write_text(source)
        binary = case_dir / name
        try:
            interpreted = run([str(ROOT / "harding"), str(source_file)],
                              options.timeout, case_dir / "interpreted.log")
            run([str(ROOT / "granite"), "build", str(source_file),
                 f"-d:{case_dir}", f"-o:{binary}"], options.build_timeout,
                case_dir / "build.log")
            compiled = run([str(binary)], options.timeout, case_dir / "compiled.log")
            if interpreted != expected or compiled != expected:
                raise RuntimeError(f"expected {expected!r}; interpreter {interpreted!r}; "
                                   f"compiled {compiled!r}")
            print(f"PASS {name}")
        except RuntimeError as error:
            failures += 1
            print(f"FAIL {name}: {error}")
    print(f"{len(CASES) - failures} passed, {failures} failed; artifacts: {build_dir}")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
