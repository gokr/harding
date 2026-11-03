"""Native int call chains retain dynamic dispatch guards at the region boundary."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''Calc := Object derive: #().
Calc>>outer: n [ ^(self inner: n) * 3 ].
Calc>>inner: n [ ^n + 1 ].
Caller := Object derive: #().
Caller>>apply: receiver with: n [ ^receiver outer: n ].
Caller>>effectful: receiver with: action [ ^receiver outer: action value ].
Child := Calc derive: #().
Unplanned := Object derive: #().
Unplanned>>fallthrough: n [ n + 1 ].
Unplanned>>callback: action [ ^action value ].
Unplanned>>divide: n [ ^n / 2 ].
Unplanned>>recursive: n [ ^self recursive: n ].
'''


class NativeCallRegions(unittest.TestCase):
    def checked(self, command):
        p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=240)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return p

    def test_transitive_native_calls_and_replacement(self):
        base = ROOT / 'build/native-call-region-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'region.hrd'
            source.write_text(SOURCE)
            self.checked([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work)])
            code = (work / 'region.nim').read_text()
            native = 'integerCall_Class_43616C63_hardingUser696E6E65723A_native(n) * 3'
            self.assertIn(native, code)
            self.assertIn('canDirectCompiledSend(receiver', code)
            # No native region can be justified for these bodies.
            self.assertNotIn('integerCall_Class_556E706C616E6E6564', code)
            # Transitive native calls have no seq or boxed argument/return ABI.
            start = code.index('proc integerCall_Class_43616C63_hardingUser6F757465723A_native')
            end = code.index('\nvar ', start)
            self.assertNotIn('NodeValue', code[start:end])
            self.assertNotIn('@[', code[start:end])
            imports = '\n'.join('import "' + str(ROOT / path) + '"' for path in
                                ['src/harding/core/types', 'src/harding/runtime/runtime',
                                 'src/harding/runtime/compiled_support',
                                 'src/harding/core/scheduler', 'src/harding/interpreter/vm'])
            host = work / 'host.nim'
            host.write_text('import std/tables\n' + imports + '\nimport ./region\n' + '''
registerCompiledMethods()
registerSuperclassHierarchy()
let calc = newClass_43616C63().toValue()
let caller = newClass_43616C6C6572().toValue()
proc apply(receiver, argument: NodeValue): NodeValue =
  sendMessage(nil, caller, "apply:with:", @[receiver, argument])
for i in 0..<3:
  doAssert apply(calc, toValue(7)).intVal == 24
  doAssert apply(calc, toValue(2.5)).floatVal == 10.5
proc changed(self: NodeValue, args: seq[NodeValue]): NodeValue = toValue(10)
# Invalidating a transitive callee must invalidate the outer region too.
registerCompiledMethod("Calc", "inner:", changed)
doAssert apply(calc, toValue(7)).intVal == 30
registerCompiledMethod("Calc", "inner:", Class_43616C63_nt_inner_k)
doAssert apply(calc, toValue(7)).intVal == 24
var effects = 0
proc changeDuringOperand(): NodeValue {.cdecl.} =
  inc effects
  registerCompiledMethod("Calc", "inner:", changed)
  toValue(7)
let action = createBlock0(changeDuringOperand, 0)
doAssert sendMessage(nil, caller, "effectful:with:", @[calc, action]).intVal == 30
doAssert effects == 1
registerCompiledMethod("Calc", "inner:", Class_43616C63_nt_inner_k)
doAssert apply(calc, toValue(7)).intVal == 24
let child = newClass_4368696C64().toValue()
registerCompiledMethod("Child", "inner:", changed)
doAssert apply(child, toValue(7)).intVal == 30
registerCompiledMethod("Calc", "outer:", changed)
doAssert apply(calc, toValue(7)).intVal == 10
proc nilAnswer(self: NodeValue, args: seq[NodeValue]): NodeValue = nilValue()
registerCompiledMethod("Calc", "outer:", nilAnswer)
doAssert isNilValue(apply(calc, toValue(7)))
# A bound host preserves interpreted replacement even after native cache warmth.
let context = newSchedulerContext()
var interp = context.mainProcess.getInterpreter()
interp.hardingHome = "."
loadStdlib(interp)
let (_, setupError) = interp.evalStatements("""
Calc := Object derive: #().
Calc>>outer: n [ ^(self inner: n) * 3 ].
Calc>>inner: n [ ^n + 1 ].
Caller := Object derive: #().
Caller>>apply: receiver with: n [ ^nil ].
Caller>>effectful: receiver with: action [ ^nil ].
VmCalc := Calc new. VmCaller := Caller new.
""")
doAssert setupError.len == 0, setupError
registerCompiledMethods()
bindCompiledMethodsTo(interp)
let (before, beforeError) = interp.doit("VmCaller apply: VmCalc with: 7")
doAssert beforeError.len == 0, beforeError
doAssert before.intVal == 24
let (_, replaceError) = interp.evalStatements("Calc>>inner: n [ ^10 ]")
doAssert replaceError.len == 0, replaceError
let (after, afterError) = interp.doit("VmCaller apply: VmCalc with: 7")
doAssert afterError.len == 0, afterError
doAssert after.intVal == 30
unbindCompiledMethodsFrom(interp)
doAssert apply(calc, toValue(7)).intVal == 24
''')
            for mm in ('arc', 'orc'):
                with self.subTest(mm=mm):
                    binary = work / ('host_' + mm)
                    self.checked(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('cache_' + mm)),
                                  '-o:' + str(binary), str(host)])
                    self.checked([str(binary)])


if __name__ == '__main__':
    unittest.main()
