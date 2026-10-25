"""Frozen build gate integration: fixtures stay under build/, never repository sources."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_frozen", ROOT / "scripts/check_frozen.py")
assert spec is not None and spec.loader is not None
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class FrozenBuildTest(unittest.TestCase):
    def test_embedded_library_changes_invalidate_toolchain_digest(self):
        base = ROOT / "build/frozen-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            root = Path(temporary)
            library = root / "lib/Bootstrap.hrd"
            library.parent.mkdir()
            library.write_text("# original")
            before = gate.toolchain_digest(root)
            library.write_text("# changed")
            self.assertNotEqual(gate.toolchain_digest(root), before)
            library.write_text("# original")
            self.assertEqual(gate.toolchain_digest(root), before)

    def test_failures_do_not_leave_a_success_receipt(self):
        base = ROOT / "build/frozen-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            receipt = Path(temporary) / "receipt.json"
            receipt.write_text("stale success")
            with patch.object(gate.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "test")):
                with self.assertRaises(subprocess.CalledProcessError):
                    gate.check(ROOT / "config/granite-frozen.json", receipt)
            self.assertFalse(receipt.exists())

    def test_failed_conformance_invalidates_existing_receipt(self):
        base = ROOT / "build/frozen-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            receipt = Path(temporary) / "receipt.json"
            receipt.write_text("old success")
            with patch.object(gate.subprocess, "run", side_effect=[None, subprocess.CalledProcessError(1, "parity")]):
                with self.assertRaises(subprocess.CalledProcessError):
                    gate.check(ROOT / "config/granite-frozen.json", receipt)
            self.assertFalse(receipt.exists())

    @unittest.skipUnless(os.environ.get("FROZEN_RECEIPT"), "Run check_frozen.py and set FROZEN_RECEIPT for executed builds")
    def test_checked_build_preserves_script_and_compile_scopes(self):
        base = ROOT / "build/frozen-tests"
        base.mkdir(parents=True, exist_ok=True)
        receipt = Path(os.environ["FROZEN_RECEIPT"]).resolve()
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            for name, body in {
                "script": "| sc |\nLocal := Object derive: #(). Local class>>answer [ ^ 7 ].\nsc := SortedCollection new. sc add: 4. sc add: 1. sc asArray println. Local answer println.",
                "scoped": "Harding compile: [Local := Object derive: #(). Local class>>answer [ ^ 7 ]].\nHarding main: [ | sc | sc := SortedCollection new. sc add: 4. sc add: 1. sc asArray println. Local answer println. ]",
            }.items():
                with self.subTest(scope=name):
                    source = work / (name + ".hrd")
                    source.write_text(body)
                    binary = work / name
                    command = [str(ROOT / "granite"), "build", str(source),
                               "--dir:" + str(work), "-o:" + str(binary),
                               "--freeze-manifest:" + str(ROOT / "config/granite-frozen.json"),
                               "--freeze-receipt:" + str(receipt), "--seal-frozen"]
                    compiled = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
                    self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                    native = subprocess.run([str(binary)], cwd=work, capture_output=True, text=True, timeout=30)
                    self.assertEqual(native.returncode, 0, native.stderr)
                    self.assertEqual(native.stdout, "#(1 4)\n7\n")
                    orc_binary = work / (name + "_orc")
                    orc_build = subprocess.run(["nim", "c", "--mm:orc", "-o:" + str(orc_binary),
                                                str(work / (name + ".nim"))],
                                               cwd=ROOT, capture_output=True, text=True, timeout=180)
                    self.assertEqual(orc_build.returncode, 0, orc_build.stdout + orc_build.stderr)
                    orc = subprocess.run([str(orc_binary)], cwd=work, capture_output=True, text=True, timeout=30)
                    self.assertEqual(orc.returncode, 0, orc.stderr)
                    self.assertEqual(orc.stdout, native.stdout)

    @unittest.skipUnless(os.environ.get("FROZEN_RECEIPT"), "Requires executed conformance receipt")
    def test_explicit_embedded_host_has_no_source_tree_or_application_replay(self):
        base = ROOT / "build/frozen-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            source = work / "module.hrd"
            source.write_text('Transcript showCr: "APPLICATION MUST NOT RUN".')
            module = work / "frozenmodule.nim"
            generated = subprocess.run([str(ROOT / "granite"), "compile", str(source),
                "--dir:" + str(work), "-o:" + str(work / "frozenmodule"),
                "--freeze-manifest:" + str(ROOT / "config/granite-frozen.json"),
                "--freeze-receipt:" + str(Path(os.environ["FROZEN_RECEIPT"]).resolve())],
                cwd=ROOT, capture_output=True, text=True, timeout=60)
            self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
            self.assertIn("proc newFrozenHost*", module.read_text())
            host = work / "host.nim"
            imports = "\n".join('import "' + (ROOT / path).as_posix() + '"' for path in
                ["src/harding/core/types", "src/harding/core/scheduler", "src/harding/interpreter/vm",
                 "src/harding/runtime/runtime"])
            host.write_text('import std/tables\n' + imports + '\nimport ./frozenmodule\n' + '''
let context = frozenmodule.newFrozenHost()
var interp = frozenHostInterpreter(context)
doAssert hybridInterpreter == nil
doAssert interp.packageOnlyLoads
doAssert interp.schedulerContextPtr != nil
let cls = interp.globals[]["SortedCollection"].classVal
doAssert cls.methods["add:"].nativeImpl != nil
let (values, error) = interp.evalStatements("""
Collection := SortedCollection new.
Collection add: 3. Collection add: 1. Collection add: 2.
Collection asArray
""")
doAssert error.len == 0, error
let array = values[^1].instVal
doAssert array.elements[0].intVal == 1 and array.elements[2].intVal == 3
let (_, redefineError) = interp.evalStatements("SortedCollection>>size [ ^ 99 ]")
doAssert redefineError.len == 0, redefineError
let changed = sendMessageInterpreted(interp, interp.globals[]["Collection"], "size", @[])
doAssert changed.intVal == 99
unbindCompiledMethodsFrom(interp)
echo "embedded host passed"
''')
            source.unlink()
            isolated = work / "isolated"
            isolated.mkdir()
            # A colliding disk bootstrap must not replace embedded source.
            (isolated / "lib/core").mkdir(parents=True)
            (isolated / "lib/core/Bootstrap.hrd").write_text('Error signal: "disk bootstrap used".')
            for mm in ("arc", "orc"):
                with self.subTest(mm=mm):
                    binary = work / ("host_" + mm)
                    compiled = subprocess.run(["nim", "c", "--mm:" + mm, "-o:" + str(binary), str(host)],
                                              cwd=ROOT, capture_output=True, text=True, timeout=180)
                    self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                    native = subprocess.run([str(binary)], cwd=isolated, capture_output=True, text=True, timeout=60)
                    self.assertEqual(native.returncode, 0, native.stdout + native.stderr)
                    self.assertEqual(native.stdout, "embedded host passed\n")
                    self.assertEqual(native.stderr, "")

    @unittest.skipUnless(os.environ.get("FROZEN_RECEIPT"), "Requires executed conformance receipt")
    def test_sealed_application_overrides_are_refused_before_reflection(self):
        base = ROOT / "build/frozen-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            for body in ["SortedCollection>>size [ ^ 99 ].", "SortedCollection := Object derive: #().",
                         "Harding compile: [SortedCollection class>>new [ ^ nil ]]."]:
                with self.subTest(source=body):
                    source = work / "override.hrd"
                    source.write_text(body)
                    command = [str(ROOT / "granite"), "compile", str(source), "--dir:" + str(work),
                               "--freeze-manifest:" + str(ROOT / "config/granite-frozen.json"),
                               "--freeze-receipt:" + str(Path(os.environ["FROZEN_RECEIPT"]).resolve()),
                               "--seal-frozen"]
                    refused = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
                    self.assertNotEqual(refused.returncode, 0)
                    self.assertIn("sealed application", refused.stdout)
                    self.assertEqual(list(work.glob("*.nim")), [])

    def test_compiler_requires_current_engine_and_case_evidence(self):
        base = ROOT / "build/frozen-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            source = work / "app.hrd"
            source.write_text("42 println.")
            manifest = ROOT / "config/granite-frozen.json"
            receipt = work / "receipt.json"
            command = [str(ROOT / "granite"), "compile", str(source),
                       "--dir:" + str(work), "--freeze-manifest:" + str(manifest)]
            missing = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("requires --freeze-receipt", missing.stdout)
            no_manifest = subprocess.run([str(ROOT / "granite"), "compile", str(source), "--seal-frozen"],
                                         cwd=ROOT, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(no_manifest.returncode, 0)
            self.assertIn("--seal-frozen requires --freeze-manifest", no_manifest.stdout)
            mixed = subprocess.run(command + ["--mixed"], cwd=ROOT, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(mixed.returncode, 0)
            self.assertIn("Frozen mixed bootstrap is not implemented", mixed.stdout)
            receipt.write_text(json.dumps({"manifestSha1": "stale"}))
            stale = subprocess.run(command + ["--freeze-receipt:" + str(receipt)],
                                   cwd=ROOT, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(stale.returncode, 0)
            self.assertIn("Stale frozen conformance receipt", stale.stdout)
            evidence = {"manifestSha1": gate.digest(manifest),
                        "graniteSha1": gate.digest(ROOT / "granite"),
                        "hardingSha1": gate.digest(ROOT / "harding"),
                        "runnerSha1": gate.digest(ROOT / "scripts/test_granite_parity.py"),
                        "toolchainSha1": gate.toolchain_digest(ROOT),
                        "passedCases": []}
            receipt.write_text(json.dumps(evidence))
            absent = subprocess.run(command + ["--freeze-receipt:" + str(receipt)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(absent.returncode, 0)
            self.assertIn("Missing executed frozen case", absent.stdout)


if __name__ == "__main__":
    unittest.main()
