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
""", "stop\nsecond\n"),
    ("error_actions", """
result := [[Error signal: "pass"] on: Error do: [:ex | ex pass]]
  on: Exception do: [:outer | outer message].
result println.
result := [Error signal: "value"] on: Error do: [:ex | 42].
result println.
attempts := 0.
result := [attempts := attempts + 1. (attempts < 2) ifTrue: [Error signal: "retry"]. attempts]
  on: Error do: [:ex | ex retry].
result println.
""", "pass\n42\n2\n"),
    # Top-level uppercase names are Harding globals: shared bindings visible to
    # compiled methods and to blocks inside them, not locals of main().
    ("global_scope", """
Order := "before".
Counter := 0.
Total := 0.
C := Object derive: #().
C>>bump [ Order := Order & "!". Counter := Counter + 1 ].
C>>read [ ^ Order ].
C>>addThrice [ 3 timesRepeat: [ Total := Total + 1 ] ].
C new bump.
Order println.
Counter println.
(C new read) println.
C new addThrice.
Total println.
""", "before!\n1\nbefore!\n3\n"),
    # A block lexically inside a method that names an instance slot compiles to
    # getSlotValue(self, ...), so it must capture `self` into its environment.
    ("block_slot_capture", """
C := Object derive: #(n).
C>>n: v [ n := v ].
C>>apply: blk [ ^ blk value ].
C>>direct [ ^ [ n + 1 ] value ].
C>>nested [ ^ self apply: [ n + 2 ] ].
C>>held [ | b | b := [ n + 3 ]. ^ self apply: b ].
o := C new.
o n: 41.
(o direct) println.
(o nested) println.
(o held) println.
""", "42\n43\n44\n"),
    ("notification_dispatch", """
result := [Notification signal: "notice"] on: Notification do: [:ex | "handled"].
result println.
result := [1 + (Notification signal: "value")] on: Notification do: [:ex | 41].
result println.
result := [[Notification signal: "pass"] on: Notification do: [:ex | ex pass. "incorrect"]]
  on: Exception do: [:outer | "outer handled"].
result println.
result := [Notification signal: "first". Notification signal: "second". "continued"]
  on: Notification do: [:ex | 0].
result println.
""", "handled\n42\nouter handled\ncontinued\n"),
    ("notification_lifetime", """
seen := 0.
cleanups := 0.
result := [[
  (Notification signal: "a") println.
  cleanups println.
  (Notification signal: "b") println.
  "body"
] ensure: [cleanups := cleanups + 1]] on: Notification do: [:ex | seen := seen + 1. seen].
result println.
seen println.
cleanups println.
result := [[Notification signal: "inner"] on: Notification do: [:ex | Notification signal: "from handler"]]
  on: Notification do: [:outer | "outer result"].
result println.
""", "1\n0\n2\nbody\n2\n1\nouter result\n"),
    ("notification_pass_cleanup", """
Order := "".
result := [[
  (Notification signal: "first") println.
  (Notification signal: "second") println.
  Order := Order & "b".
  "body"
] on: Notification do: [:ex |
  [[ex pass. "incorrect"] ensure: [Order := Order & "i"]]
    ensure: [Order := Order & "o"]
]] on: Notification do: [:outer | Order := Order & "h". "outer"].
result println.
Order println.
Order := "".
result := [[[Notification signal: "failed"] on: Notification do: [:ex |
  [ex pass] ensure: [Order := Order & "c". Error signal: "cleanup failed"]
]] on: Notification do: [:outer | Order := Order & "incorrect"]]
  on: Error do: [:outer | outer message].
result println.
Order println.
""", "outer\nouter\nbody\niohiohb\ncleanup failed\nc\n"),
    ("notification_default", """
(Notification signal: "unhandled") println.
([Notification signal: "passed"] on: Notification do: [:ex | ex pass]) println.
result := [[Notification signal: "inner"] on: Notification do: [:ex | Error signal: "handler failed"]]
  on: Error do: [:outer | outer message].
result println.
""", "Exception: unhandled\nnil\nException: passed\nnil\nhandler failed\n"),
    ("notification_failure", """
result := [[Notification signal: "notice"] on: Notification do: [:ex | ex retry]]
  on: Error do: [:outer | outer message].
result println.
result := [[Error signal: "boom"] on: Error do: [:ex | Error signal: "second"]]
  on: Error do: [:outer | outer message].
result println.
""", "Notification does not support retry\nsecond\n"),
    ("custom_exception_hierarchy", """
