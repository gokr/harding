#!/usr/bin/env python3
"""Build and execute focused interpreter/Granite parity cases with time limits."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    ("class_methods", """
Factory := Object derive: #().
Factory class>>answer [ ^ 42 ].
Factory>>answer [ ^ 9 ].
Factory class>>plus: n [ ^ self answer + n ].
Child := Factory derive: #().
Child class>>answer [ ^ super answer + 1 ].
(Factory answer) println.
(Factory new answer) println.
(Child answer) println.
(Child plus: 2) println.
alias := Child.
(alias answer) println.
""", "42\n9\n43\n45\n43\n"),
    ("inherited_super", """
Ancestor := Object derive: #().
Ancestor class>>answer [ ^ 40 ].
Ancestor>>answer [ ^ 10 ].
Middle := Ancestor derive: #().
Middle class>>answer [ ^ super answer + 2 ].
Middle>>answer [ ^ super answer + 3 ].
Leaf := Middle derive: #().
(Leaf answer) println.
(Leaf new answer) println.
""", "42\n13\n"),
    ("block_super", """
Ancestor := Object derive: #().
Ancestor class>>answer [ ^ 40 ].
Middle := Ancestor derive: #().
Middle class>>answer [ | blk | blk := [super answer + 2]. ^ blk value ].
(Middle answer) println.
""", "42\n"),
    ("class_factory", """
Product := Object derivePublic: #(amount).
Product>>setAmount: n [ amount := n. ^ self ].
Product>>readAmount [ ^ amount ].
Product class>>make: n [ | item | item := self new. item amount: n. ^ item ].
Special := Product derive: #().
(Product make: 23) amount println.
(Special make: 31) amount println.
""", "23\n31\n"),
    ("accessor_override", """
Cell := Object derivePublic: #(amount).
Cell>>amount [ ^ 99 ].
Cell>>amount: n [ amount := n + 1. ^ amount ].
c := Cell new.
(c amount: 4) println.
(c amount) println.
(c::amount) println.
Child := Cell derive: #().
d := Child new.
(d amount: 8) println.
(d amount) println.
(d::amount) println.
""", "5\n99\n5\n9\n99\n9\n"),
    ("selective_accessors", """
Cell := Object derive: #(readOnly, writeOnly, hidden) read: #(readOnly) write: #(writeOnly).
Cell>>initialize [ readOnly := 7. hidden := 9. ^ self ].
Cell>>stored [ ^ writeOnly ].
c := Cell new initialize.
(c readOnly) println.
((c writeOnly: 12) stored) println.
(c stored) println.
""", "7\n12\n12\n"),
    ("class_super", """
Base := Object derive: #().
Base class>>answer [ ^ 40 ].
Child := Base derive: #().
Child class>>answer [ ^ super answer + 2 ].
(Child answer) println.
""", "42\n"),
    ("super_new", """
Product := Object derive: #(amount).
Product class>>new [ ^ super new initialize ].
Product>>initialize [ amount := 17. ^ self ].
Product>>readAmount [ ^ amount ].
Middle := Product derive: #().
Leaf := Middle derive: #().
(Product new readAmount) println.
(Leaf new readAmount) println.
""", "17\n17\n"),
    ("overridden_new", """
Token := Object derive: #().
Token class>>new [ ^ 99 ].
Child := Token derive: #().
(Token new) println.
(Child new) println.
""", "99\n99\n"),
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
    ("shared_capture", """
count := 0.
inc := [count := count + 1. count].
read := [count].
(inc value) println.
(read value) println.
count := 10.
(read value) println.
(inc value) println.
count println.
""", "1\n1\n10\n11\n11\n"),
    ("nested_capture", """
count := 0.
outer := [ | inner | inner := [count := count + 2. count]. inner value ].
(outer value) println.
count println.
(outer value) println.
count println.
""", "2\n2\n4\n4\n"),
    ("forward_temporary", """
Maker := Object derive: #().
Maker>>make [ | count blk | blk := [count]. count := 42. ^ blk ].
((Maker new make) value) println.
outer := [ | count blk | blk := [count]. count := 19. blk value ].
(outer value) println.
""", "42\n19\n"),
    ("iteration_capture", """
blocks := #(2, 4, 6) collect: [:n | [n]].
((blocks at: 0) value) println.
((blocks at: 1) value) println.
((blocks at: 2) value) println.
""", "2\n4\n6\n"),
    ("collection_scopes", """
