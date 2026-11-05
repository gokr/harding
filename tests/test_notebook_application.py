"""Harding Notebook: one .hrd GTK application, interpreted and compiled."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "demos/notebook/notebook.hrd"

EXPECTED_MODEL = """3
2
1
1
Apple,Zebra,
#(Animals Food General)
2
n-2
3
3
Zebra
true
1
notebook model self test passed
"""

EXPECTED_GUI = """pinned ok
true
notebook gui self test passed
"""


def gui_available():
    return bool((os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
                and shutil.which("pkg-config") and shutil.which("nim")
                and subprocess.run(["pkg-config", "--exists", "gtk4"]).returncode == 0)


class NotebookModelParityTest(unittest.TestCase):
    """The model and persistence run without a display, in both engines."""

    def run_checked(self, command, **kwargs):
        completed = subprocess.run(command, capture_output=True, text=True, timeout=240, **kwargs)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return completed

    def test_model_and_persistence_are_identical_in_both_engines(self):
        base = ROOT / "build/notebook-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            interpreted = self.run_checked([str(ROOT / "harding"), str(SOURCE), "--", "--self-test"],
                                           cwd=ROOT)
            self.assertEqual(interpreted.stdout, EXPECTED_MODEL)
            native = work / "notebook_model"
            self.run_checked([str(ROOT / "granite"), "build", str(SOURCE),
                              "--dir:" + str(work), "-o:" + str(native)], cwd=ROOT)
            compiled = self.run_checked([str(native), "--self-test"], cwd=ROOT)
            self.assertEqual(compiled.stdout, EXPECTED_MODEL)


@unittest.skipUnless(gui_available(), "Requires GTK4 and a graphical session")
class NotebookGuiTest(unittest.TestCase):
    def test_the_same_source_drives_real_widgets_in_both_engines(self):
        base = ROOT / "build/notebook-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            interpreter = work / "harding_gtk"
            self.run_checked(["nim", "c", "-p:src", "--nimcache:" + str(work / "nimcache"),
                              "-o:" + str(interpreter),
                              str(ROOT / "src/harding/repl/harding_gtk.nim")], cwd=ROOT)
            data = work / "notes.json"
            interpreted = self.run_checked(
                [str(interpreter), str(SOURCE), "--", "--self-test", "--gui-test",
                 "--data", str(data)], cwd=ROOT)
            self.assertEqual(interpreted.stdout, EXPECTED_GUI)
            self.assertNotIn("Gtk-CRITICAL", interpreted.stderr)
            self.assertNotIn("GTK callback error", interpreted.stderr)

            native = work / "notebook"
            self.run_checked([str(ROOT / "granite"), "build", "--gtk", str(SOURCE),
                              "--dir:" + str(work), "-o:" + str(native)], cwd=ROOT)
            compiled = self.run_checked([str(native), "--self-test", "--gui-test",
                                         "--data", str(data)], cwd=ROOT)
            self.assertEqual(compiled.stdout, EXPECTED_GUI)
            self.assertNotIn("Gtk-CRITICAL", compiled.stderr)
            self.assertNotIn("GTK callback error", compiled.stderr)
            self.assertEqual(compiled.stdout, interpreted.stdout)

    def run_checked(self, command, **kwargs):
        completed = subprocess.run(command, capture_output=True, text=True, timeout=300, **kwargs)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return completed


if __name__ == "__main__":
    unittest.main()
