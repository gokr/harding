#
# test_float_operations.nim - Tests for Float arithmetic, comparison, and utility methods
#
# Note: Float.hrd has a known bug where >= is not defined for Float
# (line 33 redefines > using primitiveGreaterOrEq: instead of defining >=)
# Tests that expose this bug are marked accordingly.
#

import std/[unittest]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
loadStdlib(sharedInterp)

suite "Float: Literals and Type":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "float literal has vkFloat kind":
    let (result, err) = interp.doit("3.14")
    check(err.len == 0)
    check(result.kind == vkFloat)

  test "float literal has correct value":
    let (result, err) = interp.doit("3.14")
    check(err.len == 0)
    check(result.floatVal > 3.13)
    check(result.floatVal < 3.15)

  test "integer division / produces float":
    let (result, err) = interp.doit("10 / 2")
    check(err.len == 0)
    check(result.kind == vkFloat)

  test "float class name is Float":
    let (result, err) = interp.doit("3.14 class name")
    check(err.len == 0)
    check(result.strVal == "Float")

suite "Float: Arithmetic":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "float addition":
    let results = interp.evalStatements("""
      Result := 1.5 + 2.5
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal > 3.9)
    check(results[0][^1].floatVal < 4.1)

  test "float subtraction":
    let results = interp.evalStatements("""
      Result := 5.0 - 1.5
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal > 3.4)
    check(results[0][^1].floatVal < 3.6)

  test "float multiplication":
    let results = interp.evalStatements("""
      Result := 2.0 * 3.5
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal > 6.9)
    check(results[0][^1].floatVal < 7.1)

  test "float division":
    let results = interp.evalStatements("""
      Result := 7.0 / 2.0
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal > 3.4)
    check(results[0][^1].floatVal < 3.6)

  test "sqrt of float":
    let results = interp.evalStatements("""
      Result := 9.0 sqrt
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal > 2.9)
    check(results[0][^1].floatVal < 3.1)

  test "float abs on negative":
    let results = interp.evalStatements("""
      N := 0.0 - 3.5.
      Result := N abs
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal > 3.4)
    check(results[0][^1].floatVal < 3.6)

  test "float negated":
    let results = interp.evalStatements("""
      Result := 2.5 negated
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal < -2.4)
    check(results[0][^1].floatVal > -2.6)

suite "Float: Comparison":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "float < returns true when less":
    let (result, err) = interp.doit("1.5 < 2.5")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "float < returns false when greater":
    let (result, err) = interp.doit("2.5 < 1.5")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "float = returns true when equal":
    let (result, err) = interp.doit("3.14 = 3.14")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "float = returns false when not equal":
    let (result, err) = interp.doit("3.14 = 2.71")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "float <> returns true when not equal":
    let (result, err) = interp.doit("3.14 <> 2.71")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "float <= returns true when less":
    let (result, err) = interp.doit("1.5 <= 2.5")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "float <= returns true when equal":
    let (result, err) = interp.doit("2.5 <= 2.5")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

suite "Float: Mixed Integer-Float":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "sqrt of integer produces float":
    let (result, err) = interp.doit("16 sqrt")
    check(err.len == 0)
    check(result.kind == vkFloat)

  test "float in ifTrue: condition":
    let results = interp.evalStatements("""
      X := 3.5.
      (X > 3.0) ifTrue: [ Result := "yes" ] ifFalse: [ Result := "no" ]
    """)
    check(results[1].len == 0)
    check(results[0][^1].strVal == "yes")

  test "float printString":
    let (result, err) = interp.doit("3.0 printString")
    check(err.len == 0)
    check(result.kind == vkString)

  test "float between:and:":
    let results = interp.evalStatements("""
      Result := 3.5 between: 3.0 and: 4.0
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "float between:and: returns false when out of range":
    let results = interp.evalStatements("""
      Result := 5.0 between: 3.0 and: 4.0
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == false)
