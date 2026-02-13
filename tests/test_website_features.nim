#!/usr/bin/env nim
#
# Tests for website code examples from features.md
# Verifies that code examples from the features documentation work correctly
#

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

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

suite "Website Examples - features.md Point Class":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "Point class with extend: for multiple methods":
    let results = interp.evalStatements("""
      | p |
      Point := Object derive: #(x y)
      Point >> x: val [ x := val ]
      Point >> y: val [ y := val ]

      Point extend: [
          self >> moveBy: dx and: dy [
              x := x + dx.
              y := y + dy
          ]
          self >> distanceFromOrigin [
              ^ ((x * x) + (y * y)) sqrt
          ]
      ]

      p := Point new
      p x: 100; y: 200
      Result := p distanceFromOrigin
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkFloat)

suite "Website Examples - features.md Collection Methods":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "collect: transformation":
    let results = interp.evalStatements("""
      numbers := #(1 2 3 4 5)
      squares := numbers collect: [:n | n * n]
      Result := squares at: 3
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 9)

  test "select: filter with modulus":
    let results = interp.evalStatements("""
      numbers := #(1 2 3 4 5)
      evens := numbers select: [:n | (n % 2) = 0]
      Result := evens size
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 2)

  test "inject:into: reduce":
    let results = interp.evalStatements("""
      numbers := #(1 2 3 4 5)
      sum := numbers inject: 0 into: [:acc :n | acc + n]
      Result := sum
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 15)

  test "do: iteration":
    let results = interp.evalStatements("""
      | sum |
      sum := 0.
      #(1 2 3) do: [:n | sum := sum + n].
      Result := sum
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 6)

  test "detect: find first matching":
    let results = interp.evalStatements("""
      numbers := #(1 2 3 4 5)
      three := numbers detect: [:n | n = 3]
      Result := three
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 3)

suite "Website Examples - features.md Class-Side Methods":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "class>> defines class-side method":
    let results = interp.evalStatements("""
      Person := Object derive: #(name age)
      Person >> initialize [ name := ""; age := 0 ]
      Person >> name: n aged: a [ name := n; age := a ]
      Person class >> newNamed: n aged: a [
        | p |
        p := self new.
        p name: n.
        p age: a.
        ^ p
      ]
      alice := Person newNamed: "Alice" aged: 30
      Result := alice age
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 30)

suite "Website Examples - features.md Dynamic Dispatch":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "perform: without arguments":
    let results = interp.evalStatements("""
      numbers := #(1 2 3)
      Result := numbers perform: #size
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 3)

  test "perform:with: with one argument":
    let results = interp.evalStatements("""
      numbers := #(10 20 30)
      Result := numbers perform: #at: with: 2
    """)
    check(results[1].len == 0)
    check(results[0][^1].intVal == 20)
