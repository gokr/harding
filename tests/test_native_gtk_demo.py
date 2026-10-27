"""Native GTK demo acceptance; requires a GTK display and built ./granite."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def available():
    return bool((os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
                and shutil.which("pkg-config") and shutil.which("nim")
                and (ROOT / "granite").is_file()
                and subprocess.run(["pkg-config", "--exists", "gtk4"]).returncode == 0)


@unittest.skipUnless(available(), "Requires GTK4, Nim, Granite and an accessible display")
class NativeGtkDemoTest(unittest.TestCase):
    def test_compiled_actions_in_binary_only_package(self):
        base = ROOT / "build/native-gtk-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            for mm in ("arc", "orc"):
                with self.subTest(mm=mm):
                    build_dir = work / mm
                    log = work / (mm + "-build.log")
                    build_command = ["python3", str(ROOT / "scripts/build_native_gtk_demo.py"),
                                     "--dir", str(build_dir), "--mm", mm]
                    if mm == "orc":
                        build_command.append("--release")
                    with log.open("w") as output:
                        built = subprocess.run(build_command,
                                               cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=180)
                    self.assertEqual(built.returncode, 0, log.read_text())
                    generated = (build_dir / "counter_model.nim").read_text()
                    self.assertNotIn("initHybridRuntime(", generated)
                    self.assertNotIn("loadStdlib(", generated)
                    self.assertNotIn("evalStatements(", generated)
                    package = work / (mm + "-package")
                    package.mkdir()
                    binary = package / "native-gtk-counter"
                    shutil.copy2(build_dir / binary.name, binary)
                    shutil.rmtree(build_dir)
                    # No application sources, generated Nim, Harding executable or
                    # bootstrap paths are available to the packaged application.
                    environment = dict(os.environ, PATH="", HARDING_HOME=str(package / "absent"))
                    for repetition in range(3):
                        executed = subprocess.run([str(binary), "--self-test"], cwd=package,
                                                  env=environment, capture_output=True, text=True, timeout=30)
                        self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
                        self.assertEqual(executed.stdout, "native GTK counter passed\n")
                        self.assertEqual(executed.stderr.count("Callback error: Error: Deliberate callback failure"), 1)
                        self.assertNotIn("Self-test failed", executed.stderr)
                        self.assertNotIn("Callback defect", executed.stderr)
                    self.assertEqual([p.name for p in package.iterdir()], [binary.name])
                    system_python = Path("/usr/bin/python3")
                    if os.environ.get("NATIVE_GTK_ATSPI") == "1":
                        accessible_env = dict(os.environ, GTK_A11Y="atspi", PATH="",
                                              HARDING_HOME=str(package / "absent"))
                        with subprocess.Popen([str(binary)], cwd=package, env=accessible_env,
                                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                              text=True) as process:
                            try:
                                actions = subprocess.run([str(system_python),
                                    str(ROOT / "tests/native_gtk_accessibility.py"), str(process.pid)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=30)
                                self.assertEqual(actions.returncode, 0, actions.stdout + actions.stderr)
                                print(mm + " AT-SPI: " + actions.stdout.strip(), flush=True)
                                stdout, stderr = process.communicate(timeout=10)
                                self.assertEqual(process.returncode, 0, stdout + stderr)
                                self.assertEqual(stderr.count("Callback error: Error: Deliberate callback failure"), 1)
                            finally:
                                if process.poll() is None:
                                    process.terminate()
                                    process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
