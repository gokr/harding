#!/usr/bin/env nim
#
# Tests for website code examples from docs.md and index.md
# Verifies that code examples from the documentation work correctly
#

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

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

suite "Website Examples - docs.md Factorial":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Factorial (docs.md)":
    let results = interp.evalStatements("""
      | factorial |
      factorial := [:n |
          (n <= 1) ifTrue: [^ 1].
          ^ n * (factorial value: (n - 1))
      ]
      Result := factorial value: 5
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 120)

suite "Website Examples - docs.md Counter Class":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Counter class (docs.md)":
    let results = interp.evalStatements("""
      | c |
      Counter := Object derive: #(count)
      Counter >> initialize [ count := 0 ]
      Counter >> value [ ^count ]
      Counter >> increment [ ^count := count + 1]

      c := Counter new
      c initialize
      c increment
      Result := c value
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 1)

suite "Website Examples - docs.md Table":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Table literal with entries (docs.md)":
    let results = interp.evalStatements("""
      scores := #{\"Alice\" -> 95, \"Bob\" -> 87}
      Result := scores at: "Alice"
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 95)

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

suite "Website Examples - index.md deriveWithAccessors":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "deriveWithAccessors creates getters and setters":
    let results = interp.evalStatements("""
      Point := Object deriveWithAccessors: #(x y)
      p := Point new
      p x: 100
      p y: 200
      Result := p x
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 100)

  test "Point + operator with aPoint x syntax":
    let results = interp.evalStatements("""
      Point := Object deriveWithAccessors: #(x y)
      Point >>+ aPoint [
          x := x + aPoint x
          y := y + aPoint y
      ]
      p1 := Point new x: 10; y: 20
      p2 := Point new x: 5; y: 10
      p1 + p2
      Result := p1 x
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 15)

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
