#!/usr/bin/env python3
"""Compare the sieve.hrd prime-count algorithm across engines.

`sieve.hrd` counts primes <= 5000 by trial division and prints only the count, so
a single run is below timer resolution for fast engines. Every engine runs the
identical computation many times in one process and is timed externally, with a
startup-only baseline subtracted. Results are normalised to milliseconds per
single sieve pass so engines can use different repetition counts.

Harding has no clock primitive, so the interpreter path cannot self-time. The
interpreter is ~200x slower than the native build, so it uses fewer repetitions.

Squeak writes results to a file because headless Squeak raises a fatal error
dialog if it writes to a closed stdout.
"""
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build" / "bench_langs"
SQUEAK_DIR = Path("/home/gokr/squeak/Squeak6.0-22148-64bit-202312181441-Linux-x64")
SQUEAK_VM = SQUEAK_DIR / "bin" / "squeak"
SQUEAK_IMAGE = ROOT / "build" / "squeak" / "bench.image"
TRIALS = 5
SQUEAK_TIMEOUT = 600

# Repetitions per engine, scaled so every workload lasts several seconds and
# startup subtraction stays reliable.
REPS = {
    "C (gcc -O3)": 20000,
    "Nim 2.2.12 (release)": 20000,
    "Go": 20000,
    "Squeak Cog (OpenSmalltalk)": 20000,
    "Node.js v22": 20000,
    "Ruby 3.2": 2000,
    "Python 3.12": 2000,
    "Harding native (Granite)": 500,
    "Harding interpreter (release)": 20,
}

# Generated under build/ (git-ignored), so the sources live here to keep the
# benchmark reproducible. Every program counts primes <= 5000 by trial division
# exactly like benchmark/sieve.hrd, takes its repetition count as argv[1], and
# prints only the count (669).
SOURCES = {
    "sieve.c": r"""
#include <stdio.h>
#include <stdlib.h>

static int run(void) {
  int primeCount = 0;
  int i = 2;
  while (i <= 5000) {
    int isPrime = 1;
    int d = 2;
    while (d * d <= i) {
      if (i % d == 0) {
        isPrime = 0;
        d = i;
      }
      d++;
    }
    if (isPrime) primeCount++;
    i++;
  }
  return primeCount;
}

int main(int argc, char **argv) {
  int reps = argc > 1 ? atoi(argv[1]) : 1;
  int total = 0;
  for (int r = 0; r < reps; r++) total = run();
  printf("%d\n", total);
  return 0;
}
""",
    "sieve.go": r"""
package main

import (
	"fmt"
	"os"
	"strconv"
)

func run() int {
	primeCount := 0
	i := 2
	for i <= 5000 {
		isPrime := true
		d := 2
		for d*d <= i {
			if i%d == 0 {
				isPrime = false
				d = i
			}
			d++
		}
		if isPrime {
			primeCount++
		}
		i++
	}
	return primeCount
}

func main() {
	reps := 1
	if len(os.Args) > 1 {
		reps, _ = strconv.Atoi(os.Args[1])
	}
	total := 0
	for r := 0; r < reps; r++ {
		total = run()
	}
	fmt.Println(total)
}
""",
    "sieve.nim": r"""
import std/[os, strutils]

proc run(): int =
  var primeCount = 0
  var i = 2
  while i <= 5000:
    var isPrime = true
    var d = 2
    while d * d <= i:
      if i mod d == 0:
        isPrime = false
        d = i
      inc d
    if isPrime:
      inc primeCount
    inc i
  primeCount

let reps = if paramCount() >= 1: parseInt(paramStr(1)) else: 1
var total = 0
for r in 0..<reps:
  total = run()
echo total
""",
    "sieve.js": r"""
function run() {
  let primeCount = 0;
  let i = 2;
  while (i <= 5000) {
    let isPrime = true;
    let d = 2;
    while (d * d <= i) {
      if (i % d === 0) {
        isPrime = false;
        d = i;
      }
      d++;
    }
    if (isPrime) {
      primeCount++;
    }
    i++;
  }
  return primeCount;
}
const reps = process.argv[2] ? parseInt(process.argv[2], 10) : 1;
let total = 0;
for (let r = 0; r < reps; r++) {
  total = run();
}
console.log(total);
""",
    "sieve.rb": r"""
def run
  prime_count = 0
  i = 2
  while i <= 5000
    is_prime = true
    d = 2
    while d * d <= i
      if i % d == 0
        is_prime = false
        d = i
      end
      d += 1
    end
    prime_count += 1 if is_prime
    i += 1
  end
  prime_count
end

reps = ARGV[0] ? ARGV[0].to_i : 1
total = 0
reps.times { total = run }
puts total
""",
    "sieve.py": r"""
import sys


def run():
    prime_count = 0
    i = 2
    while i <= 5000:
        is_prime = True
        d = 2
        while d * d <= i:
            if i % d == 0:
                is_prime = False
                d = i
            d += 1
        if is_prime:
            prime_count += 1
        i += 1
    return prime_count


reps = int(sys.argv[1]) if len(sys.argv) > 1 else 1
total = 0
for _ in range(reps):
    total = run()
print(total)
""",
    "sieve_template.hrd": r"""#!/usr/bin/env harding
# Same trial-division prime count as benchmark/sieve.hrd, repeated {REPS} times.
primeCount := 0
rep := 0
[ rep < {REPS} ] whileTrue: [
  primeCount := 0
  i := 2
  [ i <= 5000 ] whileTrue: [
    isPrime := true
    d := 2
    [ d * d <= i ] whileTrue: [
      (i \\ d = 0) ifTrue: [
        isPrime := false
        d := i
      ]
      d := d + 1
    ]
    isPrime ifTrue: [
      primeCount := primeCount + 1
    ]
    i := i + 1
  ]
  rep := rep + 1
]
Stdout writeline: primeCount
""",
    "sieve_squeak.st": r"""
| total rep out |
total := 0.
rep := 0.
[ rep < {REPS} ] whileTrue: [
  | primeCount i d isPrime |
  primeCount := 0.
  i := 2.
  [ i <= 5000 ] whileTrue: [
    isPrime := true.
    d := 2.
    [ d * d <= i ] whileTrue: [
      (i \\ d) = 0 ifTrue: [ isPrime := false. d := i ].
      d := d + 1 ].
    isPrime ifTrue: [ primeCount := primeCount + 1 ].
    i := i + 1 ].
  total := primeCount.
  rep := rep + 1 ].
out := FileStream forceNewFileNamed: '{OUTPATH}'.
out nextPutAll: total printString; close.
Smalltalk snapshot: false andQuit: true.
""",
    "baseline.hrd": "Stdout writeline: 0\n",
    "baseline_squeak.st": (
        "| out |\n"
        "out := FileStream forceNewFileNamed: '{OUTPATH}'.\n"
        "out nextPutAll: '0'; close.\n"
        "Smalltalk snapshot: false andQuit: true.\n"
    ),
}


