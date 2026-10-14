#!/usr/bin/env python3
"""Isolated Nimony smoke probes; does not replace the project's Nim toolchain.

Pass --compiler to a locally unpacked toolchain. Logs/sources/results are written
under build/nimony-probes/. Compatibility checks are recorded, not counted as
passing compilation when they fail. No automatic download or installation.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROBES = {
    "basic": ("""import std/syncio

type Node = ref object
  value: int
  next: nil Node

proc count(): int =
  let fooBar = 10
  let foobar = 20
  let tail = Node(value: fooBar, next: nil)
  let head = Node(value: foobar, next: tail)
  result = head.value
  let previous = head.next
  if previous != nil:
    result += previous.value

var total = 0
var i = 0
while i < 1000:
  total += i
  inc i
echo total
echo count()
""", "499500\n30\n", ["c", "n"]),
    "closure": ("""import std/syncio

proc makeCounter(): proc(): int {.closure.} =
  var count = 0
  result = proc(): int {.closure.} =
    inc count
    return count

let counter = makeCounter()
echo counter()
echo counter()
""", "1\n2\n", ["c"]),
    "passive": ("""import std/syncio

var resumePoint {.threadvar.}: Continuation
var cleaned {.threadvar.}: int

proc worker() {.passive.} =
  defer: inc cleaned
  echo "before"
  resumePoint = delay()
  suspend()
  echo "after"

var task = delay(worker())
while not stopping(task):
  task = advance(task)
echo "parked"
echo cleaned
task = resumePoint
while not stopping(task):
  task = advance(task)
echo cleaned
""", "before\nparked\n0\nafter\n1\n", ["c"]),
    "transfers": ("""import std/syncio

var cleaned {.threadvar.}: int

proc failed() {.raises.} =
  defer: inc cleaned
  raise Failure

try:
  failed()
except ErrorCode:
  echo "caught"
echo cleaned
""", "caught\n1\n", ["c"]),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path,
                        default=ROOT / "build/nimony-evaluation/nimony/bin/nimony")
    parser.add_argument("--generated", type=Path,
                        help="also check an existing Granite-generated Nim file unchanged")
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    if not compiler.is_file():
        parser.error("unpack Nimony locally or specify --compiler")
    if args.generated and not args.generated.is_file():
        parser.error("--generated must name an existing Nim file")
    base = ROOT / "build/nimony-probes"
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="run-", dir=base))
    results = []

    def run(command, log, timeout):
        try:
            process = subprocess.run(command, cwd=work, text=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     timeout=timeout)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            (work / log).write_text(output + "\nTIMEOUT\n")
            raise RuntimeError(f"timeout; see {work / log}") from error
        (work / log).write_text(process.stdout)
        return process

    version = run([str(compiler), "--version"], "version.log", 10).stdout.strip()
    for name, (source, expected, backends) in PROBES.items():
        path = work / (name + ".nim")
        path.write_text(source)
        for backend in backends:
            label = name + "-" + backend
            binary = work / label
            build = run([str(compiler), backend, "--parallelBuild:2",
                         "--nimcache:" + str(work / (label + "-cache")),
                         "-o:" + str(binary), str(path)], label + "-build.log", 120)
            if build.returncode:
                raise RuntimeError(f"build failed; see {work / (label + '-build.log')}")
            execution = run([str(binary)], label + "-run.log", 20)
            if execution.returncode or execution.stdout != expected:
                raise RuntimeError(f"wrong result; see {work / (label + '-run.log')}")
            results.append(dict(probe=label, status="passed", output=execution.stdout))
            print(f"PASS {label}", flush=True)

    checks = [("harding", ROOT / "src/harding/repl/harding.nim")]
    if args.generated:
        checks.append(("generated", args.generated.resolve()))
    for label, path in checks:
        checked = run([str(compiler), "check", "--parallelBuild:2",
                       "--nimcache:" + str(work / (label + "-check")), str(path)],
                      label + "-check.log", 120)
        results.append(dict(probe=label + "-compatibility", exit_code=checked.returncode,
                            status="checked" if checked.returncode == 0 else "incompatible"))
        print(f"{label}: compatibility check exit {checked.returncode}; see log", flush=True)
    (work / "results.json").write_text(json.dumps(dict(version=version, results=results), indent=2) + "\n")
    print(f"artifacts: {work}")


if __name__ == "__main__":
    main()
