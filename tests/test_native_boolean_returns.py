"""Execute source-derived bool returns and their dynamic boundary fallbacks."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''
BoolPredicate := Object derivePublic: #{limit -> Integer}.
BoolPredicate>>below: n [ | next | next := n + 1. ^next < limit ].
BoolPredicate>>choose [ (self below: 3) ifTrue: [^11]. ^22 ].
BoolPredicate>>count: n [ | i | i := 0. [self below: i] whileTrue: [i := i + 1]. ^i ].
BoolChild := BoolPredicate derivePublic: #(extra).
BoolSource := Object derivePublic: #(held, calls).
BoolSource>>initialize [calls := 0].
BoolSource>>next [calls := calls + 1. ^held].
BoolDriver := Object derive: #().
BoolDriver>>chooseFrom: source [ (source next below: 3) ifTrue: [^11]. ^22 ].
'''


def execute(command):
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240)
    if done.returncode:
        raise AssertionError(str(command) + '\n' + done.stdout + done.stderr)
    return done


class MirroredHierarchy(unittest.TestCase):
    """Compiled classes mirror Harding inheritance in the Nim type hierarchy."""

    SOURCE = """
Vehicle := Object derivePublic: #{#wheels -> Integer, #owner -> nil}.
Vehicle>>kind [ ^#vehicle ].
Vehicle>>describe [ ^wheels ].
Vehicle>>bump [ wheels := wheels + 1. ^self ].
Car := Vehicle derivePublic: #{#doors -> Integer}.
Car>>kind [ ^#car ].
Truck := Car derivePublic: #(capacity).
Truck>>kind [ ^#truck ].
Holder := Object derivePublic: #(held).
Holder>>ship [ ^held describe ].
Holder>>shippedKind [ ^held kind ].
"""

    HOST = """
initRuntime()
registerCompiledMethods()
registerSuperclassHierarchy()
proc make(name: string): NodeValue =
  case name
  of "Vehicle": newClass_56656869636C65().toValue()
  of "Car": newClass_436172().toValue()
  of "Truck": newClass_547275636B().toValue()
  else: quit("bad name")

# A parent-typed slot holds instances of every subclass and shares one storage.
proc ship(name: string): int =
  let holder = newClass_486F6C646572().toValue()
  let value = make(name)
  discard setSlotValue(holder, "held", value)
  discard sendMessage(nil, value, "bump", [])
  discard sendMessage(nil, value, "bump", [])
  sendMessage(nil, holder, "ship", []).intVal

proc shippedKind(name: string): string =
  let holder = newClass_486F6C646572().toValue()
  discard setSlotValue(holder, "held", make(name))
  sendMessage(nil, holder, "shippedKind", []).symVal

doAssert ship("Vehicle") == 2, $ship("Vehicle")
doAssert ship("Car") == 2, $ship("Car")
doAssert ship("Truck") == 2, $ship("Truck")
# Dispatch still follows the concrete class through a parent-typed slot.
doAssert shippedKind("Vehicle") == "vehicle"
doAssert shippedKind("Car") == "car"
doAssert shippedKind("Truck") == "truck"
# The inherited field is one storage location regardless of the concrete class.
let car = newClass_436172().toValue()
discard sendMessage(nil, car, "bump", [])
doAssert sendMessage(nil, car, "describe", []).intVal == 1
discard setSlotValue(car, "doors", toValue(4))
doAssert getSlotValue(car, "doors").intVal == 4
doAssert getSlotValue(car, "wheels").intVal == 1
echo "ok"
"""

    def test_subclass_storage_and_dispatch(self):
        base = ROOT / 'build/native-boolean-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'hier.hrd'
            source.write_text(self.SOURCE)
            execute([str(ROOT / 'granite'), 'compile', str(source), '--home:' + str(ROOT),
                     '--dir:' + str(work), '-o:hier'])
            generated = (work / 'hier.nim').read_text()
            # The Nim types mirror the three-level Harding chain, parents first.
            self.assertIn(mangle_type('Car') + 'Obj* {.inheritable.} = object of ' +
                          mangle_type('Vehicle') + 'Obj', generated)
            self.assertIn(mangle_type('Truck') + 'Obj* {.inheritable.} = object of ' +
                          mangle_type('Car') + 'Obj', generated)
            # Inherited storage is declared exactly once, on the root.
            self.assertEqual(generated.count('  wheels*: int'), 1)
            self.assertEqual(generated.count('  owner*: NodeValue'), 1)
            host = work / 'hierhost.nim'
            imports = '\n'.join('import "' + str(ROOT / path) + '"' for path in [
                'src/harding/core/types', 'src/harding/core/scheduler',
                'src/harding/interpreter/vm', 'src/harding/runtime/runtime'])
            host.write_text('import std/tables\n' + imports + '\nimport ./hier\n' + self.HOST)
            for mm in ['arc', 'orc']:
                with self.subTest(mm=mm):
                    binary = work / ('hierhost_' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--out:' + str(binary), str(host)])
                    self.assertEqual(execute([str(binary)]).stdout.strip(), 'ok')


def mangle_type(name):
    return 'Class_' + ''.join(f'{ord(c):02X}' for c in name)


class NativeIntegerResults(unittest.TestCase):
    def test_int_result_and_fallbacks(self):
        base = ROOT / 'build/native-boolean-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'integers.hrd'
            source.write_text(SOURCE + '''
IntCounter := Object derivePublic: #(limit).
IntCounter>>advanceBy: n [ | k | k := n * 2. ^k + 1 ].
IntCounter>>run [ | i | i := 0. [(self advanceBy: i) < limit] whileTrue: [i := i + 1]. ^i ].
''')
            execute([str(ROOT / 'granite'), 'compile', str(source), '--home:' + str(ROOT),
                     '--dir:' + str(work), '-o:integers'])
            generated = (work / 'integers.nim').read_text()
            self.assertIn('integerResult_', generated)
            self.assertIn('hardingIntegerOut: var int): bool', generated)
            host = work / 'inthost.nim'
            imports = '\n'.join('import "' + str(ROOT / path) + '"' for path in [
                'src/harding/core/types', 'src/harding/core/scheduler',
                'src/harding/interpreter/vm', 'src/harding/runtime/runtime'])
            host.write_text('import std/tables\n' + imports + '\nimport ./integers\n' + '''
initRuntime()
registerCompiledMethods()
registerSuperclassHierarchy()
let counter = newClass_496E74436F756E746572().toValue()
discard setSlotValue(counter, "limit", toValue(9))
# i -> i*2+1 grows, so the loop stops once that reaches the limit. Expected
# values were taken from the interpreter, not hand-derived: limit 9 -> 4.
doAssert sendMessage(nil, counter, "run", []).intVal == 4
discard setSlotValue(counter, "limit", toValue(2))
doAssert sendMessage(nil, counter, "run", []).intVal == 1
# Replacing the method with one returning a non-Integer must fall back to the
# ordinary comparison. "seven" < limit is false, so the loop runs zero times; had
# the string been coerced to an int it would read as 0, satisfy 0 < limit, and
# spin forever. A fast answer of 0 therefore shows no coercion happened.
var replacementCalls = 0
proc nonInteger(receiver: NodeValue, args: openArray[NodeValue]): NodeValue =
  inc replacementCalls
  toValue("seven")
registerCompiledMethod("IntCounter", "advanceBy:", nonInteger)
doAssert sendMessage(nil, counter, "run", []).intVal == 0
doAssert replacementCalls > 0
echo "ok"
''')
            for mm in ['arc', 'orc']:
                with self.subTest(mm=mm):
                    binary = work / ('inthost_' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--out:' + str(binary), str(host)])
                    self.assertEqual(execute([str(binary)]).stdout.strip(), 'ok')


class NativeBooleanReturns(unittest.TestCase):
    def test_native_result_and_replacement_fallbacks(self):
        base = ROOT / 'build/native-boolean-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'predicates.hrd'
            source.write_text(SOURCE)
            execute([str(ROOT / 'granite'), 'compile', str(source), '--home:' + str(ROOT),
                     '--dir:' + str(work), '-o:predicates'])
            generated = (work / 'predicates.nim').read_text()
            self.assertIn('): bool =', generated)
            self.assertIn('if booleanCall_', generated)
            self.assertIn('return (next < self[].limit)', generated)
            host = work / 'host.nim'
            program = '''
initRuntime()
registerCompiledMethods()
registerSuperclassHierarchy()
let predicate = newClass_426F6F6C507265646963617465().toValue()
discard setSlotValue(predicate, "limit", toValue(8))
doAssert sendMessage(nil, predicate, "choose", []).intVal == 11
doAssert sendMessage(nil, predicate, "count:", [toValue(0)]).intVal == 7
let child = newClass_426F6F6C4368696C64().toValue()
discard setSlotValue(child, "limit", toValue(2))
doAssert sendMessage(nil, child, "choose", []).intVal == 22
let source = newClass_426F6F6C536F75726365().toValue()
discard sendMessage(nil, source, "initialize", [])
discard setSlotValue(source, "held", predicate)
let driver = newClass_426F6F6C447269766572().toValue()
doAssert sendMessage(nil, driver, "chooseFrom:", [source]).intVal == 11
doAssert getSlotValue(source, "calls").intVal == 1
let getter = slotGetters["BoolPredicate::limit"]
let setter = slotSetters["BoolPredicate::limit"]
proc differentLimit(storage: pointer): NodeValue {.nimcall.} = toValue(2)
registerSlotAccessor("BoolPredicate", "limit", differentLimit, setter)
doAssert sendMessage(nil, predicate, "choose", []).intVal == 22
registerSlotAccessor("BoolPredicate", "limit", getter, setter)
doAssert sendMessage(nil, predicate, "choose", []).intVal == 11
let original = findCompiledMethod("BoolPredicate", "below:")
var calls = 0
proc replaced(receiver: NodeValue, args: openArray[NodeValue]): NodeValue =
  inc calls
  toValue(false)
registerCompiledMethod("BoolPredicate", "below:", replaced)
doAssert sendMessage(nil, driver, "chooseFrom:", [source]).intVal == 22
doAssert calls == 1
doAssert getSlotValue(source, "calls").intVal == 2
proc nonBoolean(receiver: NodeValue, args: openArray[NodeValue]): NodeValue = toValue(99)
registerCompiledMethod("BoolPredicate", "below:", nonBoolean)
var rejected = false
try:
  discard sendMessage(nil, predicate, "choose", [])
except ValueError:
  rejected = true
doAssert rejected
registerCompiledMethod("BoolPredicate", "below:", original)
doAssert sendMessage(nil, predicate, "choose", []).intVal == 11
let context = newSchedulerContext()
var interp = context.mainProcess.getInterpreter()
interp.hardingHome = "."
loadStdlib(interp)
let (_, setupError) = interp.evalStatements("""DECLARATIONS
VmPredicate := BoolPredicate new.
VmPredicate limit: 2.
""")
doAssert setupError.len == 0, setupError
bindCompiledMethodsTo(interp)
doAssert bindNativeInstanceTo(interp, predicate)
interp.globals[]["NativePredicate"] = predicate
let (value, error) = interp.doit("NativePredicate choose")
doAssert error.len == 0, error
doAssert value.intVal == 11
let (vmValue, vmError) = interp.doit("VmPredicate choose")
doAssert vmError.len == 0, vmError
doAssert vmValue.intVal == 22
echo "ok"
'''
            imports = '\n'.join('import "' + str(ROOT / path) + '"' for path in [
                'src/harding/core/types', 'src/harding/core/scheduler',
                'src/harding/interpreter/vm', 'src/harding/runtime/runtime'])
            host.write_text('import std/tables\n' + imports + '\nimport ./predicates\n' +
                            program.replace('DECLARATIONS', SOURCE))
            for mm in ['arc', 'orc']:
                with self.subTest(mm=mm):
                    binary = work / ('host_' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--out:' + str(binary), str(host)])
                    self.assertEqual(execute([str(binary)]).stdout.strip(), 'ok')


if __name__ == '__main__':
    unittest.main()
