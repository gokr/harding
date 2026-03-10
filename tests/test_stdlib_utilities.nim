#
# test_stdlib_utilities.nim - Tests for utility functionality
# Includes: Object utilities, Accessor Generation, Library, Number - Advanced
#

import std/[unittest, os]
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

# Shared interpreter initialized once for all suites
var sharedInterp = newSharedStdlibInterpreter()

suite "Stdlib: Object utilities":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "isNil returns false for objects":
    let result = interp.evalStatements("""
      Obj := Object new.
      Result := Obj isNil
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "notNil returns true for objects":
    let result = interp.evalStatements("""
      Obj := Object new.
      Result := Obj notNil
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

suite "Stdlib: Direct Access":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "derivePublic: allows readable and writable slots":
    let result = interp.evalStatements("""
      Auto := Object derivePublic: #(x y).
      AutoInst := Auto new.
      AutoInst::x := 10.
      AutoInst::y := 20.
      Sum := AutoInst::x + AutoInst::y.
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 30)

  test "derivePublic: slot read returns correct value":
    let result = interp.evalStatements("""
      Auto := Object derivePublic: #(name).
      AutoInst := Auto new.
      AutoInst::name := "Test".
      Result := AutoInst::name
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Test")

  test "derive:read:write: stores selective direct access":
    let result = interp.evalStatements("""
      Selective := Object derive: #(x y)
                              read: #(x y)
                              write: #(x).
      SelInst := Selective new.
      SelInst::x := 5.
      XValue := SelInst::x.
      Result := XValue
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "derive:read:write: only grants specified direct access":
    let result = interp.evalStatements("""
      Selective := Object derive: #(x y)
                              read: #(x)
                              write: #(x).
      SelInst := Selective new.
      SelInst::x := 5.
      XValue := SelInst::x.
      Result := XValue
    """)
    check(result[0][^1].intVal == 5)

  test "derivePublic: works with multiple slots":
    let result = interp.evalStatements("""
      Multi := Object derivePublic: #(a b c d).
      MultiInst := Multi new.
      MultiInst::a := 1.
      MultiInst::b := 2.
      MultiInst::c := 3.
      MultiInst::d := 4.
      Total := MultiInst::a + MultiInst::b + MultiInst::c + MultiInst::d.
      Result := Total
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "derivePublic: works with string slots":
    let result = interp.evalStatements("""
      Person := Object derivePublic: #(name age).
      PersonInst := Person new.
      PersonInst::name := "Alice".
      PersonInst::age := 30.
      Greeting := PersonInst::name.
      Result := Greeting
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Alice")

  test "derivePublic: unread slot defaults to nil":
    let result = interp.evalStatements("""
      Thing := Object derivePublic: #(value).
      ThingInst := Thing new.
      Result := ThingInst::value
    """)
    check(result[1].len == 0)
    # In Harding, nil is represented as an instance of UndefinedObject
    check(result[0][^1].kind == vkInstance)

  test "derivePublic: creates readable and writable slot metadata":
    let result = interp.evalStatements("""
      PublicThing := Object derivePublic: #(name age).
      Result := PublicThing
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkClass)
    check(result[0][^1].classVal.readableSlotNames == @[
      "name", "age"
    ])
    check(result[0][^1].classVal.writableSlotNames == @[
      "name", "age"
    ])

  test "derive:read:write: stores direct access metadata":
    let result = interp.evalStatements("""
      Selective2 := Object derive: #(x y z)
                               read: #(x z)
                               write: #(y).
      Result := Selective2
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkClass)
    check(result[0][^1].classVal.readableSlotNames == @[
      "x", "z"
    ])
    check(result[0][^1].classVal.writableSlotNames == @[
      "y"
    ])

  test "derive:read:write:superclasses: stores ordered superclasses":
    let result = interp.evalStatements("""
      P1 := Object derive.
      P2 := Mixin derive.
      Parents := Array new.
      Parents add: P2.
      Child := P1 derive: #(value)
                  read: #(value)
                  write: #()
                  superclasses: Parents.
      Result := Child
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkClass)
    check(result[0][^1].classVal.superclasses.len == 2)
    check(result[0][^1].classVal.superclasses[0].name == "P1")
    check(result[0][^1].classVal.superclasses[1].name == "P2")

  test "multiple inheritance keeps first parent method and records conflict":
    let result = interp.evalStatements("""
      P1 := Mixin derive.
      P1>>greet [ ^ "from P1" ].
      P2 := Mixin derive.
      P2>>greet [ ^ "from P2" ].
      Parents := Array new.
      Parents add: P2.
      Child := P1 derive: #()
                  read: #()
                  write: #()
                  superclasses: Parents.
      Result := Array new.
      Result add: ((Child new) greet).
      Result add: (Child conflictSelectors size).
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)
    let arr = result[0][^1].instVal.elements
    check(arr[0].kind == vkString)
    check(arr[0].strVal == "from P1")
    check(arr[1].kind == vkInt)
    check(arr[1].intVal == 1)

  test ":: reads and writes declared public slots":
    let result = interp.evalStatements("""
      Point := Object derivePublic: #(x y).
      P := Point new.
      P::x := 10.
      P::y := 20.
      Result := P::x + P::y
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 30)

suite "Stdlib: Library":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Library new creates a Library instance":
    let result = interp.evalStatements("""
      Lib := Library new.
      Result := Lib
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)
    check(result[0][^1].instVal.class.name == "Library")

  test "Library at:put: and at: work":
    let result = interp.evalStatements("""
      Lib := Library new.
      Lib at: "myKey" put: 42.
      Result := Lib at: "myKey"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "Library keys returns bindings keys":
    let result = interp.evalStatements("""
      Lib := Library new.
      Lib at: "a" put: 1.
      Lib at: "b" put: 2.
      Result := Lib keys size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "Library includesKey: works":
    let result = interp.evalStatements("""
      Lib := Library new.
      Lib at: "present" put: 99.
      Result := Lib includesKey: "present"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "Library includesKey: returns false for missing key":
    let result = interp.evalStatements("""
      Lib := Library new.
      Result := Lib includesKey: "absent"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test ":: reads and writes table-style bindings on Library":
    let result = interp.evalStatements("""
      Lib := Library new.
      Lib::Thing := 42.
      Result := Lib::Thing
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test ":: reads and writes table keys":
    let result = interp.evalStatements("""
      Tbl := Table new.
      Tbl::answer := 99.
      Result := Tbl::answer
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

  test "Harding import: makes Library bindings accessible":
    var freshInterp = newInterpreter()
    initGlobals(freshInterp)
    loadStdlib(freshInterp)

    let result = freshInterp.evalStatements("""
      Lib := Library new.
      Lib at: "LibTestVal" put: 42.
      Harding import: Lib.
      Result := LibTestVal
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "imported Library does not pollute globals":
    var freshInterp = newInterpreter()
    initGlobals(freshInterp)
    loadStdlib(freshInterp)

    let result = freshInterp.evalStatements("""
      Lib := Library new.
      Lib at: "LibPrivate" put: 99.
      Result := Harding includesKey: "LibPrivate"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "globals still accessible after Library import":
    var freshInterp = newInterpreter()
    initGlobals(freshInterp)
    loadStdlib(freshInterp)

    let result = freshInterp.evalStatements("""
      Lib := Library new.
      Harding import: Lib.
      Result := Object
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkClass)

  test "most recent import wins on conflict":
    var freshInterp = newInterpreter()
    initGlobals(freshInterp)
    loadStdlib(freshInterp)

    let result = freshInterp.evalStatements("""
      Lib1 := Library new.
      Lib1 at: "SharedKey" put: 1.
      Lib2 := Library new.
      Lib2 at: "SharedKey" put: 2.
      Harding import: Lib1.
      Harding import: Lib2.
      Result := SharedKey
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "Library load: captures definitions into library":
    var freshInterp = newInterpreter()
    initGlobals(freshInterp)
    loadStdlib(freshInterp)

    let testFile = getCurrentDir() / "tests" / "test_lib_content.hrd"
    let result = freshInterp.evalStatements(
      "Lib := Library new.\n" &
      "Lib load: \"" & testFile & "\".\n" &
      "Result := Lib includesKey: \"LibTestConstant\"\n"
    )
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "Library load: does not pollute globals":
    var freshInterp = newInterpreter()
    initGlobals(freshInterp)
    loadStdlib(freshInterp)

    let testFile = getCurrentDir() / "tests" / "test_lib_content.hrd"
    let result = freshInterp.evalStatements(
      "Lib := Library new.\n" &
      "Lib load: \"" & testFile & "\".\n" &
      "Result := Harding includesKey: \"LibTestClass\"\n"
    )
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "Library load: then import makes classes accessible":
    var freshInterp = newInterpreter()
    initGlobals(freshInterp)
    loadStdlib(freshInterp)

    let testFile = getCurrentDir() / "tests" / "test_lib_content.hrd"
    let result = freshInterp.evalStatements(
      "Lib := Library new.\n" &
      "Lib load: \"" & testFile & "\".\n" &
      "Harding import: Lib.\n" &
      "Inst := LibTestClass new.\n" &
      "Inst::value := 99.\n" &
      "Result := Inst::value\n"
    )
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

suite "Stdlib: Source tracking":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "methodSourceInfo refreshes line offsets after file edits":
    let tmpDir = getTempDir() / "harding-test-stdlib-utilities-source"
    createDir(tmpDir)
    let filePath = tmpDir / "TrackedSource.hrd"
    defer:
      if fileExists(filePath):
        removeFile(filePath)
      if dirExists(tmpDir):
        removeDir(tmpDir)

    writeFile(filePath, "TrackedSource := Object derive.\nTrackedSource>>alpha [\n  ^ 1\n].\nTrackedSource>>beta [\n  ^ 2\n].\n")
    discard interp.evalStatements("Harding load: \"" & filePath & "\".")

    let first = interp.evalStatements("""
      Info := Harding methodSourceInfoForClass: "TrackedSource" selector: "beta".
      Result := Info at: "startLine"
    """)
    check(first[1].len == 0)
    check(first[0][^1].kind == vkInt)

    writeFile(filePath, "TrackedSource := Object derive.\nTrackedSource>>alpha [\n  ^ 1\n].\n\n\nTrackedSource>>beta [\n  ^ 2\n].\n")

    let second = interp.evalStatements("""
      Info := Harding methodSourceInfoForClass: "TrackedSource" selector: "beta".
      Result := Info at: "startLine"
    """)
    check(second[1].len == 0)
    check(second[0][^1].kind == vkInt)
    check(second[0][^1].intVal > first[0][^1].intVal)

  test "class definition source is indexed":
    let tmpDir = getTempDir() / "harding-test-stdlib-utilities-classdef"
    createDir(tmpDir)
    let filePath = tmpDir / "TrackedClassDef.hrd"
    defer:
      if fileExists(filePath):
        removeFile(filePath)
      if dirExists(tmpDir):
        removeDir(tmpDir)

    writeFile(filePath, "TrackedClassDef := Object derive: #(name) read: #(name) write: #(name) superclasses: #().\n# First class comment line\n# Second class comment line\n\n")
    discard interp.evalStatements("Harding load: \"" & filePath & "\".")

    let result = interp.evalStatements("""
      Info := Harding methodSourceInfoForClass: "TrackedClassDef" selector: "<classDefinition>".
      Result := Info at: "source"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "TrackedClassDef := Object derive: #(name) read: #(name) write: #(name) superclasses: #().\n# First class comment line\n# Second class comment line")

  test "sourceEntriesForClass returns ordered entries including class definition":
    let result = interp.evalStatements("""
      Entries := Harding sourceEntriesForClass: "TrackedClassDef".
      Result := Array new.
      Result add: (Entries size).
      Result add: ((Entries at: 0) at: "selector").
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)
    check(result[0][^1].instVal.elements[0].intVal >= 1)
    check(result[0][^1].instVal.elements[1].strVal == "<classDefinition>")

suite "Stdlib: Number - Advanced":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "between:and: returns true when in range":
    let result = interp.evalStatements("""
      Result := 5 between: 1 and: 10
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "between:and: returns false when out of range":
    let result = interp.evalStatements("""
      Result := 15 between: 1 and: 10
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "isZero returns true for zero":
    let (result, err) = interp.doit("0 isZero")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "isZero returns false for non-zero":
    let (result, err) = interp.doit("5 isZero")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "isPositive returns true for positive":
    let (result, err) = interp.doit("5 isPositive")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "isPositive returns false for negative":
    let result = interp.evalStatements("""
      N := 0 - 3.
      Result := N isPositive
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "isNegative returns true for negative":
    let result = interp.evalStatements("""
      N := 0 - 3.
      Result := N isNegative
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "sign returns 1 for positive":
    let (result, err) = interp.doit("5 sign")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 1)

  test "sign returns 0 for zero":
    let (result, err) = interp.doit("0 sign")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 0)

  test "sign returns -1 for negative":
    let result = interp.evalStatements("""
      N := 0 - 5.
      Result := N sign
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == -1)

  test "squared returns correct value":
    let (result, err) = interp.doit("7 squared")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 49)

  test "gcd: returns greatest common divisor":
    let result = interp.evalStatements("""
      Result := 12 gcd: 8
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 4)

  test "lcm: returns least common multiple":
    let result = interp.evalStatements("""
      Result := 4 lcm: 6
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 12)

  test "factorial returns correct value":
    let (result, err) = interp.doit("5 factorial")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 120)

  test "factorial of 0 returns 1":
    let (result, err) = interp.doit("0 factorial")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 1)
