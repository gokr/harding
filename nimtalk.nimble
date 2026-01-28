# Nimtalk - Prototype-based Smalltalk dialect for Nim
version = "0.1.0"
author = "Göran Krampe"
description = "Prototype-based Smalltalk dialect that compiles to Nim"
license = "MIT"

srcDir = "src"
bin = @["nimtalk/repl/ntalk", "nimtalk/compiler/ntalkc"]

# Current Nim version
requires "nim == 2.2.6"

# FFI dependencies
when defined(linux):
  requires "libffi"
when defined(macosx):
  passL "-ldl"

import os, strutils

task test, "Run all tests (automatic discovery via testament)":
  exec """
    echo "Running Nimtalk test suite..."
    echo "=== Running tests/test_*.nim ==="
    testament pattern "tests/test_*.nim" || true
    # echo "=== Running tests/category/*.nim ==="
    # testament pattern "tests/**/*.nim" || true
    # echo "=== Running tests/category/subcategory/*.nim ==="
    # testament pattern "tests/**/**/*.nim" || true
  """

task local, "Build and copy binaries to root directory":
  exec "nimble build"
  # Copy binaries to root directory for convenience
  exec "cp nimtalk/repl/ntalk ntalk 2>/dev/null || true"
  exec "cp nimtalk/compiler/ntalkc ntalkc 2>/dev/null || true"
  echo "Binaries available in root directory as ntalk and ntalkc"

task clean, "Clean build artifacts using build.nims":
  exec "nim e build.nims clean"

task install, "Install ntalk to ~/.local/bin/":
  var binPath = ""
  for possiblePath in ["ntalk", "nimtalk/repl/ntalk"]:
    if possiblePath.fileExists:
      binPath = possiblePath
      break

  when defined(windows):
    if binPath == "":
      for possiblePath in ["ntalk.exe", "nimtalk/repl/ntalk.exe"]:
        if possiblePath.fileExists:
          binPath = possiblePath
          break

  if binPath == "" or not binPath.fileExists:
    echo "Error: ntalk binary not found. Run 'nimble build' or 'nimble setup' first."
    echo "Checked locations: ./ntalk, nimtalk/repl/ntalk"
    system.quit(1)

  when defined(windows):
    let dest = getHomeDir() / "ntalk" / "ntalk.exe"
    exec "mkdir -p " & (getHomeDir() / "ntalk")
    exec "cp " & binPath & " " & dest
    echo "Installed to: " & dest
  else:
    let dest = getHomeDir() / ".local" / "bin" / "ntalk"
    exec "mkdir -p " & (getHomeDir() / ".local" / "bin")
    exec "cp " & binPath & " " & dest & " && chmod +x " & dest
    echo "Installed to: " & dest
