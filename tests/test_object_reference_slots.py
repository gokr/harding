"""Execute compact object-slot storage through native and interpreted boundaries."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''
RefItem := Object derivePublic: #{number -> Integer}.
RefChild := RefItem derivePublic: #(extra).
RefHolder := Object derivePublic: #{item -> RefItem, dynamic -> nil}.
RefHolder>>store: candidate [ item := candidate. ^candidate ].
RefHolder>>storeInline: candidate [ true ifTrue: [item := candidate]. ^candidate ].
RefHolder>>readCandidate: candidate [ item := candidate. ^candidate number ].
RefHolder>>copyFrom: source [ item := source item. ^item ].
RefHolder>>storeAfter: action value: candidate [ action value. item := candidate. ^item ].
RefHolder>>conditional: candidate [ candidate = 7 ifTrue: [^123]. item := candidate. ^item ].
RefHolderChild := RefHolder derivePublic: #(padding).
RefSource := Object derivePublic: #(calls, held).
RefSource>>initialize [ calls := 0 ].
RefSource>>next [ calls := calls + 1. ^held ].
RefHolder>>copyOnce: source [ item := source next item. ^item ].
'''


def execute(command):
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240)
    if done.returncode:
        raise AssertionError(str(command) + '\n' + done.stdout + done.stderr)
    return done


class ObjectReferences(unittest.TestCase):
    def test_owned_identity_nullable_subclasses_and_host_bridge(self):
        base = ROOT / 'build/object-reference-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'reference_slots.hrd'
            source.write_text(SOURCE)
            execute([str(ROOT / 'granite'), 'compile', str(source), '--home:' + str(ROOT),
                     '--dir:' + str(work), '-o:reference_slots'])
            generated = (work / 'reference_slots.nim').read_text()
            self.assertIn('item*: Instance', generated)
            self.assertIn('dynamic*: NodeValue', generated)
            self.assertIn('hardingNative_candidate: Instance', generated)
            self.assertIn('let hardingReferenceValue =', generated)
            self.assertIn('compiledObjectArgumentMatches', generated)
            imports = '\n'.join('import "' + str(ROOT / path) + '"' for path in [
                'src/harding/core/types', 'src/harding/core/scheduler',
                'src/harding/interpreter/vm', 'src/harding/runtime/runtime',
                'src/harding/runtime/compiled_support'])
            host = work / 'host.nim'
            cls = lambda name: 'Class_' + name.encode().hex().upper()
            program = '''
initRuntime()
registerCompiledMethods()
registerSuperclassHierarchy()
let holderNative = newHOLDER()
let holder = holderNative.toValue()
doAssert sizeof(holderNative.item) == sizeof(Instance)
doAssert sizeof(holderNative.item) < sizeof(NodeValue)
doAssert isNilValue(getSlotValue(holder, "item"))
block:
  let item = newITEM().toValue()
  discard setSlotValue(item, "number", toValue(42))
  discard setSlotValue(holder, "item", item)
  doAssert getSlotValue(holder, "item").instVal == item.instVal
# The holder owns the wrapper and its native storage after the creator's scope.
doAssert getSlotValue(getSlotValue(holder, "item"), "number").intVal == 42
let initial = getSlotValue(holder, "item")
doAssert sendMessage(nil, holder, "store:", [initial]).instVal == initial.instVal
doAssert sendMessage(nil, holder, "storeInline:", [initial]).instVal == initial.instVal
doAssert isNilValue(sendMessage(nil, holder, "store:", []))
doAssert holderNative.item == nil
discard sendMessage(nil, holder, "store:", [initial])
doAssert sendMessage(nil, holder, "readCandidate:", [initial]).intVal == 42
doAssert sendMessage(nil, holder, "conditional:", [toValue(7)]).intVal == 123
let copy = newHOLDER().toValue()
doAssert sendMessage(nil, copy, "copyFrom:", [holder]).instVal == initial.instVal
let derivedCopy = newHOLDERCHILD().toValue()
doAssert sendMessage(nil, derivedCopy, "store:", [initial]).instVal == initial.instVal
doAssert sendMessage(nil, derivedCopy, "copyFrom:", [holder]).instVal == initial.instVal
let source = newClass_526566536F75726365().toValue()
discard sendMessage(nil, source, "initialize", [])
discard sendMessage(nil, source, "held:", [holder])
doAssert sendMessage(nil, copy, "copyOnce:", [source]).instVal == initial.instVal
doAssert getSlotValue(source, "calls").intVal == 1
let child = newCHILD().toValue()
discard setSlotValue(child, "number", toValue(99))
discard sendMessage(nil, holder, "item:", [child])
doAssert sendMessage(nil, holder, "item", []).instVal == child.instVal
doAssert getSlotValue(getSlotValue(holder, "item"), "number").intVal == 99
discard setSlotValue(child, "number", toValue(100))
doAssert getSlotValue(getSlotValue(holder, "item"), "number").intVal == 100
let old = holderNative.item
var rejected = false
try:
  discard setSlotValue(holder, "item", toValue(5))
except CompiledHardingError:
  rejected = true
doAssert rejected
doAssert holderNative.item == old
rejected = false
try:
  discard sendMessage(nil, holder, "item:", [holder])
except CompiledHardingError:
  rejected = true
doAssert rejected
doAssert holderNative.item == old
discard setSlotValue(holder, "item", NodeValue(kind: vkNil))
doAssert holderNative.item == nil
discard setSlotValue(holder, "item", nilValue())
doAssert holderNative.item == nil
let derivedHolder = newHOLDERCHILD().toValue()
discard setSlotValue(derivedHolder, "item", child)
doAssert getSlotValue(derivedHolder, "item").instVal == child.instVal
# An accessor replacement must still redirect a compact reference-slot read.
proc redirected(storage: pointer): NodeValue {.nimcall.} = NodeValue(kind: vkNil)
let getter = slotGetters["RefHolder::item"]
let setter = slotSetters["RefHolder::item"]
registerSlotAccessor("RefHolder", "item", redirected, setter)
doAssert isNilValue(sendMessage(nil, holder, "item", []))
doAssert isNilValue(sendMessage(nil, copy, "copyFrom:", [holder]))
discard sendMessage(nil, copy, "copyOnce:", [source])
doAssert getSlotValue(source, "calls").intVal == 2
registerSlotAccessor("RefHolder", "item", getter, setter)
proc wrongGetter(receiver: NodeValue, args: openArray[NodeValue]): NodeValue = toValue(9)
let originalMethod = findCompiledMethod("RefHolder", "item")
registerCompiledMethod("RefHolder", "item", wrongGetter)
rejected = false
try:
  discard sendMessage(nil, copy, "copyFrom:", [holder])
except CompiledHardingError:
  rejected = true
doAssert rejected
registerCompiledMethod("RefHolder", "item", originalMethod)
# A callback can replace the slot setter after the argument guard has run.
var setterCalls = 0
proc observingSet(storage: pointer, value: NodeValue): NodeValue {.nimcall.} =
  inc setterCalls
  setter(storage, value)
proc changeSetter(): NodeValue {.cdecl.} =
  registerSlotAccessor("RefHolder", "item", getter, observingSet)
  NodeValue(kind: vkNil)
let action = createBlock0(changeSetter, 0)
doAssert sendMessage(nil, holder, "storeAfter:value:", [action, child]).instVal == child.instVal
doAssert setterCalls == 1
registerSlotAccessor("RefHolder", "item", getter, setter)
# A value owned by the VM can inhabit a native holder's reference slot.
let context = newSchedulerContext()
var interp = context.mainProcess.getInterpreter()
interp.hardingHome = "."
loadStdlib(interp)
let (_, setupError) = interp.evalStatements("""VMDECLARATIONS
VmItem := RefItem new.
VmItem number: 17.
""")
doAssert setupError.len == 0, setupError
bindCompiledMethodsTo(interp)
let vmItem = interp.globals[]["VmItem"]
discard setSlotValue(holder, "item", vmItem)
doAssert getSlotValue(holder, "item").instVal == vmItem.instVal
# Binding a native instance exposes the same reference through nativeSlots.
doAssert bindNativeInstanceTo(interp, holder)
interp.globals[]["NativeHolder"] = holder
let (answer, readError) = interp.doit("NativeHolder::item number")
doAssert readError.len == 0, readError
doAssert answer.intVal == 17
let (_, clearError) = interp.doit("NativeHolder::item := nil")
doAssert clearError.len == 0, clearError
doAssert holderNative.item == nil
let (_, writeError) = interp.doit("NativeHolder::item := VmItem")
doAssert writeError.len == 0, writeError
doAssert holderNative.item == vmItem.instVal
let (recovery, badError) = interp.doit("[NativeHolder::item := 3] on: Error do: [:e | 123]")
doAssert badError.len == 0, badError
doAssert recovery.intVal == 123
doAssert holderNative.item == vmItem.instVal
let (storedViaMethod, methodError) = interp.doit("NativeHolder store: VmItem")
doAssert methodError.len == 0, methodError
doAssert storedViaMethod.instVal == vmItem.instVal
let (copiedViaMethod, copyError) = interp.doit("NativeHolder copyFrom: NativeHolder")
doAssert copyError.len == 0, copyError
doAssert copiedViaMethod.instVal == vmItem.instVal
echo "ok"
'''
            for label, name in [('HOLDERCHILD', 'RefHolderChild'), ('HOLDER', 'RefHolder'),
                                ('CHILD', 'RefChild'), ('ITEM', 'RefItem')]:
                program = program.replace('new' + label + '()', 'new' + cls(name) + '()')
            program = program.replace('VMDECLARATIONS', SOURCE)
            host.write_text('import std/tables\n' + imports + '\nimport ./reference_slots\n' + program)
            for mm in ['arc', 'orc']:
                with self.subTest(mm=mm):
                    binary = work / ('host_' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--out:' + str(binary), str(host)])
                    self.assertEqual(execute([str(binary)]).stdout.strip(), 'ok')


if __name__ == '__main__':
    unittest.main()
