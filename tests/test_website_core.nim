#!/usr/bin/env nim
#
# Tests for core language features from website examples
# Covers control flow, arithmetic, strings, nil, and block returns
#

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

suite "Website Examples - Control Flow":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "true ifTrue: executes block":
    let (result, err) = interp.doit("true ifTrue: [42]")
    check(err.len == 0)
    check(result.intVal == 42)

  test "false ifFalse: executes block":
    let (result, err) = interp.doit("false ifFalse: [99]")
    check(err.len == 0)
    check(result.intVal == 99)

  test "Block value: invocation":
    let (result, err) = interp.doit("[:x | x * 2] value: 5")
    check(err.len == 0)
    check(result.intVal == 10)

suite "Website Examples - Boolean Operations":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Boolean equality":
    let (result, err) = interp.doit("true = true")
    check(err.len == 0)

  test "Boolean not equal":
    let (result, err) = interp.doit("true ~= false")
    check(err.len == 0)

suite "Website Examples - Arithmetic":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Addition":
    let (result, err) = interp.doit("3 + 4")
    check(err.len == 0)
    check(result.intVal == 7)

  test "Subtraction":
    let (result, err) = interp.doit("10 - 3")
    check(err.len == 0)
    check(result.intVal == 7)

  test "Multiplication":
    let (result, err) = interp.doit("6 * 7")
    check(err.len == 0)
    check(result.intVal == 42)

  test "Division":
    let (result, err) = interp.doit("10 / 2")
    check(err.len == 0)
    check(result.kind == vkFloat)

  test "Integer division (//)":
    let (result, err) = interp.doit("10 // 3")
    check(err.len == 0)
    check(result.intVal == 3)

  test "Modulo (%)":
    let (result, err) = interp.doit("10 % 3")
    check(err.len == 0)
    check(result.intVal == 1)

suite "Website Examples - Comparison":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Less than":
    let (result, err) = interp.doit("3 < 5")
    check(err.len == 0)

  test "Greater than":
    let (result, err) = interp.doit("5 > 3")
    check(err.len == 0)

  test "Less than or equal":
    let (result, err) = interp.doit("3 <= 3")
    check(err.len == 0)

  test "Greater than or equal":
    let (result, err) = interp.doit("5 >= 3")
    check(err.len == 0)

  test "Equality with =":
    let (result, err) = interp.doit("3 = 3")
    check(err.len == 0)

suite "Website Examples - String Operations":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "String literal":
    let (result, err) = interp.doit("\"Hello\"")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Hello")

  test "String size":
    let (result, err) = interp.doit("\"Hello\" size")
    check(err.len == 0)
    check(result.intVal == 5)

  test "String at: index":
    let (result, err) = interp.doit("\"ABC\" at: 2")
    check(err.len == 0)
    check(result.strVal == "B")

suite "Website Examples - REPL Examples":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "REPL sequence 1 - Basic arithmetic":
    let results = interp.evalStatements("3 + 4")
    check(results[1].len == 0)
    check(results[0][0].intVal == 7)

  test "REPL sequence 2 - Collections":
    let results = interp.evalStatements("""
      numbers := #(1 2 3 4 5)
      Result := numbers size
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 5)

  test "REPL sequence 3 - Table":
    let results = interp.evalStatements("""
      T := Table new
      T at: "key" put: "value"
      Result := T at: "key"
    """)
    check(results[1].len == 0)
    check(results[0][^1].strVal == "value")

suite "Website Examples - Nil Object":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "nil isNil returns true":
    let (result, err) = interp.doit("nil isNil")
    check(err.len == 0)

  test "nil class returns UndefinedObject":
    let (result, err) = interp.doit("nil class name")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "UndefinedObject")

suite "Website Examples - Math Operations":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "sqrt of number":
    let results = interp.evalStatements("""
      Result := 16 sqrt
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)
    check(results[0][^1].floatVal > 3.9)

  test "distanceFromOrigin calculation":
    let results = interp.evalStatements("""
      | x y |
      x := 3.
      y := 4.
      Result := ((x * x) + (y * y)) sqrt
    """)
    check(results[1].len == 0)
    check(results[0][^1].floatVal > 4.9)

suite "Website Examples - Block Return":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Non-local return from block":
    let results = interp.evalStatements("""
      | findPositive |
      findPositive := [:arr |
          arr do: [:n |
              (n > 0) ifTrue: [^ n]
          ].
          ^ nil
      ]
      Result := findPositive value: #(-1 -2 5 -3)
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 5)
