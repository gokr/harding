#!/usr/bin/env python3
"""Paired Granite numeric-method timings with checked output and bounded runs.

Build both variants before timing; alternate order to reduce host-load bias.
Run on an otherwise idle host. This compares Granite versions, not languages.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
WORKLOADS = {
    "integer": ("""Counter := Object derive: #().
Counter>>run [
  | total k limit |
  total := 0. k := 0. limit := 1000000.
  [k < limit] whileTrue: [total := total + k. k := k + 1].
  ^ total
].
c := Counter new.
20 timesRepeat: [answer := c run].
c run println.
""", "499999500000\n"),
    "float": ("""Counter := Object derive: #().
Counter>>run [
  | total k limit |
  total := 0.0. k := 0. limit := 1000000.
  [k < limit] whileTrue: [total := total + 0.5. k := k + 1].
  ^ total
].
c := Counter new.
20 timesRepeat: [answer := c run].
c run println.
""", "500000.0\n"),
    "dynamic_bound": ("""Counter := Object derive: #().
Counter>>run: limit [
  | total k |
  total := 0. k := 0.
  [k < limit] whileTrue: [total := total + k. k := k + 1].
  ^ total
].
c := Counter new.
20 timesRepeat: [answer := c run: 1000000].
(c run: 1000000) println.
""", "499999500000\n"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=7)
    args = parser.parse_args()
    if args.trials < 3:
        parser.error("use at least three trials")
    base = ROOT / "build/numeric-method-bench"
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="run-", dir=base))
    results = {"before": str(args.before.resolve()), "after": str(args.after.resolve()), "workloads": {}}

    def run(command, label, timeout):
        with subprocess.Popen(command, cwd=ROOT, text=True, stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              start_new_session=True) as child:
            try:
                output, errors = child.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                output, errors = child.communicate()
                (work / (label + ".stdout")).write_text(output)
                (work / (label + ".stderr")).write_text(errors + "\nTIMEOUT\n")
                raise RuntimeError(f"timeout: {command}; see {work / label}")
        process = subprocess.CompletedProcess(command, child.returncode, output, errors)
        (work / (label + ".stdout")).write_text(output)
        (work / (label + ".stderr")).write_text(errors)
        if process.returncode:
            raise RuntimeError(f"exit {process.returncode}: {command}; see {work / label}")
        return process

    for name, (source, expected) in WORKLOADS.items():
        path = work / (name + ".hrd")
        path.write_text(source)
        binaries = {}
        for variant, compiler in [("before", args.before), ("after", args.after)]:
            directory = work / (name + "-" + variant)
            directory.mkdir()
            binary = directory / "program"
            run([str(compiler.resolve()), "build", str(path), "--release", f"-d:{directory}", f"-o:{binary}"], name + "-" + variant + "-build", 180)
            binaries[variant] = binary
        times = {"before": [], "after": []}
        for trial in range(args.trials + 1):
            order = ["before", "after"] if trial % 2 == 0 else ["after", "before"]
            for variant in order:
                start = time.perf_counter()
                process = run([str(binaries[variant])], f"{name}-{variant}-{trial}", 90)
                elapsed = time.perf_counter() - start
                if process.stdout != expected or process.stderr:
                    raise RuntimeError(f"wrong output: {name}/{variant}: {process.stdout!r}, {process.stderr!r}")
                if trial:  # warm-up is checked but not timed
                    times[variant].append(elapsed)
        medians = {key: statistics.median(values) for key, values in times.items()}
        results["workloads"][name] = {"seconds": times, "medianSeconds": medians, "speedup": medians["before"] / medians["after"], "expected": expected}
        (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(f"{name}: before={medians['before']:.6f}s after={medians['after']:.6f}s speedup={medians['before'] / medians['after']:.2f}x", flush=True)
    print(f"Artifacts: {work}")


if __name__ == "__main__":
    main()
