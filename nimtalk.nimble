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
