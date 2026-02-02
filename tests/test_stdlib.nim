#
# test_stdlib.nim - Comprehensive tests for Nimtalk Standard Library
#

import std/[unittest, tables, strutils]
import ../src/nimtalk/core/types
import ../src/nimtalk/parser/[lexer, parser]
import ../src/nimtalk/interpreter/[evaluator, objects, activation]

suite "Stdlib: Numbers":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

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
      n := 0 - 5.
      result := n abs
    """)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "even works":
    let result = interp.evalStatements("result := 4 even")
    # Check it's a boolean (vkBool in class-based model)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "odd works":
    let result = interp.evalStatements("result := 5 odd")
    # Check it's a boolean (vkBool in class-based model)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "max: works":
    let result = interp.evalStatements("result := 3 max: 7")
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 7)

  test "min: works":
    let result = interp.evalStatements("result := 3 min: 7")
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

suite "Stdlib: Loops":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "whileTrue: loop works":
    let result = interp.evalStatements("""
      i := 0.
      sum := 0.
      [ i < 5 ] whileTrue: [
        sum := sum + i.
        i := i + 1
      ].
      result := sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)  # 0+1+2+3+4

  test "timesRepeat: works":
    let result = interp.evalStatements("""
      count := 0.
      5 timesRepeat: [ count := count + 1 ].
      result := count
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "to:do: works":
    let result = interp.evalStatements("""
      sum := 0.
      1 to: 10 do: [ :i | sum := sum + i ].
      result := sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 55)  # 1+2+...+10

suite "Stdlib: Arrays":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Array new creates empty array":
    let result = interp.evalStatements("""
      arr := Array new.
      result := arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "Array new: creates sized array":
    let result = interp.evalStatements("""
      arr := Array new: 100.
      result := arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 100)

  test "add: adds element to array":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 42.
      result := arr first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "size returns correct count":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 1.
      arr add: 2.
      arr add: 3.
      result := arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "first returns first element":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 10.
      arr add: 20.
      result := arr first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "last returns last element":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 10.
      arr add: 20.
      result := arr last
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 20)

  test "collect: transforms elements":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 1.
      arr add: 2.
      arr add: 3.
      doubles := arr collect: [ :n | n * 2 ].
      result := doubles size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "select: filters elements":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 1.
      arr add: 2.
      arr add: 3.
      arr add: 4.
      evens := arr select: [ :n | n even ].
      result := evens size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)  # 2 and 4

  test "reject: inverse filters elements":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 1.
      arr add: 2.
      arr add: 3.
      arr add: 4.
      odds := arr reject: [ :n | n even ].
      result := odds size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)  # 1 and 3

  test "inject:into: reduces elements":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 1.
      arr add: 2.
      arr add: 3.
      sum := arr inject: 0 into: [ :acc :n | acc + n ].
      result := sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 6)

  test "detect: finds first matching element":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 1.
      arr add: 3.
      arr add: 5.
      arr add: 6.
      found := arr detect: [ :n | n > 4 ].
      result := found
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "anySatisfy: returns true if any element matches":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 1.
      arr add: 3.
      arr add: 4.
      hasEven := arr anySatisfy: [ :n | n even ].
      result := hasEven
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "allSatisfy: returns true if all elements match":
    let result = interp.evalStatements("""
      arr := Array new.
      arr add: 2.
      arr add: 4.
      arr add: 6.
      allEven := arr allSatisfy: [ :n | n even ].
      result := allEven
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

suite "Stdlib: Tables":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Table new creates empty table":
    let result = interp.evalStatements("""
      t := Table new.
      result := t size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "at:put: stores values":
    let result = interp.evalStatements("""
      t := Table new.
      t at: "key" put: "value".
      result := t at: "key"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "value")

  test "includesKey: checks for key existence":
    let result = interp.evalStatements("""
      t := Table new.
      t at: "exists" put: "yes".
      result := t includesKey: "exists"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

suite "Stdlib: Strings":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "string size returns length":
    let result = interp.evalStatements("""
      s := "hello".
      result := s size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "string uppercase works":
    let result = interp.evalStatements("""
      s := "hello" uppercase.
      result := s
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "HELLO")

  test "string lowercase works":
    let result = interp.evalStatements("""
      s := "HELLO" lowercase.
      result := s
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "string trim works":
    let result = interp.evalStatements("""
      s := "  hello  " trim.
      result := s
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "string split: works":
    let result = interp.evalStatements("""
      arr := "a,b,c" split: ",".
      result := arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

suite "Stdlib: Object utilities":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "isNil returns false for objects":
    let result = interp.evalStatements("""
      obj := Object new.
      result := obj isNil
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "notNil returns true for objects":
    let result = interp.evalStatements("""
      obj := Object new.
      result := obj notNil
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)
