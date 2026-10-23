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
