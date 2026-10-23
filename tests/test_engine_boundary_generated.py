"""Execute generated instance/class shims in an embedded VM (build ./granite first)."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GeneratedBoundaryTest(unittest.TestCase):
    def test_generated_class_and_instance_shims(self):
        self.assertTrue((ROOT / "granite").is_file(), "Build ./granite first")
        base = ROOT / "build" / "engine-boundary"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="generated_", dir=base) as directory:
            work = Path(directory)
            source = work / "generated.hrd"
            source.write_text('''Factory := Object derive: #().
Factory>>identity [ ^ self ].
Factory class>>identity [ ^ self ].
Factory class>>double: n [ ^ n * 2 ].
Factory class>>make [ ^ self new ].
SlotParent := Object derivePublic: #(base).
SlotParent>>baseValue [ ^ base ].
SlotParent>>baseValue: value [ base := value. ^ self ].
SlotChild := SlotParent derivePublic: #(extra).
SlotChild>>total [ ^ base + extra ].
SlotChild>>remember: value [ extra := value. ^ extra ].
SlotChild>>writer [ ^ [:value | extra := value. extra] ].
SlotChild>>readOther: other [ ^ other::base ].
SlotChild>>adder: start [ | count | count := start. ^ [:step | count := count + step. count] ].
SlotChild>>constant [ ^ [42] ].
SlotChild>>pair [ ^ [:a :b | a + b] ].
SlotChild>>triple [ ^ [:a :b :c | a + b + c] ].
SlotChild>>emptyBlock [ ^ [nil] ].
SlotChild>>countdown: start [ | remaining | remaining := start. ^ [remaining := remaining - 1. remaining > 0] ].
''')

            def run(command, log, timeout=180):
                completed = subprocess.run(command, cwd=ROOT, capture_output=True,
                                           text=True, timeout=timeout)
                (work / log).write_text(completed.stdout + completed.stderr)
                self.assertEqual(completed.returncode, 0, (work / log).read_text())
                return completed.stdout

            run([str(ROOT / "granite"), "compile", str(source),
                 "--dir:" + str(work)], "generate.log")
            host = work / "host.nim"
            imports = "\n".join('import "' + (ROOT / path).as_posix() + '"'
                                for path in ["src/harding/core/types",
                                             "src/harding/core/scheduler",
                                             "src/harding/interpreter/vm",
                                             "src/harding/runtime/runtime"])
            host.write_text('import std/tables\n' + imports + '''
import ./generated

let ctx = newSchedulerContext()
var interp = ctx.mainProcess.getInterpreter()
interp.hardingHome = "."
loadStdlib(interp)
let (_, err) = interp.evalStatements("""
Factory := Object derive: #().
Factory>>identity [ ^ nil ].
Factory class>>identity [ ^ nil ].
Factory class>>double: n [ ^ 0 ].
Factory class>>make [ ^ nil ].
ChildFactory := Factory derive: #().
SlotParent := Object derivePublic: #(base).
SlotParent>>baseValue [ ^ nil ].
SlotParent>>baseValue: value [ ^ nil ].
SlotChild := SlotParent derivePublic: #(extra).
SlotChild>>total [ ^ nil ].
SlotChild>>remember: value [ ^ nil ].
SlotChild>>writer [ ^ nil ].
SlotChild>>readOther: other [ ^ nil ].
SlotChild>>adder: start [ ^ nil ].
SlotChild>>constant [ ^ nil ].
SlotChild>>pair [ ^ nil ].
SlotChild>>triple [ ^ nil ].
SlotChild>>emptyBlock [ ^ nil ].
SlotChild>>countdown: start [ ^ nil ].
SlotChild>>loop: condition body: callback [ condition whileTrue: callback. ^ 7 ].
SlotChild>>call: callback [ ^ callback value ].
SlotChild>>call: callback with: a [ ^ callback value: a ].
SlotChild>>call: callback with: a with: b [ ^ callback value: a value: b ].
SlotChild>>call: callback with: a with: b with: c [ ^ callback value: a value: b value: c ].
SlotChild>>map: callback [ ^ #(1, 2, 3) collect: callback ].
SlotChild>>choose: callback [ ^ true ifTrue: callback ].
SlotChild>>interpretedTotal [ ^ base + extra ].
SlotChild>>interpretedSet: value [ base := value. extra := extra + 1. ^ self ].
SlotChild>>interpretedWriter [ ^ [:value | base := value. base] ].
SlotChild>>interpretedNamed [ ^ self::base ].
SlotChild>>interpretedNamed: value [ self::base := value. ^ value ].
RuntimeSlotChild := SlotChild derivePublic: #(runtimeSlot).
""")
doAssert err.len == 0, err
generated.registerCompiledMethods()
generated.bindCompiledMethodsTo(interp)
let cls = interp.globals[]["Factory"]
let child = interp.globals[]["ChildFactory"]
let instance = NodeValue(kind: vkInstance, instVal: newInstance(cls.classVal))
doAssert sendMessageInterpreted(interp, cls, "identity", @[]).classVal == cls.classVal
doAssert sendMessageInterpreted(interp, child, "identity", @[]).classVal == child.classVal
doAssert sendMessageInterpreted(interp, instance, "identity", @[]).instVal == instance.instVal
doAssert sendMessageInterpreted(interp, cls, "double:", @[toValue(21)]).intVal == 42
let created = sendMessageInterpreted(interp, child, "make", @[])
doAssert created.kind == vkInstance
doAssert created.instVal.class == child.classVal
let (_, replacementError) = interp.evalStatements("Factory class>>double: n [ ^ n + 1 ]")
doAssert replacementError.len == 0, replacementError
doAssert sendMessage(nil, cls, "double:", @[toValue(21)]).intVal == 22
let liveClass = interp.globals[]["RuntimeSlotChild"].classVal
let live = NodeValue(kind: vkInstance, instVal: newInstance(liveClass))
discard sendMessageInterpreted(interp, live, "base:", @[toValue(10)])
discard sendMessageInterpreted(interp, live, "extra:", @[toValue(4)])
discard sendMessageInterpreted(interp, live, "runtimeSlot:", @[toValue(99)])
doAssert sendMessageInterpreted(interp, live, "total", @[]).intVal == 14
doAssert sendMessageInterpreted(interp, live, "baseValue:", @[toValue(20)]).instVal == live.instVal
doAssert sendMessageInterpreted(interp, live, "base", @[]).intVal == 20
doAssert sendMessageInterpreted(interp, live, "baseValue", @[]).intVal == 20
doAssert sendMessageInterpreted(interp, live, "remember:", @[toValue(5)]).intVal == 5
doAssert sendMessageInterpreted(interp, live, "extra", @[]).intVal == 5
doAssert sendMessageInterpreted(interp, live, "runtimeSlot", @[]).intVal == 99
let writer = sendMessageInterpreted(interp, live, "writer", @[])
doAssert sendMessage(nil, writer, "value:", @[toValue(8)]).intVal == 8
doAssert sendMessageInterpreted(interp, live, "extra", @[]).intVal == 8
doAssert sendMessageInterpreted(interp, live, "readOther:", @[live]).intVal == 20
# Interpreted methods invoke native closures without consuming their environments.
let constant = sendMessageInterpreted(interp, live, "constant", @[])
doAssert sendMessageInterpreted(interp, live, "call:", @[constant]).intVal == 42
doAssert sendMessageInterpreted(interp, live, "choose:", @[constant]).intVal == 42
let adder = sendMessageInterpreted(interp, live, "adder:", @[toValue(10)])
doAssert sendMessageInterpreted(interp, live, "call:with:", @[adder, toValue(2)]).intVal == 12
doAssert sendMessageInterpreted(interp, live, "call:with:", @[adder, toValue(3)]).intVal == 15
let mapped = sendMessageInterpreted(interp, live, "map:", @[adder])
doAssert sendMessageInterpreted(interp, mapped, "at:", @[toValue(2)]).intVal == 21
let pair = sendMessageInterpreted(interp, live, "pair", @[])
doAssert sendMessageInterpreted(interp, live, "call:with:with:", @[pair, toValue(4), toValue(5)]).intVal == 9
let triple = sendMessageInterpreted(interp, live, "triple", @[])
doAssert sendMessageInterpreted(interp, live, "call:with:with:with:", @[triple, toValue(4), toValue(5), toValue(6)]).intVal == 15
let empty = sendMessageInterpreted(interp, live, "emptyBlock", @[])
doAssert isNilValue(sendMessageInterpreted(interp, live, "call:", @[empty]))
var wrongArity = false
try:
  discard sendMessageInterpreted(interp, live, "call:", @[pair])
except ValueError:
  wrongArity = true
doAssert wrongArity
doAssert sendMessageInterpreted(interp, live, "call:", @[constant]).intVal == 42
doAssert invokeBlock(interp, constant.blockVal, @[]).intVal == 42
doAssert invokeBlock(interp, pair.blockVal, @[toValue(7), toValue(8)]).intVal == 15
let condition = sendMessageInterpreted(interp, live, "countdown:", @[toValue(3)])
doAssert sendMessageInterpreted(interp, live, "loop:body:", @[condition, constant]).intVal == 7
doAssert not invokeBlock(interp, condition.blockVal, @[]).boolVal
# Native inherited slots use accessors for their concrete, self-contained layout.
generated.registerSuperclassHierarchy()
let native = generated.toValue(generated.newClass_''' + "SlotChild".encode().hex().upper() + '''())
discard sendMessage(nil, native, "base:", @[toValue(30)])
discard sendMessage(nil, native, "extra:", @[toValue(2)])
doAssert sendMessage(nil, native, "baseValue", @[]).intVal == 30
doAssert sendMessage(nil, native, "total", @[]).intVal == 32
let originalOwner = native.instVal.compiledOwner
let originalPointer = native.instVal.nimValue
doAssert bindNativeInstanceTo(interp, native)
doAssert native.instVal.class == interp.globals[]["SlotChild"].classVal
doAssert native.instVal.slots.len == 0
doAssert sendMessageInterpreted(interp, native, "interpretedTotal", @[]).intVal == 32
doAssert sendMessageInterpreted(interp, native, "interpretedSet:", @[toValue(40)]).instVal == native.instVal
doAssert getSlotValue(native, "base").intVal == 40
doAssert getSlotValue(native, "extra").intVal == 3
doAssert sendMessageHybrid(native, "interpretedTotal", @[]).intVal == 43
doAssert sendMessageInterpreted(interp, native, "interpretedNamed:", @[toValue(41)]).intVal == 41
doAssert sendMessageInterpreted(interp, native, "interpretedNamed", @[]).intVal == 41
doAssert sendMessageInterpreted(interp, native, "slotAt:", @[toValue("base")]).intVal == 41
discard sendMessageInterpreted(interp, native, "slotAt:put:", @[toValue("base"), toValue(42)])
doAssert getSlotValue(native, "base").intVal == 42
let interpretedWriter = sendMessageInterpreted(interp, native, "interpretedWriter", @[])
doAssert invokeBlock(interp, interpretedWriter.blockVal, @[toValue(50)]).intVal == 50
doAssert getSlotValue(native, "base").intVal == 50
let jsonClass = interp.globals[]["Json"]
let jsonText = sendMessageInterpreted(interp, jsonClass, "stringify:", @[native])
doAssert jsonText.strVal == """{"base":50,"extra":3}"""
let clone = sendMessageInterpreted(interp, native, "clone", @[])
doAssert clone.instVal != native.instVal
discard sendMessageInterpreted(interp, clone, "interpretedSet:", @[toValue(70)])
doAssert getSlotValue(native, "base").intVal == 50
doAssert getSlotValue(clone, "base").intVal == 70
doAssert native.instVal.compiledOwner == originalOwner
doAssert native.instVal.nimValue == originalPointer
# Runtime method replacement sees the same native fields, including after a send cache warms.
var cache: CompiledSendCache
doAssert sendMessageCached(nil, native, "total", @[], cache).intVal == 53
let (_, redefineError) = interp.evalStatements("SlotChild>>total [ ^ base + extra + 1 ]")
doAssert redefineError.len == 0, redefineError
doAssert sendMessageCached(nil, native, "total", @[], cache).intVal == 54
# Binding rejects a mismatched live layout without changing class identity or storage.
let rejected = generated.toValue(generated.newClass_''' + "SlotChild".encode().hex().upper() + '''())
let savedClass = rejected.instVal.class
let liveSlotClass = interp.globals[]["SlotChild"].classVal
let savedNames = liveSlotClass.allSlotNames
liveSlotClass.allSlotNames = @["wrong"]
doAssert not bindNativeInstanceTo(interp, rejected)
doAssert rejected.instVal.class == savedClass
doAssert rejected.instVal.nativeSlots == nil
var invalidLayout = false
try:
  discard getSlotValue(native, "base")
except ValueError:
  invalidLayout = true
doAssert invalidLayout
liveSlotClass.allSlotNames = savedNames
doAssert getSlotValue(native, "base").intVal == 50
unbindCompiledMethodsFrom(interp)
echo "generated boundary passed"
''')
            for mm in ("arc", "orc"):
                with self.subTest(memory_manager=mm):
                    binary = work / ("host_" + mm)
                    run(["nim", "c", "--mm:" + mm, "-o:" + str(binary), str(host)],
                        "build_" + mm + ".log")
                    self.assertEqual(run([str(binary)], "run_" + mm + ".log", 60),
                                     "generated boundary passed\n")


if __name__ == "__main__":
    unittest.main()
