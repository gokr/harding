"""A slot-backed region must not bypass declarative slot semantics.

The region reads and writes declared Integer fields directly, so it owes the
same guarantees as an ordinary accessor call: contract checks on other paths,
and falling back to normal dispatch when the accessor table is redirected.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = '''Counter := Object derivePublic: #{#count -> Integer, #step -> Integer}.
Counter>>setup [ count := 0. step := 3. ^self ].
Counter>>bump: limit [ | i | i := 0.
[i < limit] whileTrue: [count := count + step. i := i + 1]. ^count ].
Dynamic := Object derive: #(total).
Dynamic>>sum: limit [ | i | i := 0.
[i < limit] whileTrue: [total := total + i. i := i + 1]. ^total ].
FloatSlot := Object derivePublic: #{#ratio -> Float}.
FloatSlot>>spin: limit [ | i | i := 0.
[i < limit] whileTrue: [ratio := i. i := i + 1]. ^ratio ].
'''


class SlotBackedRegions(unittest.TestCase):
    def checked(self, command):
        p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=240)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return p

    def test_slot_region_semantics(self):
        base = ROOT / 'build/slot-region-tests'
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            work = Path(directory)
            source = work / 'slots.hrd'
            source.write_text(SOURCE)
            self.checked([str(ROOT / 'granite'), 'compile', str(source), '--dir:' + str(work)])
            code = (work / 'slots.nim').read_text()

            bump = 'integerCall_Class_436F756E746572_hardingUser62756D703A_native'
            self.assertIn('proc ' + bump + '*(self: Class_436F756E746572, limit: int): int', code)
            start = code.index('proc ' + bump + '*(self')
            end = code.index('\nvar ', start)
            body = code[start:end]
            # Direct field access only: no accessor calls, no NodeValue traffic.
            self.assertIn('self[].', body)
            self.assertNotIn('NodeValue', body)
            self.assertNotIn('_direct_', body)
            # Storage redirection is still checked, once, at the entry boundary.
            self.assertIn('nativeSlotAccessorGuard_Class_436F756E746572_'
                          'hardingUser636F756E74(receiver)', code)
            # A dynamic (undeclared) slot and a non-Integer slot stay boxed.
            self.assertNotIn('integerCall_Class_44796E616D6963', code)
            self.assertNotIn('integerCall_Class_466C6F6174536C6F74', code)

            imports = '\n'.join('import "' + str(ROOT / p) + '"' for p in
                                ['src/harding/core/types', 'src/harding/runtime/runtime',
                                 'src/harding/runtime/compiled_support'])
            host = work / 'host.nim'
            host.write_text('import std/tables\n' + imports + '\nimport ./slots\n' + '''
registerCompiledMethods()
registerSuperclassHierarchy()
let counter = newClass_436F756E746572().toValue()
discard sendMessage(nil, counter, "setup", @[])
doAssert sendMessage(nil, counter, "bump:", @[toValue(4)]).intVal == 12
doAssert sendMessage(nil, counter, "bump:", @[toValue(100)]).intVal == 312

# Writes outside the region still enforce the declared contract.
var rejected = false
try:
  discard setSlotValue(counter, "count", toValue("wrong"))
except CatchableError:
  rejected = true
doAssert rejected
doAssert getSlotValue(counter, "count").intVal == 312
doAssert getSlotValue(counter, "count").kind == vkInt

# Redirecting an accessor must disable the region, not be bypassed by it.
var routed = 0
proc routedCount(nimValue: pointer): NodeValue {.nimcall.} =
  inc routed
  NodeValue(kind: vkInt, intVal: cast[Class_436F756E746572](nimValue)[].hardingUser636F756E74)
proc routedStore(nimValue: pointer, value: NodeValue): NodeValue {.nimcall.} =
  cast[Class_436F756E746572](nimValue)[].hardingUser636F756E74 = value.intVal
  value
registerSlotAccessor("Counter", "count", routedCount, routedStore)
let afterReplace = sendMessage(nil, counter, "bump:", @[toValue(2)])
echo "afterReplace=", afterReplace.intVal, " routed=", routed
# Replaced accessor: the region must fall back, so the routing getter runs.
doAssert routed > 0
''')
            for mm in ('arc', 'orc'):
                with self.subTest(mm=mm):
                    binary = work / ('host_' + mm)
                    self.checked(['nim', 'c', '--mm:' + mm, '--nimcache:' + str(work / ('cache_' + mm)),
                                  '-o:' + str(binary), str(host)])
                    self.checked([str(binary)])


if __name__ == '__main__':
    unittest.main()
