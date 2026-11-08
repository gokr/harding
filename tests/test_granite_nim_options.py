#!/usr/bin/env python3
"""Integration coverage for Granite's Nim argument forwarding."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NimOptionsTest(unittest.TestCase):
    def test_missing_option_argument_is_rejected(self):
        result = subprocess.run([str(ROOT / "granite"), "build", "--nim-option"],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--nim-option requires an argument", result.stdout)

    def test_repeatable_arguments_and_shell_quoting(self):
        build = ROOT / "build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as directory:
            work = Path(directory)
            source = work / "example.hrd"
            source.write_text('Stdout writeline: "ok".\n')
            marker = work / "injected"
            cmd = [str(ROOT / "granite"), "build", str(source),
                   "--home:" + str(ROOT), "--dir:" + str(work),
                   "-o:" + str(work / "program"), "--nim-option:--mm:orc",
                   "--nim-option:-d:forwarded;touch " + str(marker)]
            result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(marker.exists(), "option was executed by the shell")
            output = subprocess.run([str(work / "program")], capture_output=True,
                                    text=True, check=True)
            self.assertEqual(output.stdout.strip(), "ok")


if __name__ == "__main__":
    unittest.main()
