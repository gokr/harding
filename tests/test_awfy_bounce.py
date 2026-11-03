"""AWFY Bounce provenance and executable interpreter/Granite parity checks."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PORT = ROOT / "benchmark/awfy/bounce"
BUILD = ROOT / "build/awfy-bounce"
COMMIT = "74306fec151070fd07157cefeacf19e7e0bcdc89"


class AwfyBounceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)

    def command(self, args, log):
        run = subprocess.run([str(arg) for arg in args], cwd=ROOT,
                             capture_output=True, text=True, timeout=240)
        (BUILD / log).write_text(run.stdout + run.stderr)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        return run

    def output(self, args, expected, log):
        run = self.command(args, log)
        self.assertEqual(run.stderr, "")
        self.assertEqual(run.stdout, expected)

    def test_pinned_sources_and_python(self):
        manifest = json.loads((PORT / "upstream/provenance.json").read_text())
        self.assertEqual(manifest["commit"], COMMIT)
        for entry in manifest["files"]:
            data = (PORT / "upstream" / entry["path"]).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"])
        self.output([sys.executable, "-B", PORT / "compare.py"], "1331\n", "python.log")

    def test_interpreter_arc_and_orc(self):
        checks = BUILD / "checks.hrd"
        checks.write_text((PORT / "bounce.hrd").read_text() + '''
(Bounce new benchmark) println.
(Bounce new verifyResult: 1331) println.
(Bounce new verifyResult: 1330) println.
(SomRandom new next) println.
''')
        for mm in ("arc", "orc"):
            with self.subTest(mm=mm):
                interpreter = BUILD / ("harding-" + mm)
                self.command(["nim", "c", "--mm:" + mm, "-d:release",
                              "--nimcache:" + str(BUILD / ("interpreter-cache-" + mm)),
                              "-p:" + str(ROOT / "external"), "-o:" + str(interpreter),
                              ROOT / "src/harding/repl/harding.nim"],
                             "interpreter-" + mm + "-build.log")
                self.output([interpreter, PORT / "bounce.hrd"], "1331\n", "interpreter-" + mm + ".log")
                self.output([interpreter, checks], "1331\n1331\ntrue\nfalse\n22896\n",
                            "checks-" + mm + ".log")

    def test_granite_arc_and_orc(self):
        for mm in ("arc", "orc"):
            with self.subTest(mm=mm):
                directory = BUILD / ("native-" + mm)
                directory.mkdir(exist_ok=True)
                self.command([ROOT / "granite", "compile", PORT / "bounce.hrd",
                              "--dir:" + str(directory), "-o:bounce"],
                             "granite-" + mm + ".log")
                executable = directory / "bounce"
                self.command(["nim", "c", "--mm:" + mm, "-d:release",
                              "--nimcache:" + str(BUILD / ("native-cache-" + mm)),
                              "-o:" + str(executable), directory / "bounce.nim"],
                             "native-" + mm + "-build.log")
                self.output([executable], "1331\n", "native-" + mm + ".log")


if __name__ == "__main__":
    unittest.main()
