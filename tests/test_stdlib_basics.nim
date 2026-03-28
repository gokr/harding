#
# test_stdlib_basics.nim - Tests for basic standard library functionality
# Includes: Numbers, Loops, Arrays (basic), Tables (basic)
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

# Shared interpreter initialized once for all suites
var sharedInterp = newSharedStdlibInterpreter()

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

  test "modulo \\ works":
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

suite "Stdlib: Reflection":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "class objects report isClass":
    let (result, err) = interp.doit("Object isClass")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "Object new returns an instance value":
    let (result, err) = interp.doit("Object new")
    check(err.len == 0)
    check(result.kind == vkInstance)
    if result.kind == vkInstance:
      check(result.instVal != nil)

  test "regular instances do not report isClass":
    let (result, err) = interp.doit("Object new isClass")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "primitive values do not report isClass":
    let (result, err) = interp.doit("1 isClass")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "definedMethods returns only class-local selectors":
    let (result, err) = interp.doit("BaseForDefined := Object derive. BaseForDefined selector: #foo put: [ ^ 1 ]. ChildForDefined := BaseForDefined derive. ChildForDefined selector: #bar put: [ ^ 2 ]. (ChildForDefined definedMethods includes: #bar) and: [ (ChildForDefined definedMethods includes: #foo) not ]")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "removeMethod removes selector from class":
    let (result, err) = interp.doit("RemoveMethodClass := Object derive. RemoveMethodClass selector: #tempMethod put: [ ^ 1 ]. RemoveMethodClass removeMethod: #tempMethod. (RemoveMethodClass methods includes: #tempMethod) not")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "methodSourceInfo primitive finds core method":
    let result = interp.evalStatements("""
      Info := Harding methodSourceInfoForClass: "Object" selector: "isNil".
      Result := Info at: "found"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "methodSourceInfo primitive finds keyword selector":
    let result = interp.evalStatements("""
      Info := Harding methodSourceInfoForClass: "Object" selector: "doesNotUnderstand:with:with:".
      Result := Info at: "found"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

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

  test "collect: preserves Array species":
    let result = interp.evalStatements("""
      Arr := #(1, 2, 3).
      Doubles := Arr collect: [ :n | n * 2 ].
      Result := Doubles className
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Array")

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
