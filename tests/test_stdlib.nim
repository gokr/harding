#
# test_stdlib.nim - Comprehensive tests for Harding Standard Library
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/[vm, objects]

# Shared interpreter initialized once for all suites
# This avoids repeated newInterpreter + initGlobals + loadStdlib per test
var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
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
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
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
