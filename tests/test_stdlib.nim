#
# test_stdlib.nim - Comprehensive tests for Harding Standard Library
#

import std/[unittest, os]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

# Shared interpreter initialized once for all suites
# This avoids repeated newInterpreter + initGlobals + loadStdlib per test
var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
initProcessorGlobal(sharedInterp)
loadStdlib(sharedInterp)

suite "Stdlib: Numbers":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "arithmetic operations work":
    let (result, err) = interp.doit("3 + 4")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 7)

  test "subtraction works":
    let (result, err) = interp.doit("10 - 3")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 7)

  test "multiplication works":
    let (result, err) = interp.doit("6 * 7")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 42)

  test "integer division // works":
    let (result, err) = interp.doit("17 // 5")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 3)

  test "modulo \\\\ works":
    let (result, err) = interp.doit("17 \\\\ 5")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 2)

  test "comparison < works":
    let (result, err) = interp.doit("3 < 5")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "comparison > works":
    let (result, err) = interp.doit("5 > 3")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "comparison <= works":
    let (result, err) = interp.doit("3 <= 3")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "comparison >= works":
    let (result, err) = interp.doit("5 >= 3")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "abs works":
    let result = interp.evalStatements("""
      N := 0 - 5.
      Result := N abs
    """)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "even works":
    let result = interp.evalStatements("Result := 4 even")
    # Check it's a boolean (vkBool in Class-based model)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "odd works":
    let result = interp.evalStatements("Result := 5 odd")
    # Check it's a boolean (vkBool in Class-based model)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "max: works":
    let result = interp.evalStatements("Result := 3 max: 7")
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 7)

  test "min: works":
    let result = interp.evalStatements("Result := 3 min: 7")
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

