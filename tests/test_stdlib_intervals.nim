#
# test_stdlib_intervals.nim - Tests for interval and sorted collection functionality
# Includes: Interval, SortedCollection
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

# Shared interpreter initialized once for all suites
var sharedInterp = newSharedStdlibInterpreter()

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

  test "Interval collect: returns Array species":
    let result = interp.evalStatements("""
      Squares := (1 to: 5) collect: [:i | i * i].
      Result := Squares className
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Array")

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

  test "SortedCollection collect: preserves sort policy":
    let result = interp.evalStatements("""
      SC := SortedCollection sortBlock: [:a :b | a > b].
      SC add: 1.
      SC add: 3.
      SC add: 2.
      Mapped := SC collect: [:each | each * 10].
      Result := Mapped first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 30)
