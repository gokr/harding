"""Executed generated-code tests for guarded native slot access and arithmetic."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''
DirectCounter := Object derivePublic: #{#count -> 0, #other -> 2, #step -> 0.5, #flag -> false, #text -> "ok"}.
DirectCounter>>bump [ count := count + 1. ^count ].
DirectCounter>>compute [ ^(count + other) * 3 ].
DirectCounter>>withLocal [ | amount | amount := 3. ^count + amount ].
DirectCounter>>fraction [ step := step + 0.5. ^step ].
DirectCounter>>less [ ^count < other ].
DirectCounter>>block [ ^[count := count + 1. count] ].
DirectCounter>>once: action [ ^count := action value ].
DirectChild := DirectCounter derivePublic: #(padding).
DirectChild>>setup [ padding := 99. ^self ].
'''


def execute(command, cwd=ROOT, timeout=240):
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=timeout)
    if completed.returncode:
        raise AssertionError(str(command) + '\n' + completed.stdout + completed.stderr)
    return completed


class DirectSlots(unittest.TestCase):
    def test_native_layout_guards_and_interpreter_fallback(self):
        base = ROOT / 'build/direct-slots-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'direct.hrd'
            source.write_text(SOURCE)
            execute([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work)])
            generated = (work / 'direct.nim').read_text()
            cls = 'Class_' + 'DirectCounter'.encode().hex().upper()
            # The fast branch uses the retained native owner and machine arithmetic.
            self.assertIn('compiledOwner of ' + cls, generated)
            self.assertIn('nativeSlots == nil', generated)
            self.assertIn('compiledSlotAccessorVersion', generated)
            self.assertIn(cls + '(self.instVal.compiledOwner)[].hardingUser636F756E74 + 1', generated)
            self.assertIn('getSlotValue(self, "count")', generated)
            self.assertIn('setSlotValue(self, "count", value)', generated)
            host = work / 'host.nim'
            imports = '\n'.join('import "' + str(ROOT / path) + '"' for path in [
                'src/harding/core/types', 'src/harding/core/scheduler',
                'src/harding/interpreter/vm', 'src/harding/runtime/runtime'])
            host.write_text('import std/tables\n' + imports + '\nimport ./direct\n' + '''
registerCompiledMethods()
registerSuperclassHierarchy()
let native = newClass_446972656374436F756E746572().toValue()
doAssert sendMessage(nil, native, "bump", @[]).intVal == 1
doAssert sendMessage(nil, native, "compute", @[]).intVal == 9
doAssert sendMessage(nil, native, "withLocal", @[]).intVal == 4
doAssert sendMessage(nil, native, "fraction", @[]).floatVal == 1.0
doAssert sendMessage(nil, native, "less", @[]).boolVal
discard sendMessage(nil, native, "flag:", @[toValue(true)])
discard sendMessage(nil, native, "text:", @[toValue("updated")])
doAssert sendMessage(nil, native, "flag", @[]).boolVal
doAssert sendMessage(nil, native, "text", @[]).strVal == "updated"
let child = newClass_4469726563744368696C64().toValue()
doAssert sendMessage(nil, child, "setup", @[]).kind == vkInstance
doAssert sendMessage(nil, child, "bump", @[]).intVal == 1
doAssert getSlotValue(child, "padding").intVal == 99
let closure = sendMessage(nil, native, "block", @[])
doAssert sendMessage(nil, closure, "value", @[]).intVal == 2

# Accessor replacement invalidates warmed direct paths, including arithmetic.
proc replacementGet(storage: pointer): NodeValue {.nimcall.} = toValue(30)
proc replacementSet(storage: pointer, value: NodeValue): NodeValue {.nimcall.} = value
let originalGet = slotGetters["DirectCounter::count"]
let originalSet = slotSetters["DirectCounter::count"]
registerSlotAccessor("DirectCounter", "count", replacementGet, replacementSet)
doAssert sendMessage(nil, native, "compute", @[]).intVal == 96
registerSlotAccessor("DirectCounter", "count", originalGet, originalSet)
doAssert sendMessage(nil, native, "compute", @[]).intVal == 12

# VM-owned storage must never be cast to a compiled layout; declared writes are
# checked, while an undeclared VM class can still supply dynamic values.
let context = newSchedulerContext()
var interp = context.mainProcess.getInterpreter()
interp.hardingHome = "."
loadStdlib(interp)
let (_, setupError) = interp.evalStatements("""
DirectCounter := Object derivePublic: #{#count -> 0, #other -> 2, #step -> 0.5, #flag -> false, #text -> "ok"}.
DirectCounter>>bump [ ^nil ].
DirectCounter>>compute [ ^nil ].
DirectCounter>>fraction [ ^nil ].
DirectCounter>>less [ ^nil ].
DirectCounter>>block [ ^nil ].
DirectCounter>>once: action [ ^nil ].
VmCounter := DirectCounter new.
""")
doAssert setupError.len == 0, setupError
bindCompiledMethodsTo(interp)
let vmCounter = interp.globals[]["VmCounter"]
let (answer, error) = interp.doit("VmCounter bump")
doAssert error.len == 0, error
doAssert answer.intVal == 1
let (rejectedWrite, mutateError) = interp.doit("[VmCounter::count := 1.5] on: Error do: [:ex | 23]")
doAssert mutateError.len == 0, mutateError
doAssert rejectedWrite.intVal == 23
let (preserved, preservedError) = interp.doit("VmCounter compute")
doAssert preservedError.len == 0, preservedError
doAssert preserved.intVal == 9
let (_, sideEffectError) = interp.evalStatements("Calls := 0")
doAssert sideEffectError.len == 0
let (assigned, assignError) = interp.doit("VmCounter once: [Calls := Calls + 1. 8]")
doAssert assignError.len == 0, assignError
doAssert assigned.intVal == 8
doAssert interp.globals[]["Calls"].intVal == 1
let (_, replaceError) = interp.evalStatements("DirectCounter>>compute [^77]")
doAssert replaceError.len == 0, replaceError
let (replaced, replacedError) = interp.doit("VmCounter compute")
doAssert replacedError.len == 0, replacedError
doAssert replaced.intVal == 77

# A bridged native object keeps the existing layout validation path.
doAssert bindNativeInstanceTo(interp, native)
interp.globals[]["NativeCounter"] = native
let (boundAnswer, boundError) = interp.doit("NativeCounter bump")
doAssert boundError.len == 0, boundError
doAssert boundAnswer.intVal == 3
let liveClass = native.instVal.class
let savedContract = liveClass.slotContracts["count"]
liveClass.slotContracts["count"] = SlotContract(kind: scFloat)
let incompatible = newClass_446972656374436F756E746572().toValue()
doAssert not bindNativeInstanceTo(interp, incompatible)
var contractRejected = false
try:
  discard getSlotValue(native, "count")
except ValueError:
  contractRejected = true
doAssert contractRejected
liveClass.slotContracts["count"] = savedContract
liveClass.allSlotNames.add("layoutDrift")
var rejected = false
try:
  discard sendMessage(nil, native, "bump", @[])
except ValueError:
  rejected = true
doAssert rejected
liveClass.allSlotNames.setLen(liveClass.allSlotNames.len - 1)
unbindCompiledMethodsFrom(interp)
echo "direct slots passed"
''')
            for mm in ['arc', 'orc']:
                with self.subTest(mm=mm):
                    binary = work / ('host-' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('cache-' + mm)),
                             '-o:' + str(binary), str(host)])
                    ran = execute([str(binary)])
                    self.assertEqual(ran.stdout, 'direct slots passed\n')
                    self.assertEqual(ran.stderr, '')


if __name__ == '__main__':
    unittest.main()
