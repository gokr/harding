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
                               "--freeze-receipt:" + str(receipt)]
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