count := 99.
blocks := #(nil, nil).
#(3, 5) do: [:n | | count | count := n + 1. blocks at: ((n - 3) // 2) put: [count]].
((blocks at: 0) value) println.
((blocks at: 1) value) println.
count println.
chosen := #(1, 2, 3) select: [:n | | count | count := n + 10. count println. n > 1].
chosen size println.
count println.
""", "4\n6\n99\n11\n12\n13\n2\n99\n"),
    ("while_scopes", """
count := 99.
i := 0.
[ | allowed | allowed := i < 2. allowed ] whileTrue: [ | count | count := i + 10. count println. i := i + 1 ].
count println.
i := 0.
[ | done | done := i >= 2. done ] whileFalse: [ | count | count := i + 20. count println. i := i + 1 ].
count println.
""", "10\n11\n99\n20\n21\n99\n"),
    ("range_capture", """
blocks := #(nil, nil, nil).
1 to: 3 by: 1 do: [:n | blocks at: (n - 1) put: [n]].
((blocks at: 0) value) println.
((blocks at: 1) value) println.
((blocks at: 2) value) println.
3 to: 1 by: -1 do: [:n | blocks at: (n - 1) put: [n + 10]].
((blocks at: 0) value) println.
((blocks at: 2) value) println.
""", "1\n2\n3\n11\n13\n"),
    ("inline_shadowing", """
count := 7.
true ifTrue: [ | count | count := 20. count println ].
count println.
3 timesRepeat: [ | count | count := 1. count println ].
count println.
answer := true ifTrue: [ | count | count := 42. count ] ifFalse: [0].
answer println.
count println.
""", "20\n7\n1\n1\n1\n7\n42\n7\n"),
    ("lexical_shadowing", """
Cell := Object derivePublic: #(amount).
Cell>>localValue [ | amount blk | amount := 5. blk := [amount := amount + 1. amount]. ^ blk value ].
c := Cell new.
c amount: 99.
(c localValue) println.
(c amount) println.
outer := 7.
blk := [:outer | outer := outer + 1. [outer]].
inner := blk value: 20.
(inner value) println.
outer println.
""", "6\n99\n21\n7\n"),
    ("escaped_mutable_capture", """
Maker := Object derive: #().
Maker>>counter: start [ | count | count := start. ^ [count := count + 1. count] ].
m := Maker new.
a := m counter: 10.
b := m counter: 100.
(a value) println.
(b value) println.
(a value) println.
""", "11\n101\n12\n"),
    ("captured_parameter", """
make := [:start | [start := start + 1. start]].
a := make value: 3.
b := make value: 30.
(a value) println.
(b value) println.
(a value) println.
""", "4\n31\n5\n"),
    ("escaped_environment", """
Maker := Object derive: #().
Maker>>make: text [ | blk | blk := [text & "!"]. ^ blk ].
Maker>>direct: text [ ^ [text & "?"] ].
m := Maker new.
a := m make: "first".
b := m make: "second".
c := m direct: "third".
(a value) println.
(b value) println.
(c value) println.
(a value) println.
""", "first!\nsecond!\nthird?\nfirst!\n"),
    ("error_unwind", """
result := [Error signal: "stop". "incorrect"] on: Error do: [:ex | ex message].
result println.
result := [[Error signal: "first"] on: Error do: [:ex | Error signal: "second"]]
  on: Error do: [:outer | outer message].
result println.
result := [[Error signal: "first"] on: Error do: [:ex | ex resume: 42]]
  on: Error do: [:outer | outer message].
result println.
result := [[Error signal: "first"] on: Error do: [:ex | ex resume]]
  on: Error do: [:outer | outer message].
result println.
""", "stop\nsecond\nCannot resume a non-resumable exception\nCannot resume a non-resumable exception\n"),
    ("error_actions", """
result := [[Error signal: "pass"] on: Error do: [:ex | ex pass]]
  on: Exception do: [:outer | outer message].
result println.
result := [Error signal: "return"] on: Error do: [:ex | ex return: 42].
result println.
attempts := 0.
result := [attempts := attempts + 1. (attempts < 2) ifTrue: [Error signal: "retry"]. attempts]
  on: Error do: [:ex | ex retry].
result println.
""", "pass\n42\n2\n"),
    # Only the handler-result path agrees across engines today. Resuming after a
    # notification (script/compiled contexts) and native pass across nested
    # handlers are tracked gaps in PLAN.md, so they are not asserted here.
    ("notification_dispatch", """
result := [Notification signal: "notice"] on: Notification do: [:ex | "handled"].
result println.
""", "handled\n"),
    ("notification_failure", """
result := [[Notification signal: "notice"] on: Notification do: [:ex | ex retry]]
  on: Error do: [:outer | outer message].
result println.
result := [[Notification signal: "notice"] on: Notification do: [:ex | ex return: 1]]
  on: Error do: [:outer | outer message].
