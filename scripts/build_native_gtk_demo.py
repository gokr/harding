#!/usr/bin/env python3
"""Build the native GTK shell and Granite-compiled Harding counter (no VM startup)."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(directory, mm="arc", release=False):
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    subprocess.run(["pkg-config", "--exists", "gtk4"], check=True)
    subprocess.run([str(ROOT / "granite"), "compile",
                    str(ROOT / "demos/native-gtk-counter/counter_model.hrd"),
                    "--dir:" + str(directory), "-o:" + str(directory / "counter_model")], cwd=ROOT, check=True)
    shell = ROOT / "demos/native-gtk-counter/native_gtk_counter.nim"
    # Resolve the imports before staging; custom build directories stay usable.
    content = shell.read_text().replace("import ../../src/harding/runtime/compiled_support",
                                       'import "' + (ROOT / "src/harding/runtime/compiled_support").as_posix() + '"')
    (directory / shell.name).write_text(content)
    binary = directory / "native-gtk-counter"
    command = ["nim", "c", "--mm:" + mm, "--nimcache:" + str(directory / ("nimcache-" + mm)),
               "-o:" + str(binary)]
    if release:
        command.append("-d:release")
    subprocess.run(command + [str(directory / shell.name)], cwd=ROOT, check=True)
    return binary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, default=ROOT / "build/native-gtk-counter")
    parser.add_argument("--mm", choices=("arc", "orc"), default="arc")
    parser.add_argument("--release", action="store_true")
    options = parser.parse_args()
    if not (ROOT / "granite").is_file():
        parser.error("Build ./granite first")
    print(build(options.dir, options.mm, options.release))


if __name__ == "__main__":
    main()
