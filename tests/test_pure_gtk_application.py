"""One .hrd GTK application, interpreted and compiled, with source-free packaging."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def gui_available():
    return bool((os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
                and shutil.which("pkg-config") and shutil.which("nim")
                and subprocess.run(["pkg-config", "--exists", "gtk4"]).returncode == 0)


class GtkCompilerGateTest(unittest.TestCase):
    def test_incompatible_modes_are_rejected(self):
        source = ROOT / "demos/native-gtk-counter/counter.hrd"
        for flag in ("--mixed", "--freeze-manifest:config/granite-frozen.json"):
            refused = subprocess.run([str(ROOT / "granite"), "compile", "--gtk", flag, str(source)],
                                     cwd=ROOT, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("--gtk currently requires pure compilation", refused.stdout)


@unittest.skipUnless(gui_available(), "Requires GTK4 and a graphical session")
class PureGtkApplicationTest(unittest.TestCase):
    def run_checked(self, command, **kwargs):
        completed = subprocess.run(command, capture_output=True, text=True, timeout=180, **kwargs)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return completed

    def test_same_hrd_in_both_engines_and_binary_only_native_package(self):
        base = ROOT / "build/pure-gtk-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            source = ROOT / "demos/native-gtk-counter/counter.hrd"
            for mm in ("arc", "orc"):
                with self.subTest(mm=mm):
                    generated_dir = work / (mm + " generated")
                    generated_dir.mkdir()
                    native = generated_dir / "counter"
                    self.run_checked([str(ROOT / "granite"), "build", "--gtk", str(source),
                                      "--dir:" + str(generated_dir), "-o:" + str(native)], cwd=ROOT)
                    if mm == "orc":
                        self.run_checked(["nim", "c", "--mm:orc", "-d:release",
                            "--nimcache:" + str(work / "orc-native-cache"), "-o:" + str(native),
                            str(generated_dir / "counter.nim")], cwd=ROOT)
                    generated = (generated_dir / "counter.nim").read_text()
                    self.assertIn("registerNativeGtk()", generated)
                    for forbidden in ("initHybridRuntime(", "loadStdlib(", "evalStatements("):
                        self.assertNotIn(forbidden, generated)
                    interpreter = work / ("harding_gtk_" + mm)
                    self.run_checked(["nim", "c", "--mm:" + mm,
                        "--nimcache:" + str(work / (mm + "-interpreter-cache")),
                        "-o:" + str(interpreter), str(ROOT / "src/harding/repl/harding_gtk.nim")], cwd=ROOT)
                    interpreted = self.run_checked([str(interpreter), str(source), "--self-test"], cwd=ROOT)
                    self.assertEqual(interpreted.stdout, "pure GTK counter passed\n")
                    package = work / (mm + "-package")
                    package.mkdir()
                    packaged = package / "counter"
                    shutil.copy2(native, packaged)
                    shutil.rmtree(generated_dir)
                    environment = dict(os.environ, PATH="", HARDING_HOME=str(package / "absent"))
                    for repetition in range(3):
                        executed = self.run_checked([str(packaged), "--self-test"], cwd=package, env=environment)
                        self.assertEqual(executed.stdout, interpreted.stdout)
                        self.assertEqual(executed.stderr, interpreted.stderr)
                        self.assertEqual(executed.stderr.count("GTK callback error:"), 1)
                        self.assertNotIn("CRITICAL", executed.stderr)
                    self.assertEqual([p.name for p in package.iterdir()], ["counter"])
                    if os.environ.get("NATIVE_GTK_ATSPI") == "1":
                        for name, command, cwd, env in [
                            ("interpreted", [str(interpreter), str(source)], ROOT, dict(os.environ, GTK_A11Y="atspi")),
                            ("native", [str(packaged)], package, dict(environment, GTK_A11Y="atspi")),
                        ]:
                            with subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                                  stderr=subprocess.PIPE, text=True) as process:
                                try:
                                    actions = self.run_checked(["/usr/bin/python3",
                                        str(ROOT / "tests/native_gtk_accessibility.py"), str(process.pid)], cwd=ROOT)
                                    print(mm, name, actions.stdout.strip(), flush=True)
                                    stdout, stderr = process.communicate(timeout=10)
                                    self.assertEqual(process.returncode, 0, stdout + stderr)
                                    self.assertEqual(stderr.count("GTK callback error:"), 1)
                                    self.assertNotIn("CRITICAL", stderr)
                                finally:
                                    if process.poll() is None:
                                        process.terminate()
                                        process.communicate(timeout=5)

    def test_script_definitions_and_temporaries_keep_their_scope(self):
        base = ROOT / "build/pure-gtk-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            source = work / "script.hrd"
            source.write_text('''| value |
Local := Object derivePublic: #(stored).
Local class>>answer [ ^ 42 ].
value := Local answer.
GtkApplication run: "org.hardinglang.ScriptGtk" activate: [
  (GtkLabel text: value printString) text println.
  GtkApplication quit
].
''')
            binary = work / "script"
            self.run_checked([str(ROOT / "granite"), "build", "--gtk", str(source),
                              "--dir:" + str(work), "-o:" + str(binary)], cwd=ROOT)
            result = self.run_checked([str(binary)], cwd=work)
            self.assertEqual(result.stdout, "42\n")

    def test_explicit_compile_main_scopes_keep_gtk_definitions(self):
        base = ROOT / "build/pure-gtk-tests"
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temporary:
            work = Path(temporary)
            source = work / "scoped.hrd"
            source.write_text('''Harding compile: [Local := Object derive: #(). Local class>>answer [ ^ 42 ]].
Harding main: [
  GtkApplication run: "org.hardinglang.ScopedGtk" activate: [
    | label |
    label := GtkLabel text: (Local answer printString).
    label text println.
    GtkApplication quit
  ]
].
''')
            binary = work / "scoped"
            self.run_checked([str(ROOT / "granite"), "build", "--gtk", str(source),
                              "--dir:" + str(work), "-o:" + str(binary)], cwd=ROOT)
            result = self.run_checked([str(binary)], cwd=work)
            self.assertEqual(result.stdout, "42\n")


if __name__ == "__main__":
    unittest.main()
