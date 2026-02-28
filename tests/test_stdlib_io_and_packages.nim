import std/[unittest, os, strutils, tables]
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ../src/harding/interpreter/objects
import ../src/harding/packages/package_api

proc newStdlibInterpreter(args: seq[string] = @[]): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  result.commandLineArgs = args
  loadStdlib(result)

proc escapeHardingString(s: string): string =
  s.replace("\\", "\\\\").replace("\"", "\\\"")

proc findClass(interp: Interpreter, name: string): Class =
  if interp.globals[].hasKey(name):
    let clsVal = interp.globals[][name]
    if clsVal.kind == vkClass:
      return clsVal.classVal

  let classKey = toValue(name)
  for lib in interp.importedLibraries:
    if lib.kind == ikObject and lib.class != nil and lib.class.name == "Library":
      let bindingsVal = lib.slots[0]
      if bindingsVal.kind == vkInstance and bindingsVal.instVal.kind == ikTable:
        if classKey in bindingsVal.instVal.entries:
          let clsVal = bindingsVal.instVal.entries[classKey]
          if clsVal.kind == vkClass:
            return clsVal.classVal
  return nil

proc registerPkgPrimitives(interp: var Interpreter) {.nimcall.} =
  let pkgEchoClass = findClass(interp, "PkgEcho")
  if pkgEchoClass == nil:
    return

  proc pkgValueImpl(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    discard self
    discard args
    return toValue("ok")

  let primMethod = createCoreMethod("primitivePkgValue")
  primMethod.setNativeImpl(pkgValueImpl)
  pkgEchoClass.classMethods["primitivePkgValue"] = primMethod
  pkgEchoClass.allClassMethods["primitivePkgValue"] = primMethod

suite "Stdlib: IO and package loading":
  test "System arguments exposes process args":
    var interp = newStdlibInterpreter(@["alpha", "beta"])
    let (vals, err) = interp.evalStatements("""
      Args := System arguments.
      Result := Args at: 0
    """)
    check(err.len == 0)
    if err.len == 0:
      check(vals[^1].kind == vkString)
      check(vals[^1].strVal == "alpha")

  test "Std stream globals are available":
    var interp = newStdlibInterpreter()
    let (vals, err) = interp.evalStatements("""
      HasStdout := Harding includesKey: "Stdout".
      HasStderr := Harding includesKey: "Stderr".
      HasStdin := Harding includesKey: "Stdin".
      Result := HasStdout & HasStderr & HasStdin
    """)
    check(err.len == 0)
    if err.len == 0:
      check(vals[^1].kind == vkBool)
      check(vals[^1].boolVal)

  test "File class write/read roundtrip":
    var interp = newStdlibInterpreter()
    let tmpPath = getTempDir() / "harding_io_roundtrip.txt"
    defer:
      if fileExists(tmpPath):
        removeFile(tmpPath)

    let escapedPath = escapeHardingString(tmpPath)
    let code = "Path := \"" & escapedPath & "\".\n" &
               "File write: \"hello harding\" to: Path.\n" &
               "Result := File readAll: Path"

    let (vals, err) = interp.evalStatements(code)
    check(err.len == 0)
    if err.len == 0:
      check(vals[^1].kind == vkString)
      check(vals[^1].strVal == "hello harding")

  test "File exists: checks filesystem paths":
    var interp = newStdlibInterpreter()
    let missingPath = getTempDir() / "harding_missing_file.txt"
    if fileExists(missingPath):
      removeFile(missingPath)
    let escapedPath = escapeHardingString(missingPath)
    let code = "Result := File exists: \"" & escapedPath & "\""
    let (vals, err) = interp.evalStatements(code)
    check(err.len == 0)
    if err.len == 0:
      check(vals[^1].kind == vkBool)
      check(vals[^1].boolVal == false)

  test "Embedded package sources can load through Library load:":
    var interp = newStdlibInterpreter()

    let pkgSpec = HardingPackageSpec(
      name: "PkgDemo",
      version: "0.1.0",
      bootstrapPath: "pkg/Bootstrap.hrd",
      sources: @[
        (path: "pkg/Bootstrap.hrd", source: """
          Pkg := Library new.
          Pkg load: "pkg/Echo.hrd".
          Harding import: Pkg.
        """),
        (path: "pkg/Echo.hrd", source: """
          PkgEcho := Object derive: #().
          PkgEcho class>>value <primitive primitivePkgValue>
        """)
      ],
      registerPrimitives: registerPkgPrimitives
    )

    check(installPackage(interp, pkgSpec))

    let (vals, err) = interp.evalStatements("Result := PkgEcho value")
    check(err.len == 0)
    if err.len == 0:
      check(vals[^1].kind == vkString)
      check(vals[^1].strVal == "ok")
