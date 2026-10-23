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
Factory class>>makeNamed [ ^ SlotChild new ].
Factory>>makeNamed [ ^ SlotChild new ].
Factory>>maker [ ^ [SlotChild new] ].
Factory>>nestedMaker [ ^ [[SlotChild new]] ].
Factory>>classReference [ ^ SlotChild ].
Factory>>aliasNew [ ^ AliasTarget new ].
Factory>>aliasAnswer [ ^ AliasTarget answer ].
Factory>>aliasReader [ ^ [[AliasTarget]] ].
Factory>>globalReader [ ^ LiveSetting ].
Factory>>globalBlock [ ^ [LiveSetting] ].
Factory>>localAlias [ | target | target := AliasTarget. ^ target new ].
Factory>>shadow: AliasTarget [ ^ [AliasTarget] ].
Factory>>classArgument: target [ ^ target answer ].
Factory>>importedReader [ ^ [LibrarySetting] ].
Factory>>writeGlobal: value [ LiveSetting := value. ^ LiveSetting ].
Factory>>globalWriter [ ^ [:value | LiveSetting := value] ].
Factory>>nestedWriter [ ^ [[:value | CreatedSetting := value]] ].
Factory>>libraryWriter [ ^ [:value | LibrarySetting := value. LibrarySetting] ].
Factory>>protectedWriter [ Object := nil ].
Factory>>shadowWrite: LiveSetting [ ^ [:value | LiveSetting := value. LiveSetting] ].
Factory class>>writeGlobal: value [ LiveSetting := value. ^ LiveSetting ].
Factory>>sideEffectWriter: next [ ^ [CreatedSetting := next value] ].
Factory>>counter [ | count | count := 0. ^ [count := count + 1] ].
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
Factory class>>makeNamed [ ^ nil ].
Factory>>makeNamed [ ^ nil ].
Factory>>maker [ ^ nil ].
Factory>>nestedMaker [ ^ nil ].
Factory>>classReference [ ^ nil ].
Factory>>aliasNew [ ^ nil ].
Factory>>aliasAnswer [ ^ nil ].
Factory>>aliasReader [ ^ nil ].
Factory>>globalReader [ ^ nil ].
Factory>>globalBlock [ ^ nil ].
Factory>>localAlias [ ^ nil ].
Factory>>shadow: AliasTarget [ ^ nil ].
Factory>>classArgument: target [ ^ nil ].
Factory>>importedReader [ ^ nil ].
Factory>>writeGlobal: value [ ^ nil ].
Factory>>globalWriter [ ^ nil ].
Factory>>nestedWriter [ ^ nil ].
Factory>>libraryWriter [ ^ nil ].
Factory>>protectedWriter [ ^ nil ].
Factory>>shadowWrite: LiveSetting [ ^ nil ].
Factory class>>writeGlobal: value [ ^ nil ].
Factory>>sideEffectWriter: next [ ^ nil ].
Factory>>counter [ ^ nil ].
BoundaryLib := Library name: "BoundaryLib".
BoundaryLib at: "LibrarySetting" put: 31.
Harding import: BoundaryLib.
AliasTarget := Object derive: #().
AliasTarget class>>answer [ ^ 81 ].
AlternateTarget := Object derive: #().
AlternateTarget class>>answer [ ^ 82 ].
LiveSetting := 11.
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
# Named allocations in class/instance bodies and escaped closures use live classes.
let liveSlotIdentity = interp.globals[]["SlotChild"].classVal
let namedClassObject = sendMessageInterpreted(interp, cls, "makeNamed", @[])
doAssert namedClassObject.instVal.class == liveSlotIdentity
doAssert not namedClassObject.instVal.isNimProxy
let namedInstanceObject = sendMessageInterpreted(interp, instance, "makeNamed", @[])
doAssert namedInstanceObject.instVal.class == liveSlotIdentity
discard sendMessageInterpreted(interp, namedInstanceObject, "extra:", @[toValue(0)])
discard sendMessageInterpreted(interp, namedInstanceObject, "interpretedSet:", @[toValue(4)])
let maker = sendMessageInterpreted(interp, instance, "maker", @[])
let fromMaker = invokeBlock(interp, maker.blockVal, @[])
doAssert fromMaker.instVal.class == liveSlotIdentity
let outerMaker = sendMessageInterpreted(interp, instance, "nestedMaker", @[])
let innerMaker = invokeBlock(interp, outerMaker.blockVal, @[])
doAssert invokeBlock(interp, innerMaker.blockVal, @[]).instVal.class == liveSlotIdentity
# Reads stay live inside escaped closures; lexical parameters still shadow globals.
doAssert sendMessageInterpreted(interp, instance, "classReference", @[]).classVal == liveSlotIdentity
let aliasOne = interp.globals[]["AliasTarget"]
let aliasTwo = interp.globals[]["AlternateTarget"]
doAssert sendMessageInterpreted(interp, instance, "aliasNew", @[]).instVal.class == aliasOne.classVal
doAssert sendMessageInterpreted(interp, instance, "localAlias", @[]).instVal.class == aliasOne.classVal
doAssert sendMessageInterpreted(interp, instance, "aliasAnswer", @[]).intVal == 81
doAssert sendMessageInterpreted(interp, instance, "classArgument:", @[aliasTwo]).intVal == 82
let aliasOuter = sendMessageInterpreted(interp, instance, "aliasReader", @[])
let aliasInner = invokeBlock(interp, aliasOuter.blockVal, @[])
doAssert invokeBlock(interp, aliasInner.blockVal, @[]).classVal == aliasOne.classVal
interp.globals[]["AliasTarget"] = aliasTwo
doAssert invokeBlock(interp, aliasInner.blockVal, @[]).classVal == aliasTwo.classVal
doAssert sendMessageInterpreted(interp, instance, "aliasAnswer", @[]).intVal == 82
doAssert sendMessageInterpreted(interp, instance, "aliasNew", @[]).instVal.class == aliasTwo.classVal
let shadow = sendMessageInterpreted(interp, instance, "shadow:", @[toValue(17)])
doAssert invokeBlock(interp, shadow.blockVal, @[]).intVal == 17
let globalBlock = sendMessageInterpreted(interp, instance, "globalBlock", @[])
doAssert invokeBlock(interp, globalBlock.blockVal, @[]).intVal == 11
interp.globals[]["LiveSetting"] = toValue(12)
doAssert invokeBlock(interp, globalBlock.blockVal, @[]).intVal == 12
doAssert sendMessageInterpreted(interp, instance, "globalReader", @[]).intVal == 12
interp.globals[]["LiveSetting"] = nilValue()
doAssert isNilValue(invokeBlock(interp, globalBlock.blockVal, @[]))
interp.globals[].del("LiveSetting")
doAssert isNilValue(sendMessageInterpreted(interp, instance, "globalReader", @[]))
let importedReader = sendMessageInterpreted(interp, instance, "importedReader", @[])
doAssert invokeBlock(interp, importedReader.blockVal, @[]).intVal == 31
let (_, updateLibraryError) = interp.evalStatements("BoundaryLib at: \\\"LibrarySetting\\\" put: 32")
doAssert updateLibraryError.len == 0, updateLibraryError
doAssert invokeBlock(interp, importedReader.blockVal, @[]).intVal == 32
doAssert sendMessageInterpreted(interp, instance, "writeGlobal:", @[toValue(40)]).intVal == 40
doAssert interp.globals[]["LiveSetting"].intVal == 40
let globalWriter = sendMessageInterpreted(interp, instance, "globalWriter", @[])
let writeResult = invokeBlock(interp, globalWriter.blockVal, @[nilValue()])
doAssert isNilValue(writeResult)
doAssert isNilValue(interp.globals[]["LiveSetting"])
let nestedWriter = sendMessageInterpreted(interp, instance, "nestedWriter", @[])
let innerWriter = invokeBlock(interp, nestedWriter.blockVal, @[])
doAssert invokeBlock(interp, innerWriter.blockVal, @[toValue(51)]).intVal == 51
doAssert interp.globals[]["CreatedSetting"].intVal == 51
let libraryWriter = sendMessageInterpreted(interp, instance, "libraryWriter", @[])
doAssert invokeBlock(interp, libraryWriter.blockVal, @[toValue(33)]).intVal == 33
doAssert invokeBlock(interp, importedReader.blockVal, @[]).intVal == 33
let shadowWriter = sendMessageInterpreted(interp, instance, "shadowWrite:", @[toValue(1)])
doAssert invokeBlock(interp, shadowWriter.blockVal, @[toValue(2)]).intVal == 2
doAssert isNilValue(interp.globals[]["LiveSetting"])
let savedObject = interp.globals[]["Object"]
var protectedFailed = false
try:
  discard sendMessageInterpreted(interp, instance, "protectedWriter", @[])
