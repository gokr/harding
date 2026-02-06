# Harding - Modern Smalltalk dialect
version = "0.3.0"
author = "Göran Krampe"
description = "Modern Smalltalk dialect written in Nim"
license = "MIT"

srcDir = "src"
bin = @["harding/repl/harding","harding/compiler/granite"]

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
    echo "Running Harding test suite..."
    echo "=== Running tests/test_*.nim ==="
    testament pattern "tests/test_*.nim" || true
    # echo "=== Running tests/category/*.nim ==="
    # testament pattern "tests/**/*.nim" || true
    # echo "=== Running tests/category/subcategory/*.nim ==="
    # testament pattern "tests/**/**/*.nim" || true
  """

task local, "Build and copy binaries to root directory":
  # Build REPL directly (nimble build has path conflicts with package name)
  exec "nim c -o:harding src/harding/repl/harding.nim"
  exec "nim c -o:granite src/harding/compiler/granite.nim"
  echo "Binaries available in root directory as harding and granite"

task gui, "Build the GUI IDE with GTK4":
  # Build the GUI IDE with GTK4 (default)
  exec "nim c -d:gtk4 -o:bona src/harding/gui/bona.nim"
  echo "GUI binary available as bona (GTK4)"

task gui3, "Build the GUI IDE with GTK3":
  # Build the GUI IDE with GTK3
  exec "nim c -o:bona src/harding/gui/bona.nim"
  echo "GUI binary available as bona (GTK3)"

task clean, "Clean build artifacts using build.nims":
  exec "nim e build.nims clean"


task vsix, "Build the VS Code extension (vsix file)":
  ## Build the Harding VS Code extension package
  ## Requires vsce to be installed: npm install -g vsce
  if not "package.json".fileExists:
    echo "Error: package.json not found in current directory"
    system.quit(1)
  exec "vsce package"
  echo "VSIX file built successfully"
