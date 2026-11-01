"""Executed guarded unary receiver specialization, with warm-cache mutations."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''
Receiver := Object derivePublic: #(payload).
Receiver>>answer [ ^ 11 ].
Receiver>>nilAnswer [ ^ nil ].
Receiver>>throws [ Error signal: "direct failure" ].
Caller := Object derive: #().
Caller>>read: target [ ^ target payload ].
Caller>>ask: target [ ^ target answer ].
Caller>>askNil: target [ ^ target nilAnswer ].
Caller>>catch: target [ ^[target throws] on: Error do: [:error | 73] ].
Caller>>once: action [ ^ action value answer ].
Caller>>effectful: action [ ^ (action value) answer ].
Caller>>loopRead: target [ | total i | total := 0. i := 0.
  [i < 3] whileTrue: [total := total + target payload. i := i + 1]. ^total ].
Child := Receiver derivePublic: #(extra).
Child>>setup [ extra := 99. ^ self ].
'''


def execute(command):
    p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240)
    if p.returncode:
        raise AssertionError(str(command) + '\n' + p.stdout + p.stderr)
    return p


class DirectSends(unittest.TestCase):
    def test_generated_guard_fallback_and_live_mutation(self):
        base = ROOT / 'build/direct-send-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'directsend.hrd'
            source.write_text(SOURCE)
            execute([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work)])
            generated = (work / 'directsend.nim').read_text()
            self.assertIn('canDirectCompiledSend(receiver', generated)
            self.assertIn('return Class_5265636569766572_nt_answer(receiver, @[])', generated)
            self.assertIn('sendMessageBound(owner, receiver, "answer", @[])', generated)
            self.assertIn('_direct_payload_read(receiver)', generated)
            imports = '\n'.join('import "' + str(ROOT / p) + '"' for p in [
                'src/harding/core/types', 'src/harding/core/scheduler',
                'src/harding/interpreter/vm', 'src/harding/runtime/runtime'])
            host = work / 'host.nim'
            host.write_text('import std/tables\n' + imports + '\nimport ./directsend\n' + '''
registerCompiledMethods()
registerSuperclassHierarchy()
let caller = newClass_43616C6C6572().toValue()
let receiver = newClass_5265636569766572().toValue()
discard setSlotValue(receiver, "payload", toValue(7))
doAssert sendMessage(nil, caller, "catch:", @[receiver]).intVal == 73
for iteration in 0..<3:
  doAssert sendMessage(nil, caller, "read:", @[receiver]).intVal == 7
  doAssert sendMessage(nil, caller, "ask:", @[receiver]).intVal == 11
  doAssert sendMessage(nil, caller, "loopRead:", @[receiver]).intVal == 21
  doAssert isNilValue(sendMessage(nil, caller, "askNil:", @[receiver]))
# Direct accessor answers preserve shared collection identity.
let collection = compiledArray(@[toValue(1)])
discard setSlotValue(receiver, "payload", collection)
let retained = sendMessage(nil, caller, "read:", @[receiver])
discard sendMessage(nil, retained, "add:", @[toValue(2)])
doAssert collection.instVal.elements.len == 2
discard setSlotValue(receiver, "payload", toValue(7))
proc replacement(self: NodeValue, args: seq[NodeValue]): NodeValue = toValue(42)
proc changedGet(storage: pointer): NodeValue {.nimcall.} = toValue(88)
let oldGet = slotGetters["Receiver::payload"]
let oldSet = slotSetters["Receiver::payload"]
registerSlotAccessor("Receiver", "payload", changedGet, oldSet)
doAssert sendMessage(nil, caller, "read:", @[receiver]).intVal == 88
doAssert sendMessage(nil, caller, "loopRead:", @[receiver]).intVal == 264
registerSlotAccessor("Receiver", "payload", oldGet, oldSet)
registerCompiledMethod("Receiver", "answer", replacement)
doAssert sendMessage(nil, caller, "ask:", @[receiver]).intVal == 42
registerCompiledMethod("Receiver", "answer", Class_5265636569766572_nt_answer)
doAssert sendMessage(nil, caller, "ask:", @[receiver]).intVal == 11
registerCompiledMethod("Receiver", "payload", replacement)
doAssert sendMessage(nil, caller, "read:", @[receiver]).intVal == 42
registerCompiledMethods()
# An exact-class guard must refuse subclass storage and let override lookup run.
let child = newClass_4368696C64().toValue()
discard setSlotValue(child, "payload", toValue(8))
discard sendMessage(nil, child, "setup", @[])
registerCompiledMethod("Child", "answer", replacement)
doAssert sendMessage(nil, caller, "ask:", @[child]).intVal == 42
doAssert sendMessage(nil, caller, "read:", @[child]).intVal == 8
doAssert getSlotValue(child, "extra").intVal == 99
# Foreign classes are not evidence failures: use their ordinary dynamic method.
let foreignClass = newClass(name = "ForeignDirectSend")
let foreign = newInstance(foreignClass)
foreign.isNimProxy = true
registerCompiledMethod("ForeignDirectSend", "answer", replacement)
doAssert sendMessage(nil, caller, "ask:", @[NodeValue(kind: vkInstance, instVal: foreign)]).intVal == 42
# A duplicate class name is not the same identity. The accessor route must not
# cast this VM-owned storage as the generated native layout.
let duplicate = newInstance(newClass(slotNames = @["payload"], name = "Receiver"))
duplicate.isNimProxy = true
duplicate.slots[0] = toValue(23)
var identityGuard: CompiledDirectGuard
doAssert not canDirectCompiledSend(NodeValue(kind: vkInstance, instVal: duplicate),
  receiver.instVal.class, "answer", Class_5265636569766572_nt_answer, identityGuard)
# VM-owned objects, interpreted overrides and callbacks must keep the host path.
let context = newSchedulerContext()
var interp = context.mainProcess.getInterpreter()
interp.hardingHome = "."
loadStdlib(interp)
let (_, setupError) = interp.evalStatements("""
Receiver := Object derivePublic: #(payload).
Receiver>>answer [ ^11 ]. Receiver>>nilAnswer [ ^nil ].
Receiver>>throws [ Error signal: "direct failure" ].
Caller := Object derive: #().
Caller>>read: target [ ^nil ]. Caller>>ask: target [ ^nil ].
Caller>>askNil: target [ ^nil ]. Caller>>once: action [ ^nil ].
Caller>>effectful: action [ ^nil ].
Caller>>loopRead: target [ ^nil ].
VmCaller := Caller new. VmReceiver := Receiver new.
VmReceiver payload: 17. Calls := 0.
""")
doAssert setupError.len == 0, setupError
bindCompiledMethodsTo(interp)
for (expression, expected) in [("VmCaller read: VmReceiver", 17),
                               ("VmCaller ask: VmReceiver", 11),
                               ("VmCaller loopRead: VmReceiver", 51),
                               ("VmCaller once: [Calls := Calls + 1. VmReceiver]", 11)]:
  let (answer, error) = interp.doit(expression)
  doAssert error.len == 0, error
  doAssert answer.intVal == expected
  doAssert interp.globals[]["Calls"].intVal <= 1
let (_, callbackSetup) = interp.evalStatements("Calls := 0")
doAssert callbackSetup.len == 0
let (callbackAnswer, callbackError) = interp.doit("VmCaller effectful: [Calls := Calls + 1. VmReceiver]")
doAssert callbackError.len == 0, callbackError
doAssert callbackAnswer.intVal == 11
doAssert interp.globals[]["Calls"].intVal == 1
let (_, replaceError) = interp.evalStatements("Receiver>>answer [ ^nil ]")
doAssert replaceError.len == 0
let (nilAnswer, nilError) = interp.doit("VmCaller ask: VmReceiver")
doAssert nilError.len == 0, nilError
doAssert isNilValue(nilAnswer)
# A pure native caller during a host lifetime must also respect live ownership.
let vmReceiver = interp.globals[]["VmReceiver"]
doAssert isNilValue(sendMessage(nil, caller, "ask:", @[vmReceiver]))
unbindCompiledMethodsFrom(interp)
doAssert sendMessage(nil, caller, "ask:", @[receiver]).intVal == 11
echo "direct sends passed"
''')
            for mm in ('arc', 'orc'):
                with self.subTest(mm=mm):
                    binary = work / ('host-' + mm)
                    execute(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('cache-' + mm)),
                             '-o:' + str(binary), str(host)])
                    ran = execute([str(binary)])
                    self.assertEqual(ran.stdout, 'direct sends passed\n')
                    self.assertEqual(ran.stderr, '')


if __name__ == '__main__':
    unittest.main()
