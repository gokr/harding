"""Approved declared-slot contract, checked against explicit results in both engines."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''
Banana := Object derivePublic: #().
RipeBanana := Banana derivePublic: #().
Other := Object derivePublic: #().
Probe := Object derivePublic: #{#i -> Integer, #f -> Float, #b -> Boolean, #s -> String, #sym -> Symbol, #literal -> #"ready now", #fruit -> Banana, #free -> nil}.
Probe>>writeI: v [ i := v. ^self ].
Probe>>writeF: v [ f := v. ^self ].
Probe>>blockWrite: v [ [i := v] value. ^self ].
Probe>>defaults [ ^i = 0 and: [f = 0.0 and: [b = false and: [s = "" and: [sym == #""]]]] ].
p := Probe basicNew.
Stdout writeline: p defaults.
Stdout writeline: (p literal == #"ready now").
Stdout writeline: p fruit isNil.
p i: 7.
errors := 0.
[p i: nil] on: Error do: [:ex | errors := errors + 1].
[p writeI: "bad"] on: Error do: [:ex | errors := errors + 1].
[p::i := 2.5] on: Error do: [:ex | errors := errors + 1].
[p at: #i put: false] on: Error do: [:ex | errors := errors + 1].
[p blockWrite: nil] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: errors.
Stdout writeline: p i.
p writeF: 3.
Stdout writeline: (p f = 3.0).
[p f: nil] on: Error do: [:ex | errors := errors + 1].
[p s: #wrong] on: Error do: [:ex | errors := errors + 1].
[p b: 0] on: Error do: [:ex | errors := errors + 1].
[p sym: "wrong"] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: errors.
Stdout writeline: (p sym == #"").
p sym: #ok.
Stdout writeline: (p sym == #ok).
p fruit: RipeBanana new.
[p fruit: Other new] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: (p fruit isKindOf: Banana).
p fruit: nil.
Stdout writeline: p fruit isNil.
p free: nil.
p free: 3.
p free: "any".
Stdout writeline: p free.
Child := Probe derivePublic: #(extra).
c := Child basicNew.
Stdout writeline: c defaults.
[c::i := nil] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: c i.
Secondary := Object derivePublic: #().
Secondary addSuperclass: Banana.
p fruit: Secondary new.
Stdout writeline: (p fruit isKindOf: Banana).
Defaults := Object derivePublic: #{#sentence -> "hello world: \\\"quoted\\\"", #real -> 5.25}.
d := Defaults basicNew.
Stdout writeline: d sentence.
Stdout writeline: d real.
Private := Object derive: #{#v -> 4}.
Private>>set: x [v := x].
Private>>get [^v].
private := Private basicNew.
[private set: nil] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: private get.
Stdout writeline: errors.
Selective := Object derive: #{#total -> 6} read: #(total) write: #(total).
selected := Selective basicNew.
[selected::total := nil] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: selected::total.
Compat := Object deriveWithAccessors: #{#initial -> 8}.
compat := Compat basicNew.
[compat initial: nil] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: compat initial.
Counted := Object derivePublic: #{#i -> Integer}.
Counted>>initialize [i := 9].
normal := Counted new.
raw := Counted basicNew.
Stdout writeline: normal i.
Stdout writeline: raw i.
Calls := 0.
[p i: [Calls := Calls + 1. "bad"] value] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: Calls.
Stdout writeline: p i.
Stdout writeline: errors.
TypedExtra := Object derivePublic: #{#secondaryCount -> 13}.
Multiple := Object derivePublic: #().
Multiple addSuperclass: TypedExtra.
multi := Multiple basicNew.
Stdout writeline: multi secondaryCount.
[multi secondaryCount: nil] on: Error do: [:ex | errors := errors + 1].
Stdout writeline: multi secondaryCount.
Stdout writeline: errors.
'''
EXPECTED = '''true
true
true
5
7
true
9
true
true
true
true
any
true
0
true
hello world: "quoted"
5.25
4
12
6
8
9
0
1
7
15
13
13
16
'''


def execute(command, cwd=ROOT):
    p = subprocess.run(command, cwd=cwd, env=dict(os.environ, HARDING_HOME=str(ROOT)),
                       capture_output=True, text=True, timeout=240)
    if p.returncode:
        raise AssertionError(str(command) + '\n' + p.stdout + p.stderr)
    return p


class DeclaredSlotContract(unittest.TestCase):
    def test_contract_in_both_engines(self):
        base = ROOT / 'build/slot-contract-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'contract.hrd'
            source.write_text(SOURCE)
            # Compile interpreter and native output independently under ARC/ORC.
            for mm in ['arc', 'orc']:
                with self.subTest(mm=mm):
                    interpreter = work / ('harding-' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('vm-cache-' + mm)),
                             '-o:' + str(interpreter), str(ROOT / 'src/harding/repl/harding.nim')])
                    result = execute([str(interpreter), str(source)])
                    self.assertEqual(result.stderr, '')
                    self.assertEqual(result.stdout, EXPECTED)
                    output = work / ('native-' + mm)
                    execute([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work), '-o:program'])
                    execute(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('native-cache-' + mm)),
                             '-o:' + str(output), str(work / 'program.nim')])
                    result = execute([str(output)])
                    self.assertEqual(result.stderr, '')
                    self.assertEqual(result.stdout, EXPECTED)


if __name__ == '__main__':
    unittest.main()
