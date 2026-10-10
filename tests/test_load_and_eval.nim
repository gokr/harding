import std/[unittest, os, strutils, tempfiles, tables]

import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

proc newStdlibInterpreter(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initProcessorGlobal(result)
  loadStdlib(result)

proc writeTempSource(name, source: string): string =
  createDir("build")
  let directory = createTempDir("load-eval-", "", "build")
  result = directory / name
  writeFile(result, source)

proc escapeHarding(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

suite "Load failure contract":
  test "core bootstrap defines LoadError":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("LoadError isClass and: [ LoadError new isKindOf: Error ]")
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "missing file signals catchable LoadError":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("""
      Caught := nil.
      [ Harding load: "build/load-eval-missing.hrd" ]
        on: LoadError
        do: [:ex | Caught := ex message ].
      Caught
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal.contains("missing"))

  test "parse errors signal LoadError and leave globals unchanged":
    var interp = newStdlibInterpreter()
    let path = writeTempSource("broken.hrd", "BrokenProbe := Object derive: #(.\n")
    defer: removeDir(parentDir(path))
    let (value, err) = interp.doit("""
      Caught := nil.
      [ Harding load: "PATH" ] on: LoadError do: [:ex | Caught := ex message ].
      (Harding includesKey: "BrokenProbe") or: [ Caught isNil ]
    """.replace("PATH", path))
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal == false)

  test "successful load still returns true":
    var interp = newStdlibInterpreter()
    let path = writeTempSource("good.hrd", "GoodProbe := Object derive: #().\nGoodProbe>>answer [ ^ 7 ].\n")
    defer: removeDir(parentDir(path))
    let (value, err) = interp.doit("""
      Loaded := Harding load: "PATH".
      Loaded and: [ GoodProbe new answer = 7 ]
    """.replace("PATH", path))
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "library load failure signals and does not capture bindings":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("""
      Lib := Library name: "LoadFailureProbe".
      Caught := nil.
      [ Lib load: "build/load-eval-missing-lib.hrd" ]
        on: LoadError
        do: [:ex | Caught := ex message ].
      Caught notNil and: [ Lib includesKey: "LoadFailureProbe" ]
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal == false)

suite "Structured evaluation results":
  test "evaluate: reports success with the result value":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("""
      Result := Object evaluate: "3 + 4".
      (Result at: "ok") and: [
        ((Result at: "value") = 7) and: [ (Result at: "error") isEmpty ]
      ]
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "evaluate: reports failures without raising":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("""
      Result := Object evaluate: "UnknownThing sendMessage".
      ((Result at: "ok") not) and: [ (Result at: "error") isEmpty not ]
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "results that look like error text are still successes":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("""
      Result := Object evaluate: "\"Error: not a failure\"".
      (Result at: "ok") and: [ (Result at: "value") = "Error: not a failure" ]
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "evaluate: shares the image so definitions remain visible":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("""
      Object evaluate: "EvaluateProbe := Object derive: #().".
      Object evaluate: "EvaluateProbe>>answer [ ^ 11 ]".
      Result := Object evaluate: "EvaluateProbe new answer".
      (Result at: "ok") and: [ (Result at: "value") = 11 ]
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "evaluate: shares source indexing with the caller":
    var interp = newStdlibInterpreter()
    let path = writeTempSource("indexed.hrd", "IndexedProbe := Object derive: #().\nIndexedProbe>>answer [ ^ 1 ].\n")
    defer: removeDir(parentDir(path))
    let infoCode = "Harding methodSourceInfoForClass: " & escapeHarding("IndexedProbe") &
      " selector: " & escapeHarding("answer")
    let (value, err) = interp.doit("""
      Harding load: PATH.
      Info := (Object evaluate: CODE) at: "value".
      (Info at: "found") and: [ (Info at: "file") includesSubString: "indexed.hrd" ]
    """.replace("PATH", escapeHarding(path)).replace("CODE", escapeHarding(infoCode)))
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "eval: keeps returning plain values and error strings":
    var interp = newStdlibInterpreter()
    let (value, err) = interp.doit("""
      Good := Object eval: "1 + 1".
      Bad := Object eval: "UnknownThing sendMessage".
      (Good = 2) and: [ (Bad isKindOf: String) and: [ Bad isEmpty not ] ]
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)
