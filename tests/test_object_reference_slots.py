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
RefHolderChild := RefHolder derivePublic: #(padding).
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
            imports = '\n'.join('import "' + str(ROOT / path) + '"' for path in [
                'src/harding/core/types', 'src/harding/core/scheduler',
                'src/harding/interpreter/vm', 'src/harding/runtime/runtime'])
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