result println.
result := [[Error signal: "boom"] on: Error do: [:ex | Error signal: "second"]]
  on: Error do: [:outer | outer message].
result println.
""", "Notification does not support retry\nNotification does not support return:\nsecond\n"),
    ("ensure_cleanup", """
count := 0.
result := [ "body" ] ensure: [ count := count + 1 ].
result println.
count println.
result := [[ "body" ] ensure: [ count := count + 10 ]] on: Error do: [:ex | ex message].
result println.
count println.
order := "".
[ [ "inner" ] ensure: [ order := order & "1" ] ] ensure: [ order := order & "2" ].
order println.
result := [ 7 ] ensure: [ 99 ].
result println.
""", "body\n1\nbody\n11\n12\n7\n"),
    ("unhandled_error", 'Error signal: "uncaught".', {"error": "Error: uncaught"}),
    ("unhandled_pass", '[Error signal: "passed"] on: Error do: [:ex | ex pass].',
     {"error": "Error: passed"}),
    # Both engines now reject a return to a finished home, so this is ordinary
    # parity rather than a compiled-only error check.
    ("inactive_return_target", """
Maker := Object derive: #().
Maker>>make [ ^ [^ 42] ].
blk := Maker new make.
result := [blk value] on: Error do: [:ex | ex message].
result println.
""", "Block cannot return: home activation is no longer active\n"),
    ("loop_non_local_return", """
Finder := Object derive: #().
Finder>>loop [
  | run |
  run := [ | i | i := 0. [i < 3] whileTrue: [i := i + 1. (i > 1) ifTrue: [^ i]] ].
  run value.
  ^ 99
].
(Finder new loop) println.
""", "2\n"),
    ("recursive_return_target", """
Recur := Object derive: #().
Recur>>walk: depth callback: callback [
  | own |
  own := [^ 42].
  (depth > 0) ifTrue: [self walk: (depth - 1) callback: own] ifFalse: [callback value].
  ^ 99
].
(Recur new walk: 1 callback: nil) println.
""", "42\n"),
    ("non_local_return", """
Finder := Object derive: #().
Finder>>first: xs [ xs do: [:n | (n > 0) ifTrue: [^ n]]. ^ nil ].
(Finder new first: #(-5, -3, 7, 2)) println.
""", "7\n"),
]


def run(command, timeout, log, expected_error=None):
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
    if expected_error is not None:
        if completed.returncode == 0 or expected_error not in completed.stdout:
            raise RuntimeError(f"expected failing execution containing {expected_error!r}; see {log}")
        return completed.stdout
    if completed.returncode:
        raise RuntimeError(f"exit {completed.returncode}: {command}; see {log}")
    return completed.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", nargs="*", help="optional case names")
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
    selected = [case for case in CASES if not options.cases or case[0] in options.cases]
    unknown = set(options.cases) - {case[0] for case in CASES}
    if unknown:
        parser.error(f"unknown cases: {sorted(unknown)}")
    failures = 0
    for name, source, expected in selected:
        case_dir = build_dir / name
        case_dir.mkdir()
        source_file = case_dir / f"{name}.hrd"
        source_file.write_text(source)
        binary = case_dir / name
        try:
            # The VM currently permits returns to completed homes; this case
            # checks the compiled semantic error explicitly, not engine parity.
            expected_error = expected.get("error") if isinstance(expected, dict) else None
            interpreted = None if expected is None else run(
                [str(ROOT / "harding"), str(source_file)], options.timeout,
                case_dir / "interpreted.log", expected_error=expected_error)
            run([str(ROOT / "granite"), "build", str(source_file),
                 f"-d:{case_dir}", f"-o:{binary}"], options.build_timeout,
                case_dir / "build.log")
            if expected is None:
                run([str(binary)], options.timeout, case_dir / "compiled.log",
                    expected_error="home activation is no longer active")
                print(f"PASS {name} (compiled error check; VM discrepancy documented)")
                continue
            if expected_error is not None:
                run([str(binary)], options.timeout, case_dir / "compiled.log",
                    expected_error=expected_error)
                print(f"PASS {name} (error parity)")
                continue
            compiled = run([str(binary)], options.timeout, case_dir / "compiled.log")
            if interpreted != expected or compiled != expected:
                raise RuntimeError(f"expected {expected!r}; interpreter {interpreted!r}; "
                                   f"compiled {compiled!r}")
            print(f"PASS {name} (parity)")
        except RuntimeError as error:
            failures += 1
            print(f"FAIL {name}: {error}")
    print(f"{len(selected) - failures} passed, {failures} failed; artifacts: {build_dir}")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