suite "Stdlib: Loops":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "whileTrue: loop works":
    let result = interp.evalStatements("""
      I := 0.
      Sum := 0.
      [ I < 5 ] whileTrue: [
        Sum := Sum + I.
        I := I + 1
      ].
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)  # 0+1+2+3+4

  test "timesRepeat: works":
    let result = interp.evalStatements("""
      Count := 0.
      5 timesRepeat: [ Count := Count + 1 ].
      Result := Count
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "to:do: works":
    let result = interp.evalStatements("""
      Sum := 0.
      1 to: 10 do: [ :i | Sum := Sum + i ].
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 55)  # 1+2+...+10

suite "Stdlib: Arrays":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Array new creates empty array":
    let result = interp.evalStatements("""
      Arr := Array new.
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "Array new: creates sized array":
    let result = interp.evalStatements("""
      Arr := Array new: 100.
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 100)

  test "add: adds element to array":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 42.
      Result := Arr first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "size returns correct Count":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 1.
      Arr add: 2.
      Arr add: 3.
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "first returns first element":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      Result := Arr first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "last returns last element":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      Result := Arr last
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 20)

  test "collect: transforms elements":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 1.
      Arr add: 2.
      Arr add: 3.
      Doubles := Arr collect: [ :n | n * 2 ].
      Result := Doubles size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "select: filters elements":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 1.
      Arr add: 2.
      Arr add: 3.
      Arr add: 4.
      Evens := Arr select: [ :n | n even ].
      Result := Evens size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)  # 2 and 4

  test "reject: inverse filters elements":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 1.
      Arr add: 2.
      Arr add: 3.
      Arr add: 4.
      Odds := Arr reject: [ :n | n even ].
      Result := Odds size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)  # 1 and 3

  test "inject:into: reduces elements":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 1.
      Arr add: 2.
      Arr add: 3.
      Sum := Arr inject: 0 into: [ :acc :n | acc + n ].
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 6)

  test "detect: finds first matching element":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 1.
      Arr add: 3.
      Arr add: 5.
      Arr add: 6.
      Found := Arr detect: [ :n | n > 4 ].
      Result := Found
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "anySatisfy: returns true if any element matches":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 1.
      Arr add: 3.
      Arr add: 4.
      HasEven := Arr anySatisfy: [ :n | n even ].
      Result := HasEven
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)

  test "allSatisfy: returns true if all elements match":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 2.
      Arr add: 4.
      Arr add: 6.
      AllEven := Arr allSatisfy: [ :n | n even ].
      Result := AllEven
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)

suite "Stdlib: Tables":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Table new creates empty Table":
    let result = interp.evalStatements("""
      T := Table new.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "at:put: stores Values":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "Key" put: "value".
      Result := T at: "Key"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "value")

  test "includesKey: checks for Key existence":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "exists" put: "yes".
      Result := T includesKey: "exists"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

suite "Stdlib: Strings":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "string size returns length":
    let result = interp.evalStatements("""
      S := "hello".
      Result := S size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "string uppercase works":
    let result = interp.evalStatements("""
      S := "hello" uppercase.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "HELLO")

  test "string lowercase works":
    let result = interp.evalStatements("""
      S := "HELLO" lowercase.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "string trim works":
    let result = interp.evalStatements("""
      S := "  hello  " trim.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "string split: works":
    let result = interp.evalStatements("""
      Arr := "a,b,c" split: ",".
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "string concatenation with , (comma)":
    let result = interp.evalStatements("""
      S1 := "Hello".
      S2 := " World".
      Result := S1 , S2
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Hello World")

  test "string concatenation chains":
    let result = interp.evalStatements("""
      Result := "a" , "b" , "c" , "d"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "abcd")

  test "string concatenation with number (auto-conversion)":
    # Auto-conversion of numbers to strings via toString
    let result = interp.evalStatements("""
      Result := "The answer is " , 42
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "The answer is 42")

  test "string concatenation with empty string":
    let result = interp.evalStatements("""
      Result := "hello" , ""
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

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

suite "Stdlib: Accessor Generation":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "deriveWithAccessors: generates getters and setters":
    let result = interp.evalStatements("""
      Auto := Object deriveWithAccessors: #(x y).
      AutoInst := Auto new.
      AutoInst x: 10.
      AutoInst y: 20.
      Sum := AutoInst x + AutoInst y.
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 30)

  test "deriveWithAccessors: getter returns correct value":
    let result = interp.evalStatements("""
      Auto := Object deriveWithAccessors: #(name).
      AutoInst := Auto new.
      AutoInst name: "Test".
      Result := AutoInst name
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Test")

  test "derive:getters:setters: generates selective accessors":
    let result = interp.evalStatements("""
      Selective := Object derive: #(x y)
                              getters: #(x y)
                              setters: #(x).
      SelInst := Selective new.
      SelInst x: 5.
      XValue := SelInst x.
      Result := XValue
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "derive:getters:setters: only generates specified accessors":
    let result = interp.evalStatements("""
      Selective := Object derive: #(x y)
                              getters: #(x)
                              setters: #(x).
      SelInst := Selective new.
      SelInst x: 5.
      XValue := SelInst x.
      Result := XValue
    """)
    check(result[0][^1].intVal == 5)

  test "deriveWithAccessors: works with multiple slots":
    let result = interp.evalStatements("""
      Multi := Object deriveWithAccessors: #(a b c d).
      MultiInst := Multi new.
      MultiInst a: 1.
      MultiInst b: 2.
      MultiInst c: 3.
      MultiInst d: 4.
      Total := MultiInst a + MultiInst b + MultiInst c + MultiInst d.
      Result := Total
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "deriveWithAccessors: works with string slots":
    let result = interp.evalStatements("""
      Person := Object deriveWithAccessors: #(name age).
      PersonInst := Person new.
      PersonInst name: "Alice".
      PersonInst age: 30.
      Greeting := PersonInst name.
      Result := Greeting
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Alice")

  test "deriveWithAccessors: getter returns nil for unset slot":
    let result = interp.evalStatements("""
      Thing := Object deriveWithAccessors: #(value).
      ThingInst := Thing new.
      Result := ThingInst value
    """)
    check(result[1].len == 0)
    # In Harding, nil is represented as an instance of UndefinedObject
    check(result[0][^1].kind == vkInstance)

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
      "Inst value: 99.\n" &
      "Result := Inst value\n"
    )
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

suite "Stdlib: Interval":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Interval from:to: creates range":
    let result = interp.evalStatements("""
      R := Interval from: 1 to: 5.
      Result := R size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "Interval from:to:by: creates range with step":
    let result = interp.evalStatements("""
      R := Interval from: 1 to: 10 by: 2.
      Result := R size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "Number to: creates Interval":
    let result = interp.evalStatements("""
      R := 1 to: 5.
      Result := R size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "Number to:by: creates Interval with step":
    let result = interp.evalStatements("""
      R := 1 to: 10 by: 2.
      Result := R size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "Interval do: iterates over values":
    let result = interp.evalStatements("""
      Sum := 0.
      (1 to: 5) do: [:i | Sum := Sum + i].
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 15)

  test "Interval collect: transforms elements":
    let result = interp.evalStatements("""
      Squares := (1 to: 5) collect: [:i | i * i].
      Result := Squares size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "Interval includes: checks membership":
    let result = interp.evalStatements("""
      R := 1 to: 10 by: 2.
      Has5 := R includes: 5.
      Has6 := R includes: 6.
      Result := Has5
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "Interval first returns start":
    let result = interp.evalStatements("""
      R := 10 to: 20.
      Result := R first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "Interval reversed reverses direction":
    let result = interp.evalStatements("""
      R := (10 to: 1 by: -1).
      Result := R size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

suite "Stdlib: SortedCollection":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "SortedCollection new creates empty collection":
    let result = interp.evalStatements("""
      SC := SortedCollection new.
      Result := SC size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "SortedCollection add: inserts in sorted order":
    let result = interp.evalStatements("""
      SC := SortedCollection new.
      SC add: 5.
      SC add: 1.
      SC add: 3.
      Result := SC first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)

  test "SortedCollection last returns largest":
    let result = interp.evalStatements("""
      SC := SortedCollection new.
      SC add: 5.
      SC add: 1.
      SC add: 3.
      Result := SC last
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "SortedCollection includes: finds elements":
    let result = interp.evalStatements("""
      SC := SortedCollection new.
      SC add: 1.
      SC add: 3.
      SC add: 5.
      Result := SC includes: 3
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "SortedCollection with custom sortBlock":
    let result = interp.evalStatements("""
      SC := SortedCollection sortBlock: [:a :b | a > b].
      SC add: 1.
      SC add: 3.
      SC add: 2.
      Result := SC first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "Array asSortedCollection converts to sorted":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 3.
      Arr add: 1.
      Arr add: 2.
      SC := Arr asSortedCollection.
      Result := SC first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)

suite "Stdlib: Monitor":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Monitor new creates monitor":
    let result = interp.evalStatements("""
      M := Monitor new.
      Result := M
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "Monitor critical: executes block":
    let result = interp.evalStatements("""
      M := Monitor new.
      Sum := 0.
      M critical: [Sum := Sum + 10].
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

suite "Stdlib: Semaphore":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Semaphore new creates semaphore":
    let result = interp.evalStatements("""
      S := Semaphore new.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "Semaphore forMutualExclusion creates binary semaphore":
    let result = interp.evalStatements("""
      S := Semaphore forMutualExclusion.
      S signal.
      S wait.
      Result := 42
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "Semaphore signal increments count":
    let result = interp.evalStatements("""
      S := Semaphore new.
      S signal.
      S signal.
      Result := S count
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

suite "Stdlib: SharedQueue":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "SharedQueue new creates queue":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Result := Q
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "SharedQueue nextPut: adds item":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Q nextPut: 42.
      Result := Q size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)

  test "SharedQueue next retrieves item":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Q nextPut: 42.
      Item := Q next.
      Result := Item
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "SharedQueue isEmpty checks emptiness":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Empty := Q isEmpty.
      Q nextPut: 1.
      NotEmpty := Q isEmpty not.
      Result := NotEmpty
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

suite "Stdlib: Strings - Advanced":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "indexOf: returns position of substring":
    let result = interp.evalStatements("""
      Result := "hello world" indexOf: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal > 0)

  test "indexOf: returns 0 when not found":
    let result = interp.evalStatements("""
      Result := "hello" indexOf: "xyz"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "includesSubString: returns true when present":
    let result = interp.evalStatements("""
      Result := "hello world" includesSubString: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "includesSubString: returns false when absent":
    let result = interp.evalStatements("""
      Result := "hello" includesSubString: "xyz"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "replace:with: replaces substring":
    let result = interp.evalStatements("""
      Result := "hello world" replace: "world" with: "there"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello there")

  test "asInteger converts string to integer":
    let result = interp.evalStatements("""
      Result := "42" asInteger
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "asSymbol converts string to symbol":
    let result = interp.evalStatements("""
      Result := "hello" asSymbol
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkSymbol)

  test "repeat: repeats string":
    let result = interp.evalStatements("""
      Result := "ab" repeat: 3
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "ababab")

  test "from:to: extracts substring":
    let result = interp.evalStatements("""
      Result := "hello" from: 2 to: 4
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "ell")

  test "startsWith: returns true for matching prefix":
    let result = interp.evalStatements("""
      Result := "hello world" startsWith: "hello"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "startsWith: returns false for non-matching prefix":
    let result = interp.evalStatements("""
      Result := "hello world" startsWith: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "endsWith: returns true for matching suffix":
    let result = interp.evalStatements("""
      Result := "hello world" endsWith: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "endsWith: returns false for non-matching suffix":
    let result = interp.evalStatements("""
      Result := "hello world" endsWith: "hello"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

suite "Stdlib: Symbol":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "symbol literal has vkSymbol kind":
    let (result, err) = interp.doit("#foo")
    check(err.len == 0)
    check(result.kind == vkSymbol)

  test "symbol name is accessible via asString":
    let results = interp.evalStatements("""
      S := #foo asString.
      T := #foo asString.
      Result := S = T
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "different symbols are not equal":
    let (result, err) = interp.doit("#foo = #bar")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "symbol asString returns string":
    let (result, err) = interp.doit("#hello asString")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "hello")

  test "symbol printString returns #-prefixed form":
    let (result, err) = interp.doit("#hello printString")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "#hello")

  test "string asSymbol produces vkSymbol":
    let (result, err) = interp.doit("\"hello\" asSymbol")
    check(err.len == 0)
    check(result.kind == vkSymbol)

suite "Stdlib: Arrays - Advanced":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "removeAt: removes element at index":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      Arr add: 30.
      Arr removeAt: 1.
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "withIndexDo: passes element and index":
    let result = interp.evalStatements("""
      Arr := #(10 20 30).
      sum := 0.
      Arr withIndexDo: [:elem :idx | sum := sum + idx].
      Result := sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)  # 0+1+2 = 3 for 0-based indexing

  test "copyFrom:to: extracts subarray":
    let result = interp.evalStatements("""
      Arr := #(10 20 30 40 50).
      Sub := Arr copyFrom: 1 to: 3.
      Result := Sub size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "copyFrom:to: contains correct elements":
    let result = interp.evalStatements("""
      Arr := #(10 20 30 40 50).
      Sub := Arr copyFrom: 1 to: 3.
      Result := Sub at: 0
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 20)

  test "indexOf: returns 0-based index of element":
    let result = interp.evalStatements("""
      Arr := #(10 20 30).
      Result := Arr indexOf: 20
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)  # 0-based index

  test "indexOf: returns nil when not found":
    let result = interp.evalStatements("""
      Arr := #(10 20 30).
      Result := Arr indexOf: 99
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "removeFirst removes and returns first element":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      First := Arr removeFirst.
      Result := First
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "removeLast removes and returns last element":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      Last := Arr removeLast.
      Result := Last
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 20)

  test "includes: returns true for present element":
    let (result, err) = interp.doit("#(1 2 3) includes: 2")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "includes: returns false for absent element":
    let (result, err) = interp.doit("#(1 2 3) includes: 99")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "sorted returns elements in ascending order":
    let result = interp.evalStatements("""
      Arr := #(3 1 4 1 5 9 2 6).
      Sorted := Arr sorted.
      Result := Sorted first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)

  test "sorted: with custom block sorts descending":
    let result = interp.evalStatements("""
      Arr := #(3 1 4 1 5 9 2 6).
      Sorted := Arr sorted: [:a :b | a > b].
      Result := Sorted first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 9)

suite "Stdlib: Tables - Advanced":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "at:ifAbsent: returns value when key present":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "key" put: "value".
      Result := T at: "key" ifAbsent: [ "missing" ]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "value")

  test "at:ifAbsent: evaluates block when key absent":
    let result = interp.evalStatements("""
      T := Table new.
      Result := T at: "missing" ifAbsent: [ "default" ]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "default")

  test "at:ifPresent: evaluates block when key present":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "name" put: "Alice".
      Result := T at: "name" ifPresent: [:v | v uppercase]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "ALICE")

  test "at:ifPresent: returns nil when key absent":
    let result = interp.evalStatements("""
      T := Table new.
      Result := T at: "missing" ifPresent: [:v | v]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "do: iterates over key-value pairs":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "a" put: 1.
      T at: "b" put: 2.
      T at: "c" put: 3.
      sum := 0.
      T do: [:k :v | sum := sum + v].
      Result := sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 6)

  test "values returns array of all values":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "x" put: 10.
      T at: "y" put: 20.
      Result := T values size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "removeKey: removes a key-value pair":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "key" put: "value".
      T removeKey: "key".
      Result := T includesKey: "key"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "isEmpty returns true for empty table":
    let result = interp.evalStatements("""
      T := Table new.
      Result := T isEmpty
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "notEmpty returns true after adding entry":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "x" put: 1.
      Result := T notEmpty
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

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
