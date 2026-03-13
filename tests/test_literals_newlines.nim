#
# test_literals_newlines.nim - Tests for newlines in array and table literals
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

# Shared interpreter initialized once for all suites
var sharedInterp = newSharedStdlibInterpreter()

suite "Array Literals with Newlines":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "array literal with newline between elements":
    let result = interp.evalStatements("""
      Arr := #(
        1
        2
        3
      ).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "array literal with mixed newlines and spaces":
    let result = interp.evalStatements("""
      Arr := #(1
        2 3
        4).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 4)

  test "array literal with elements on separate lines":
    let result = interp.evalStatements("""
      Arr := #(
        "first"
        "second"
        "third"
      ).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "nested array literal with newlines":
    let result = interp.evalStatements("""
      Arr := #(
        #(1 2)
        #(3 4)
        #(5 6)
      ).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

suite "Table Literals with Newlines":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "table literal with newline between entries":
    let result = interp.evalStatements("""
      T := #{
        "a" -> 1
        "b" -> 2
        "c" -> 3
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "table literal with mixed newlines and commas":
    let result = interp.evalStatements("""
      T := #{ "a" -> 1,
        "b" -> 2,
        "c" -> 3 }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "table literal with entries on separate lines":
    let result = interp.evalStatements("""
      T := #{
        "name" -> "Alice"
        "age" -> 30
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "table literal value can be a unary message without parentheses":
    let result = interp.evalStatements("""
      Friend := Object derive.
      Friend selector: #name put: [ ^"Alice" ].
      myFriend := Friend new.
      T := #{ "his name" -> myFriend name }.
      Result := T at: "his name"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Alice")

  test "table literal newline entries do not require trailing commas":
    let result = interp.evalStatements("""
      T := #{
        "count" -> #(1 2 3) size
        "age" -> 42
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

suite "Quoted Symbol Literals":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "quoted symbol literal with whitespace parses and evaluates":
    let result = interp.evalStatements("Result := #\"my symbol\"")
    check(result[1].len == 0)
    check(result[0][^1].kind == vkSymbol)
    check(result[0][^1].symVal == "my symbol")

  test "quoted symbol literal with whitespace prints as symbol":
    let result = interp.evalStatements("Result := #\"my symbol\" printString")
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "#my symbol")

  test "nested table literal with newlines":
    let result = interp.evalStatements("""
      T := #{
        "first" -> #{ "x" -> 1 }
        "second" -> #{ "y" -> 2 }
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)
