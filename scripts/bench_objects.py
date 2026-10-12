#!/usr/bin/env python3
"""Checked object benchmarks: interpreter, Granite and native Nim.

All engines run identical linked-object algorithms. Each trial checks output;
paired zero-work processes subtract startup and class-registration overhead.
Raw timings, generated sources and logs remain in an isolated build directory.
Build Harding in release mode before using this runner.
"""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {"queens": 92, "towers": 8191}
NIM_SOURCE = r'''
import std/os
import std/strutils

type
  Placement = ref object
    row, column: int
    previous: Placement
  Disk = ref object
    size: int
    next: Disk
  Peg = ref object
    top: Disk

proc canPlace(row, column: int, head: Placement): bool =
  var current = head
  result = true
  while current != nil:
    let distance = row - current.row
    let delta = column - current.column
    if delta == 0 or delta == distance or delta == -distance:
      result = false
    current = current.previous

proc search(row: int, head: Placement): int =
  if row == 8:
    return 1
  for column in 0..<8:
    if canPlace(row, column, head):
      let placed = Placement(row: row, column: column, previous: head)
      result += search(row + 1, placed)

proc push(peg: Peg, disk: Disk) =
  doAssert peg.top == nil or disk.size < peg.top.size
  disk.next = peg.top
  peg.top = disk

proc pop(peg: Peg): Disk =
  doAssert peg.top != nil
  result = peg.top
  peg.top = result.next
  result.next = nil

proc move(count: int, source, destination, helper: Peg, moves: var int) =
  if count > 0:
    move(count - 1, source, helper, destination, moves)
    push(destination, pop(source))
    inc moves
    move(count - 1, helper, destination, source, moves)

proc towers(): int =
  let source = Peg()
  let destination = Peg()
  let helper = Peg()
  for size in countdown(13, 1):
    push(source, Disk(size: size))
  move(13, source, destination, helper, result)
  doAssert source.top == nil and helper.top == nil
  var disk = destination.top
  var expected = 1
  while disk != nil:
    doAssert disk.size == expected
    inc expected
    disk = disk.next
  doAssert expected == 14

let reps = parseInt(paramStr(1))
var answer = 0
for iteration in 0..<reps:
  when defined(queens):
    answer = search(0, nil)
  else:
    answer = towers()
echo answer
'''


def execute(command, work, log, timeout):
    start = time.perf_counter_ns()
    try:
        proc = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        (work / log).write_text(output + "\nTIMEOUT\n")
        raise RuntimeError(f"timeout: {command}; see {work / log}") from error
    elapsed = (time.perf_counter_ns() - start) / 1_000_000
    (work / log).write_text(proc.stdout)
    if proc.returncode:
        raise RuntimeError(f"exit {proc.returncode}: {command}; see {work / log}")
    return elapsed, proc.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", nargs="*", metavar="CASE", help="queens and/or towers; default: both")
    parser.add_argument("--trials", type=int, default=5)
    parser.add_argument("--native-reps", type=int, default=30)
    parser.add_argument("--interpreter-reps", type=int, default=3)
    parser.add_argument("--nim-reps", type=int, default=1000)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    args.cases = args.cases or list(EXPECTED)
    if any(case not in EXPECTED for case in args.cases):
        parser.error("cases must be queens or towers")
    if min(args.trials, args.native_reps, args.interpreter_reps, args.nim_reps) < 1:
        parser.error("trial/repetition counts must be positive")
    base = ROOT / "build/bench_objects"
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="run-", dir=base))
    results = []
    for case in args.cases:
        definitions = (ROOT / f"benchmark/{case}.hrd").read_text().split("# Benchmark driver")[0]
        solver = "Queens" if case == "queens" else "Towers"

        def program(label, reps):
            path = work / f"{case}_{label}.hrd"
            path.write_text(definitions + f"""
solver := {solver} new.
answer := 0.
{reps} timesRepeat: [answer := solver benchmark].
answer println.
""")
            return path

        baseline = program("baseline", 0)
        native_source = program("native", args.native_reps)
        interpreter_source = program("interpreter", args.interpreter_reps)
        native_binary = work / f"{case}_native"
        baseline_binary = work / f"{case}_baseline"
        for source, binary in [(native_source, native_binary), (baseline, baseline_binary)]:
            execute([str(ROOT / "granite"), "build", str(source), "--release", "-o:" + str(binary)],
                    work, binary.name + "_build.log", args.timeout)
        nim_source = work / f"{case}.nim"
        nim_source.write_text(NIM_SOURCE.lstrip())
        nim_binary = work / f"{case}_nim"
        execute(["nim", "c", "-d:release", "--opt:speed", "--mm:arc", "-d:" + case,
                 "-o:" + str(nim_binary), str(nim_source)], work, case + "_nim_build.log", args.timeout)
        engines = [
            ("Granite", [str(native_binary)], [str(baseline_binary)], args.native_reps),
            ("Interpreter (release)", [str(ROOT / "harding"), str(interpreter_source)],
             [str(ROOT / "harding"), str(baseline)], args.interpreter_reps),
            ("Nim (release ARC)", [str(nim_binary), str(args.nim_reps)],
             [str(nim_binary), "0"], args.nim_reps),
        ]
        for index, (label, command, baseline_command, reps) in enumerate(engines):
            raw = []
            for trial in range(args.trials):
                prefix = f"{case}_{index}_{trial}"
                elapsed, output = execute(command, work, prefix + ".log", args.timeout)
                if output != str(EXPECTED[case]):
                    raise RuntimeError(f"{case}/{label}: expected {EXPECTED[case]}, got {output!r}")
                startup, output = execute(baseline_command, work, prefix + "_base.log", args.timeout)
                if output != "0":
                    raise RuntimeError(f"{case}/{label}: invalid baseline {output!r}")
                raw.append({"work_ms": elapsed, "baseline_ms": startup})
            net = statistics.median(item["work_ms"] for item in raw) - statistics.median(
                item["baseline_ms"] for item in raw)
            if net <= 0:
                raise RuntimeError(f"{case}/{label}: below measurement resolution; increase repetitions")
            row = dict(case=case, engine=label, reps=reps, per_run_ms=net / reps, trials=raw)
            results.append(row)
            print(f"{case:8} {label:24} {net / reps:10.3f} ms/pass ({reps} reps)", flush=True)
    (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"artifacts: {work}")


if __name__ == "__main__":
    main()