except CatchableError:
  protectedFailed = true
doAssert protectedFailed
doAssert interp.globals[]["Object"].classVal == savedObject.classVal
doAssert sendMessageInterpreted(interp, instance, "writeGlobal:", @[toValue(42)]).intVal == 42
doAssert sendMessageInterpreted(interp, cls, "writeGlobal:", @[toValue(43)]).intVal == 43
let counter = sendMessageInterpreted(interp, instance, "counter", @[])
let countedWriter = sendMessageInterpreted(interp, instance, "sideEffectWriter:", @[counter])
doAssert invokeBlock(interp, countedWriter.blockVal, @[]).intVal == 1
doAssert invokeBlock(interp, counter.blockVal, @[]).intVal == 2
# Overridden new may answer nil: host allocation must not retry the native path.
let (_, nilFactoryError) = interp.evalStatements("SlotChild class>>new [ ^ nil ]")
doAssert nilFactoryError.len == 0, nilFactoryError
doAssert isNilValue(sendMessageInterpreted(interp, cls, "makeNamed", @[]))
doAssert isNilValue(invokeBlock(interp, maker.blockVal, @[]))
let (_, failingNewError) = interp.evalStatements("SlotChild class>>new [ Error signal: \\\"allocation failure\\\" ]")
doAssert failingNewError.len == 0, failingNewError
var allocationFailed = false
try:
  discard invokeBlock(interp, maker.blockVal, @[])
except ValueError:
  allocationFailed = true
doAssert allocationFailed
let (_, restoreNewError) = interp.evalStatements("SlotChild class>>new [ ^ super new ]")
doAssert restoreNewError.len == 0, restoreNewError
doAssert invokeBlock(interp, maker.blockVal, @[]).instVal.class == liveSlotIdentity
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
