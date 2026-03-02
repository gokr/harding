#
# test_set_operations.nim - Tests for Set class operations
#
# Set is fully implemented in objects.nim and declared in lib/core/Set.hrd
# Key selectors: new, add:, remove:, includes:, size, isEmpty, do:,
#                union:, intersection:, difference:
#

import std/[unittest]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
loadStdlib(sharedInterp)

suite "Set: Creation and Basic Operations":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Set new creates empty set":
    let results = interp.evalStatements("""
      S := Set new.
      Result := S size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 0)

  test "Set isEmpty returns true for empty set":
    let results = interp.evalStatements("""
      S := Set new.
      Result := S isEmpty
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "Set add: increases size":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 1.
      S add: 2.
      S add: 3.
      Result := S size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 3)

  test "Set add: is idempotent (no duplicates)":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 1.
      S add: 1.
      S add: 1.
      Result := S size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 1)

  test "Set includes: returns true for added element":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 42.
      Result := S includes: 42
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "Set includes: returns false for absent element":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 1.
      Result := S includes: 99
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == false)

  test "Set remove: decreases size":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 1.
      S add: 2.
      S add: 3.
      S remove: 2.
      Result := S size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 2)

  test "Set remove: element is no longer included":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 5.
      S remove: 5.
      Result := S includes: 5
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == false)

  test "Set isEmpty returns false after adding elements":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 1.
      Result := S isEmpty
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == false)

suite "Set: Iteration":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Set do: accumulates sum":
    let results = interp.evalStatements("""
      S := Set new.
      S add: 1.
      S add: 2.
      S add: 3.
      Sum := 0.
      S do: [:each | Sum := Sum + each].
      Result := Sum
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 6)

  test "Set do: on empty set does nothing":
    let results = interp.evalStatements("""
      S := Set new.
      Count := 0.
      S do: [:each | Count := Count + 1].
      Result := Count
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 0)

suite "Set: Set Operations":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "union: produces correct size":
    let results = interp.evalStatements("""
      S1 := Set new.
      S1 add: 1. S1 add: 2. S1 add: 3.
      S2 := Set new.
      S2 add: 2. S2 add: 3. S2 add: 4.
      U := S1 union: S2.
      Result := U size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 4)

  test "intersection: produces correct size":
    let results = interp.evalStatements("""
      S1 := Set new.
      S1 add: 1. S1 add: 2. S1 add: 3.
      S2 := Set new.
      S2 add: 2. S2 add: 3. S2 add: 4.
      I := S1 intersection: S2.
      Result := I size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 2)

  test "intersection: shared elements are included":
    let results = interp.evalStatements("""
      S1 := Set new.
      S1 add: 1. S1 add: 2. S1 add: 3.
      S2 := Set new.
      S2 add: 2. S2 add: 3. S2 add: 4.
      I := S1 intersection: S2.
      Result := I includes: 2
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "difference: produces correct size":
    let results = interp.evalStatements("""
      S1 := Set new.
      S1 add: 1. S1 add: 2. S1 add: 3.
      S2 := Set new.
      S2 add: 2. S2 add: 3.
      D := S1 difference: S2.
      Result := D size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 1)

  test "difference: excluded elements are absent":
    let results = interp.evalStatements("""
      S1 := Set new.
      S1 add: 1. S1 add: 2. S1 add: 3.
      S2 := Set new.
      S2 add: 2. S2 add: 3.
      D := S1 difference: S2.
      Result := D includes: 1
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "disjoint intersection has size 0":
    let results = interp.evalStatements("""
      S1 := Set new.
      S1 add: 1. S1 add: 2.
      S2 := Set new.
      S2 add: 3. S2 add: 4.
      I := S1 intersection: S2.
      Result := I size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 0)

  test "union: does not mutate original sets":
    let results = interp.evalStatements("""
      S1 := Set new.
      S1 add: 1. S1 add: 2.
      S2 := Set new.
      S2 add: 3. S2 add: 4.
      U := S1 union: S2.
      Result := S1 size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 2)

suite "Set: Mixed Element Types":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Set with string elements":
    let results = interp.evalStatements("""
      S := Set new.
      S add: "apple".
      S add: "banana".
      S add: "apple".
      Result := S size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 2)

  test "Set includes: works with strings":
    let results = interp.evalStatements("""
      S := Set new.
      S add: "hello".
      Result := S includes: "hello"
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)