Problem := Error derivePublic: #(code).
Problem>>initialize [ code := 7 ].
Problem>>describe [ ^ self message & ":" & code asString ].
DeepProblem := Problem derive: #().
([DeepProblem signal: "bad"] on: Problem do: [:ex | ex describe]) println.
([DeepProblem signal: "boxed"] on: Error do: [:ex | ex message]) println.
Instance := DeepProblem new.
Instance message: "instance".
([Instance signal] on: Error do: [:caught | caught describe]) println.
([DeepProblem new describe] on: Error do: [:ex | "incorrect"]) println.
Advice := Notification derive: #().
Advice>>defaultAction [ "custom default" println ].
(Advice signal: "notice") println.
""", "bad:7\nboxed\ninstance:7\nnil:7\ncustom default\nnil\n"),
    ("arithmetic_zero_divisor", r"""
([1 // 0] on: DivisionByZero do: [:ex | ex message]) println.
([1 % 0] on: DivisionByZero do: [:ex | ex message]) println.
([1 \\ 0] on: DivisionByZero do: [:ex | ex message]) println.
([1 / 0] on: DivisionByZero do: [:ex | ex message]) println.
([1 / 0.0] on: DivisionByZero do: [:ex | ex message]) println.
([1.0 / 0] on: DivisionByZero do: [:ex | ex message]) println.
([1.0 / 0.0] on: DivisionByZero do: [:ex | ex message]) println.
([1 / 0] on: Exception do: [:ex | "outer catch"]) println.
([7 // 2] on: DivisionByZero do: [:ex | "incorrect"]) println.
([2 / 4] on: DivisionByZero do: [:ex | "incorrect"]) println.
""", "Integer division by zero\nInteger modulo by zero\nInteger modulo by zero\nInteger division by zero\nFloat division by zero\nFloat division by zero\nFloat division by zero\nouter catch\n3\n0.5\n"),
    ("handler_transfer_cleanup", """
Order := "".
result := [[[Error signal: "body"] on: Error do: [:ex |
  [ex pass] ensure: [Order := Order & "i"]
]] ensure: [Order := Order & "o"]]
  on: Error do: [:outer | Order := Order & "h". "outer"].
result println.
Order println.
Order := "".
Attempts := 0.
result := [Attempts := Attempts + 1. (Attempts < 2) ifTrue: [Error signal: "retry"]. "body"]
  on: Error do: [:ex | [ex retry] ensure: [Order := Order & "c"]].
result println.
Order println.
Order := "".
result := [[[Error signal: "body"] on: Error do: [:ex |
  [ex pass] ensure: [Order := Order & "c". Error signal: "cleanup failed"]
]] ensure: [Order := Order & "o"]]
  on: Error do: [:outer | outer message].
result println.
Order println.
""", "outer\nioh\nbody\nc\ncleanup failed\nco\n"),
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
    ("ensure_retry", """
attempts := 0.
cleanups := 0.
result := [[attempts := attempts + 1. (attempts < 3) ifTrue: [Error signal: "again"]. attempts]
  ensure: [cleanups := cleanups + 1]] on: Error do: [:ex | ex retry].
result println.
attempts println.
cleanups println.
""", "3\n3\n3\n"),
    ("ensure_transfer", """
Winner := Object derive: #().
Winner>>run [
  [[Error signal: "body failed"] ensure: ["inner cleanup" println. ^ "cleanup won"]]
    ensure: ["outer cleanup" println]
].
([Winner new run] on: Error do: [:ex | "incorrect"]) println.
Winner>>returning [
  [[^ "body return"] ensure: ["inner cleanup" println. ^ "cleanup return"]]
    ensure: ["outer cleanup" println]
].
(Winner new returning) println.
""", "inner cleanup\nouter cleanup\ncleanup won\ninner cleanup\nouter cleanup\ncleanup return\n"),
    ("ensure_cleanup_failure", """
Order := "".
result := [[[Error signal: "body error"] ensure: [Order := Order & "1". Error signal: "cleanup error"]]
  ensure: [Order := Order & "2"]] on: Error do: [:ex | ex message].
result println.
Order println.
""", "cleanup error\n12\n"),
    ("ensure_uncaught", """
[[Error signal: "uncaught"] ensure: ["inner cleanup" println]]
  ensure: ["outer cleanup" println].
""", {"error": "Error: uncaught", "prefix": "inner cleanup\nouter cleanup\n"}),
    ("ensure_uncaught_override", """
Winner := Object derive: #().
Winner>>run [
  [[Error signal: "uncaught"] ensure: [^ "cleanup won"]]
    ensure: ["outer cleanup" println]
].
(Winner new run) println.
""", "outer cleanup\ncleanup won\n"),
    ("unhandled_missing_message", '[1 missing] ensure: ["cleanup" println].',
     {"error": "Message not understood: missing", "prefix": "cleanup\n"}),
    ("unhandled_error", 'Error signal: "uncaught".', {"error": "Error: uncaught"}),
    ("unhandled_pass", '[Error signal: "passed"] on: Error do: [:ex | ex pass].',
     {"error": "Error: passed"}),
    ("unhandled_custom_default_action", """
MyError := Error derive: #().
MyError>>defaultAction [ "custom error default" println ].
MyError signal: "unhandled".
"not reached" println.
""", {"error": "MyError: unhandled", "contains": "custom error default"}),
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

# Keep the measured workloads under executed correctness coverage as well.
CASES.extend([
    ("case_sensitive_bindings", """
fooBar := 10.
foobar := 20.
fooBar := fooBar + 1.
foobar := foobar + 2.
fooBar println.
foobar println.
CaseBindings := Object derivePublic: #(slotValue, slotvalue).
CaseBindings>>combine: fooBar with: foobar [ | readPair | readPair := [fooBar + foobar]. ^ readPair value ].
k := CaseBindings new.
k slotValue: 31.
k slotvalue: 42.
k slotValue println.
k slotvalue println.
(k combine: 3 with: 4) println.
([:fooBar :foobar | fooBar + foobar] value: 5 value: 6) println.
""", "11\n22\n31\n42\n7\n11\n"),
    ("reserved_identifiers", """
Keywords := Object derivePublic: #(object, type, result).
Keywords>>set: object [ type := object. result := object + 1. ^ result ].
Keywords>>capture: object [ | result env args home hardingHome | result := object. env := 2. args := 3. home := 4. hardingHome := 5. ^ [result + env + args + home + hardingHome] ].
k := Keywords new.
(k set: 10) println.
k type println.
k result println.
(k capture: 1) value println.
object := 6.
object := object + 1.
object println.
([:type | type + 2] value: 8) println.
values := #(1, 2) collect: [:result | result + 3].
(values at: 1) println.
k::object := 12.
k::object println.
count := 1.
current := 2.
[count < 3] whileTrue: [count := count + 1].
(count + current) println.
""", "11\n10\n11\n15\n7\n10\n5\n12\n5\n"),
    ("class_return_representation", """
ClassReturn := Object derive: #().
ClassReturn>>marker [ ^ "instance" ].
ClassReturn class>>marker [ ^ "class" ].
ClassReturn class>>implicit [ 42 ].
ClassReturn class>>explicit [ ^ self ].
ClassReturn class>>empty [ ].
ClassReturn class>>block [ ^ [self] ].
ClassReturn class>>handled [ [Error signal: "boom"] on: Error do: [:ex | 7] ].
ClassReturn class>>cleaned [ [42] ensure: ["cleanup" println] ].
ClassChild := ClassReturn derive: #().
ClassChild class>>marker [ ^ "child" ].
ClassReturn implicit marker println.
ClassReturn explicit marker println.
ClassReturn empty marker println.
ClassChild implicit marker println.
(ClassChild block value) marker println.
ClassChild handled marker println.
ClassChild cleaned marker println.
""", "class\nclass\nclass\nchild\nchild\nchild\ncleanup\nchild\n"),
    ("handler_pending_operands", """
(1 + ([2] on: Error do: [:ex | 0])) println.
(1 + ([Error signal: "boom"] on: Error do: [:ex | 2])) println.
([1 + (Notification signal: "notice")] on: Notification do: [:ex | 2]) println.
(1 + ([1 missing] on: Error do: [:ex | 2])) println.
attempts := 0.
(1 + ([attempts := attempts + 1. (attempts = 1) ifTrue: [Error signal: "retry"]. 2]
  on: Error do: [:ex | ex retry])) println.
""", "3\n3\n3\n3\n3\n"),
    ("implicit_method_returns", """
ReturnSideEffect := 0.
ReturnRules := Object derivePublic: #(stored).
ReturnRules>>marker [ ^ "receiver" ].
ReturnRules>>empty [ ].
ReturnRules>>literal [ 42 ].
ReturnRules>>parameter: item [ item ].
ReturnRules>>local [ | item | item := 9 ].
ReturnRules>>store: item [ stored := item ].
ReturnRules>>global [ ReturnSideEffect := 17 ].
ReturnRules>>handled [ [Error signal: "boom"] on: Error do: [:ex | 42] ].
ReturnRules>>cleanup [ [7] ensure: ["cleanup" println] ].
ReturnRules>>choose: flag [ flag ifTrue: [^ 55]. 9 ].
ReturnRules>>explicit [ ^ [Error signal: "boom"] on: Error do: [:ex | 42] ].
r := ReturnRules new.
r empty marker println.
r literal marker println.
(r parameter: 3) marker println.
r local marker println.
(r store: 8) marker println.
r stored println.
r global marker println.
ReturnSideEffect println.
r handled marker println.
r cleanup marker println.
(r choose: false) marker println.
(r choose: true) println.
r explicit println.
[42] value println.
""", "receiver\nreceiver\nreceiver\nreceiver\nreceiver\n8\nreceiver\n17\nreceiver\ncleanup\nreceiver\nreceiver\n55\n42\n42\n"),
    ("missing_message_results", """
([1 missing] on: Error do: [:ex | 42]) println.
([nil missing] on: MessageNotUnderstood do: [:ex | ex message]) println.
(["text" missing] on: Exception do: [:ex | "string caught"]) println.
Recover := Object derive: #().
Recover>>doesNotUnderstand: selector [ ^ "recovered" ].
Recover class>>doesNotUnderstand: selector [ ^ "class recovered" ].
RecoverChild := Recover derive: #().
(Recover new missing) println.
(RecoverChild new missing: 1) println.
NilRecover := Object derive: #().
NilRecover>>doesNotUnderstand: selector [ ^ nil ].
(NilRecover new missing) isNil ifTrue: ["nil recovery" println].
(RecoverChild absent) println.
([RecoverChild new absentDnu] on: Error do: [:ex | "unreachable"]) println.
MissingClass := Object derive: #().
([MissingClass absent] on: Error do: [:ex | "class caught"]) println.
([[1 missing] ensure: ["cleanup" println]] on: Error do: [:ex | "handler"]) println.
([[Error signal: "first"] on: Error do: [:ex | ex resume: 1]]
  on: MessageNotUnderstood do: [:outer | "outer caught"]) println.
""", "42\nMessage not understood: missing\nstring caught\nrecovered\nrecovered\nnil recovery\nclass recovered\nrecovered\nclass caught\ncleanup\nhandler\nouter caught\n"),
    ("cached_polymorphic_send", """
First := Object derive: #().
First>>answer [ ^ 1 ].
Second := First derive: #().
Second>>answer [ ^ 2 ].
Reader := Object derive: #().
Reader>>read: item [ ^ item answer ].
reader := Reader new.
(reader read: First new) println.
(reader read: Second new) println.
(reader read: First new) println.
Empty := Object derive: #().
Empty>>answer [ ^ nil ].
(reader read: Empty new) isNil ifTrue: ["nil result" println].
(reader read: Second new) println.
""", "1\n2\n1\nnil result\n2\n"),
    ("application_logging", """
Log fatal: "still running".
alias := Log.
alias fatal: "alias works".
Stdout print: "Hello ".
Stdout println: "World".
Printer := Object derive: #().
Printer>>println: value [ ^ "override" ].
(Printer new println: "unused") println.
""", "FATAL still running\nFATAL alias works\nHello World\noverride\n"),
    ("numeric_specialization", """
total := 0.
i := 0.
[i < 1000] whileTrue: [total := total + i. i := i + 1].
total println.
x := 1.5.
x := x * 2.0.
(x = 3.0) ifTrue: ["float" println].
Identity := Object derive: #().
Identity>>echo: value [ ^ value ].
(Identity new echo: total) println.
""", "499500\nfloat\n499500\n"),
    ("numeric_dynamic_fallback", """
changing := 1.
changing := "dynamic".
changing println.
captured := 1.
callback := [captured := captured + 1].
callback value.
captured println.
GlobalNumber := 7.
GlobalNumber println.
shadow := 9.
[:shadow | (shadow + 1) println] value: 20.
shadow println.
""", "dynamic\n2\n7\n21\n9\n"),
    ("write_only_capture", """
Writer := Object derive: #().
Writer>>run [ | value setter | value := 1. setter := [value := 42]. setter value. ^ value ].
Writer new run println.
""", "42\n"),
    ("benchmark_queens", (ROOT / "benchmark/queens.hrd").read_text(), "92\n"),
    ("benchmark_towers", (ROOT / "benchmark/towers.hrd").read_text(), "8191\n"),
    ("nil_predicates", """
nil isNil ifTrue: ["nil" println].
nil notNil ifFalse: ["not present" println].
42 isNil ifFalse: ["number" println].
42 notNil ifTrue: ["present" println].
""", "nil\nnot present\nnumber\npresent\n"),
])


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
                compiled = run([str(binary)], options.timeout, case_dir / "compiled.log",
                               expected_error=expected_error)
                prefix = expected.get("prefix", "")
                if not interpreted.startswith(prefix) or not compiled.startswith(prefix):
                    raise RuntimeError(f"expected cleanup prefix {prefix!r}; see engine logs")
                contains = expected.get("contains", "")
                if contains and (contains not in interpreted or contains not in compiled):
                    raise RuntimeError(f"expected output containing {contains!r}; see engine logs")
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
