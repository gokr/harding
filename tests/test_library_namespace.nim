#!/usr/bin/env nim

import std/[os, strutils, unittest]
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

suite "Library namespaces":
  test "Library class>>name: creates a named library":
    var interp = newSharedStdlibInterpreter()
    let (result, err) = interp.doit("(Library name: \"MyLib\") name")
    check err.len == 0
    check result.kind == vkString
    check result.strVal == "MyLib"

  test "Library load: resolves relative to __sourceDir and sees prior bindings":
    let tempDir = getTempDir() / "harding_library_namespace_test"
    createDir(tempDir)
    writeFile(tempDir / "Alpha.hrd", "Alpha := Object derive. Alpha>>value [ ^ 41 ].")
    writeFile(tempDir / "Beta.hrd", "Beta := Object derive. Beta>>value [ ^ (Alpha new value) + 1 ].")

    var interp = newSharedStdlibInterpreter()
    let escapedDir = tempDir.replace("\\", "\\\\")
    let script = "MyLib := Library name: \"MyLib\". " &
      "MyLib at: \"__sourceDir\" put: \"" & escapedDir & "\". " &
      "MyLib load: \"Alpha.hrd\". " &
      "MyLib load: \"Beta.hrd\". " &
      "Harding import: MyLib. " &
      "(Beta new value)"
    let (result, err) = interp.doit(script)
    check err.len == 0
    check result.kind == vkInt
    if result.kind == vkInt:
      check result.intVal == 42

  test "Harding import: rejects conflicting bindings":
    var interp = newSharedStdlibInterpreter()
    let (result, err) = interp.doit("Lib1 := Library name: \"Lib1\". Lib1 at: \"Shared\" put: 1. Lib2 := Library name: \"Lib2\". Lib2 at: \"Shared\" put: 2. Harding import: Lib1. Harding import: Lib2. Shared")
    check err.len == 0
    check result.kind == vkInt
    if result.kind == vkInt:
      check result.intVal == 1