def write_sources():
    WORK.mkdir(parents=True, exist_ok=True)
    for name, text in SOURCES.items():
        (WORK / name).write_text(text.lstrip("\n"))


def reps_arg(args, reps):
    return list(args) + [str(reps)]


def run(command, timeout=600, cwd=WORK):
    start = time.perf_counter()
    completed = subprocess.run(command, cwd=str(cwd), text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               timeout=timeout)
    elapsed = (time.perf_counter() - start) * 1000
    if completed.returncode:
        raise RuntimeError(f"exit {completed.returncode}: {command}\n{completed.stdout[-600:]}")
    return elapsed, completed.stdout.strip()


def build(command, log_name):
    log = WORK / log_name
    completed = subprocess.run(command, cwd=str(WORK), text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_text(completed.stdout)
    if completed.returncode:
        raise RuntimeError(f"build failed: {command}; see {log}")


def harding_program(reps):
    src = (WORK / "sieve_template.hrd").read_text()
    target = WORK / f"sieve_{reps}.hrd"
    target.write_text(src.replace("{REPS}", str(reps)))
    return target


def squeak_program(template, reps, out_path):
    src = (WORK / template).read_text()
    script = WORK / f"{template.removesuffix('.st')}_run.st"
    script.write_text(src.replace("{REPS}", str(reps)).replace("{OUTPATH}", str(out_path)))
    return script


def measure(label, workload, baseline, expected, reps, cwd=WORK):
    work_times, base_times, result = [], [], None
    for _ in range(TRIALS):
        elapsed, output = run(workload, 600, cwd)
        work_times.append(elapsed)
        if output.splitlines():
            result = output.splitlines()[-1]
        elapsed, _ = run(baseline, 600, cwd)
        base_times.append(elapsed)
    if result != expected:
        raise RuntimeError(f"{label}: expected {expected}, got {result!r}")
    net = statistics.median(work_times) - statistics.median(base_times)
    return dict(label=label, reps=reps, net=net, per_run=net / reps, result=result)


def measure_squeak(label, script, baseline_script, out_file, expected, reps):
    work_times, base_times, result = [], [], None
    for _ in range(TRIALS):
        out_file.unlink(missing_ok=True)
        start = time.perf_counter()
        run([str(SQUEAK_VM), "-nodisplay", "-nosound", str(SQUEAK_IMAGE), str(script)],
            SQUEAK_TIMEOUT, cwd=WORK)
        work_times.append((time.perf_counter() - start) * 1000)
        result = out_file.read_text().strip() if out_file.exists() else None
        start = time.perf_counter()
        run([str(SQUEAK_VM), "-nodisplay", "-nosound", str(SQUEAK_IMAGE), str(baseline_script)],
            SQUEAK_TIMEOUT, cwd=WORK)
        base_times.append((time.perf_counter() - start) * 1000)
    if result != expected:
        raise RuntimeError(f"{label}: expected {expected}, got {result!r}")
    net = statistics.median(work_times) - statistics.median(base_times)
    return dict(label=label, reps=reps, net=net, per_run=net / reps, result=result)


def main():
    write_sources()
    build(["gcc", "-O3", "-o", "sieve_c", "sieve.c"], "build_c.log")
    build(["nim", "c", "-d:release", "--opt:speed", "-o:sieve_nim", "sieve.nim"], "build_nim.log")
    build(["go", "build", "-o", "sieve_go", "sieve.go"], "build_go.log")

    harding_native = harding_program(REPS["Harding native (Granite)"])
    build([str(ROOT / "granite"), "build", str(harding_native), "--release",
           "-o:" + str(WORK / "sieve_native")], "build_granite.log")

    squeak_out = WORK / "squeak_work_out.txt"
    squeak_work = squeak_program("sieve_squeak.st", REPS["Squeak Cog (OpenSmalltalk)"], squeak_out)
    squeak_base = squeak_program("baseline_squeak.st", 0, WORK / "squeak_base_out.txt")

    results = [
        measure("C (gcc -O3)", reps_arg([str(WORK / "sieve_c")], REPS["C (gcc -O3)"]),
                ["true"], "669", REPS["C (gcc -O3)"]),
        measure("Nim 2.2.12 (release)",
                reps_arg([str(WORK / "sieve_nim")], REPS["Nim 2.2.12 (release)"]),
                ["true"], "669", REPS["Nim 2.2.12 (release)"]),
        measure("Go", reps_arg([str(WORK / "sieve_go")], REPS["Go"]),
                ["true"], "669", REPS["Go"]),
        measure_squeak("Squeak Cog (OpenSmalltalk)", squeak_work, squeak_base,
                       squeak_out, "669", REPS["Squeak Cog (OpenSmalltalk)"]),
        measure("Harding native (Granite)",
                reps_arg([str(WORK / "sieve_native")], REPS["Harding native (Granite)"]),
                ["true"], "669", REPS["Harding native (Granite)"]),
        measure("Node.js v22",
                reps_arg(["node", str(WORK / "sieve.js")], REPS["Node.js v22"]),
                ["node", "-e", ""], "669", REPS["Node.js v22"]),
        measure("Ruby 3.2", reps_arg(["ruby", str(WORK / "sieve.rb")], REPS["Ruby 3.2"]),
                ["ruby", "-e", ""], "669", REPS["Ruby 3.2"]),
        measure("Python 3.12",
                reps_arg(["python3", str(WORK / "sieve.py")], REPS["Python 3.12"]),
                ["python3", "-c", ""], "669", REPS["Python 3.12"]),
        measure("Harding interpreter (release)",
                [str(ROOT / "harding"), str(harding_program(REPS["Harding interpreter (release)"]))],
                [str(ROOT / "harding"), str(WORK / "baseline.hrd")], "669",
                REPS["Harding interpreter (release)"], cwd=ROOT),
    ]

    fastest = min(r["per_run"] for r in results)
    print(f"workload: count primes <= 5000 by trial division; trials={TRIALS}; "
          f"startup baseline subtracted; per-run = one sieve pass")
    print(f"{'engine':30} {'result':>6} {'reps':>5} {'per-run ms':>11} {'rel':>8}")
    for r in sorted(results, key=lambda r: r["per_run"]):
        print(f"{r['label']:30} {str(r['result']):>6} {r['reps']:>5} "
              f"{r['per_run']:>11.3f} {r['per_run'] / fastest:>7.1f}x")


if __name__ == "__main__":
    main()
