# NimTalk - Prototype-based Smalltalk dialect for Nim
version = "0.1.0"
author = "NimTalk Author"
description = "Prototype-based Smalltalk dialect that compiles to Nim"
license = "MIT"

srcDir = "nimtalk"
bin = @["repl/main"]

# Current Nim version
requires "nim == 2.2.6"

# FFI dependencies
when defined(linux):
  requires "libffi"
when defined(macosx):
  passL "-ldl"
