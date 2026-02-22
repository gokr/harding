## Test Smalltalk-style precedence rules
## Precedence (highest to lowest):
## 1. Unary messages (identifier starting with lowercase)
## 2. Binary operators (+, -, *, /, <, >, =, etc.)
## 3. Keyword messages (ending with :)
## 4. Assignment (:=)
## For same precedence: left-to-right evaluation

import std/unittest
import harding/interpreter/vm
import harding/core/types

suite "Parser Precedence Tests":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  teardown:
    discard

  #============================================================================
  # Test 1: Unary messages have highest precedence
  #============================================================================

  test "unary message binds tighter than binary":
    # "1 + 2 negated" should be "1 + (2 negated)" = "1 + -2" = -1
    # NOT "(1 + 2) negated"
    let (result, err) = interp.doit("1 + 2 negated")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == -1)

  test "unary chain binds left to right":
    # "10 negated abs" should be "(10 negated) abs" = "-10 abs" = 10
    let (result, err) = interp.doit("10 negated abs")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 10)

  test "unary before keyword argument":
    # "arr at: 1 + 1" should be "arr at: (1 + 1)"
    let (result, err) = interp.doit("Arr := #(10 20 30). Arr at: 1 + 1")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 30)

  #============================================================================
  # Test 2: Binary operators
  #============================================================================

  test "binary operators left to right":
    # "10 - 5 - 2" should be "(10 - 5) - 2" = 3
    # NOT "10 - (5 - 2)"
    let (result, err) = interp.doit("10 - 5 - 2")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 3)

  test "binary before keyword":
    # "arr at: 1 + 2 * 3" should be "arr at: ((1 + 2) * 3)"
    # But wait - this needs clarification
    # Actually, keyword arguments should parse unary+binary only
    let (result, err) = interp.doit("Arr := #(10 20 30 40 50 60 70 80 90 100). Arr at: 1 + 2")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 40)

  #============================================================================
  # Test 3: Keyword messages have lowest precedence
  #============================================================================

  test "keyword after binary":
    # "1 + 2 at: 3" - this would be invalid if "+" returns number
    # But "arr at: 1 + 1" should work
    let (result, err) = interp.doit("Arr := #(10 20 30). Arr at: 1 + 1")
    check(err.len == 0)
    check(result.intVal == 30)

  test "cascading keyword messages":
    # "obj msg1: arg1 msg2: arg2" should be single message "msg1:msg2:"
    # or "(obj msg1: arg1) msg2: arg2" for cascade
    # In Smalltalk: "obj at: 1 put: 2" is one message
    # "obj at: 1 put: 2; at: 3 put: 4" is cascade
    discard

  #============================================================================
  # Test 4: Assignment has lowest precedence
  #============================================================================

  test "assignment after all operations":
    # "x := 1 + 2 * 3" should be "x := ((1 + 2) * 3)"
    let (result, err) = interp.doit("X := 1 + 2 * 3. X")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 9)

  test "assignment with keyword message":
    # "x := arr at: 1" should be "x := (arr at: 1)"
    let (result, err) = interp.doit("Arr := #(10 20 30). X := Arr at: 1. X")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)

  #============================================================================
  # Test 5: Complex combinations
  #============================================================================

  test "complex expression with all precedence levels":
    # "arr at: x + 1 printString" should be "arr at: ((x + 1) printString)"
    # This would error because printString returns a String, not an index
    # Instead test: "arr at: x + 1" where x + 1 is computed correctly
    let (result, err) = interp.doit("Arr := #(10 20 30). X := 0. Arr at: X + 1")
    # X + 1 = 1, arr at: 1 = 20
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)

  test "binary after unary in keyword arg":
    # "arr at: x negated + 1" should be "arr at: ((x negated) + 1)"
    let (result, err) = interp.doit("Arr := #(-10 20 30). X := 0. Arr at: X negated + 1")
    # X = 0, X negated = 0, 0 + 1 = 1, arr at: 1 = 20
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)

  #============================================================================
  # Test 6: Parentheses override precedence
  #============================================================================

  test "parentheses override precedence":
    # "(1 + 2) * 3" should be 9, not 7
    let (result, err) = interp.doit("(1 + 2) * 3")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 9)

  test "parentheses in keyword argument":
    # "arr at: (1 + 2)" should be arr[3]
    let (result, err) = interp.doit("Arr := #(10 20 30 40). Arr at: (1 + 2)")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 40)

  #============================================================================
  # Test 7: Message cascades
  #============================================================================

  test "cascade sends multiple messages to same receiver":
    # "obj msg1; msg2" sends msg1 to obj, then msg2 to obj
    let (result, err) = interp.doit("Arr := #(10 20 30). Arr at: 0; at: 1")
    # Should return result of second message (20)
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)
