#!/usr/bin/env nim
#
# Tests for website code examples
# Verifies that code examples from the website work correctly
#

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/[vm, objects]

suite "Website Examples - docs.md Example Code":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Hello World (docs.md)":
    let (result, err) = interp.doit("\"Hello, World!\" println")
    check(err.len == 0)
    # println returns string, but we just check no error

  test "Simple block assignment":
    let results = interp.evalStatements("""
      factorial := [:n | n + 1]
      Result := factorial value: 5
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 6)

  test "IfTrue: block execution":
    let (result, err) = interp.doit("true ifTrue: [42]")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 42)

suite "Website Examples - features.md Message Passing":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Binary message (3 + 4)":
    let (result, err) = interp.doit("3 + 4")
    check(err.len == 0)
    check(result.intVal == 7)

  test "Unary message class":
    let (result, err) = interp.doit("true class")
    check(err.len == 0)
    check(result.kind == vkClass)

  test "Keyword message Table at:put:":
    let results = interp.evalStatements("""
      T := Table new
      T at: "foo" put: 42
      Result := T at: "foo"
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 42)

suite "Website Examples - features.md Modern Syntax":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Optional periods (no period)":
    let results = interp.evalStatements("""
      x := 1
      y := 2
      Result := x + y
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 3)

  test "Double-quoted strings":
    let (result, err) = interp.doit("\"Double quotes\"")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Double quotes")

suite "Website Examples - features.md Class Creation":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Class creation with derive":
    let results = interp.evalStatements("Point := Object derive: #(x y)")
    check(results[1].len == 0)
    check(results[0][0].kind == vkClass)

  test "Method definition with selector:put:":
    let results = interp.evalStatements("""
      Calculator := Object derive
      Calculator selector: #add:to: put: [:x :y | x + y]
      C := Calculator new
      Result := C add: 5 to: 10
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 15)

  test "Instance creation with new":
    let results = interp.evalStatements("""
      Point := Object derive: #(x y)
      p := Point new
      Result := p class
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkClass)

suite "Website Examples - features.md Collections":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Array literal":
    let (result, err) = interp.doit("#(1 2 3 4 5)")
    check(err.len == 0)
    check(result.instVal.kind == ikArray)
    check(result.instVal.elements.len == 5)

  test "Table literal":
    let (result, err) = interp.doit("#{\"Alice\" -> 95}")
    check(err.len == 0)
    check(result.kind == vkInstance)
    check(result.instVal.kind == ikTable)

  test "Array element access (at:)":
    let results = interp.evalStatements("""
      arr := #(10 20 30)
      Result := arr at: 2
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 20)

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

suite "Website Examples - index.md Quick Start":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Quick Start: 3 + 4":
    let (result, err) = interp.doit("3 + 4")
    check(err.len == 0)
    check(result.intVal == 7)

  test "Quick Start: Array literal":
    let (result, err) = interp.doit("#(1 2 3)")
    check(err.len == 0)
    check(result.instVal.kind == ikArray)
    check(result.instVal.elements.len == 3)

suite "Website Examples - differences from Smalltalk":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Hash comments":
    let source = """
      # This is a comment
      3 + 4
    """.strip()
    let (result, err) = interp.doit(source)
    check(err.len == 0)
    check(result.intVal == 7)

  test "Double-quoted strings":
    let (result, err) = interp.doit("\"Hello\"")
    check(err.len == 0)
    check(result.kind == vkString)

  test "Optional periods (newline separator)":
    let results = interp.evalStatements("""
      x := 1
      y := 2
      Result := x + y
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 3)
    check(results[0][0].intVal == 1)
    check(results[0][1].intVal == 2)
