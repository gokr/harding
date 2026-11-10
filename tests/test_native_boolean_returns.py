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
