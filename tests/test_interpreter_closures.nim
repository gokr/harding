#!/usr/bin/env nim
#
# Lexical closure tests for Harding interpreter
# Tests block evaluation and closures
#

import std/[unittest, tables, strutils, logging]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

suite "Interpreter: Block Evaluation":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    initProcessorGlobal(interp)
    loadStdlib(interp)

  test "blocks can be stored and evaluated later":
    let result = interp.evalStatements("""
    MyClass := Object derive.
    MyClass selector: #block put: [ ^42 ].
    Obj := MyClass new.
    Result := Obj block
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "blocks with parameters capture arguments":
    # Simplified test - just check if block value: works
    let result = interp.evalStatements("""
      Doubler := [ :x | x * 2 ].
      Result := Doubler value: 21
      """)

    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "blocks can close over variables":
    let result = interp.evalStatements("""
      Counter := Object derive.
      Counter selector: #makeCounter put: [ | count |
        count := 0.
        ^[
          count := count + 1.
          ^count
        ]
      ].

      Counter2 := Counter new.
      C := Counter2 makeCounter.
      Result1 := C value.
      Result2 := C value.
      Result3 := C value
      """)

    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

suite "Interpreter: Lexical Closures":
  var interp: Interpreter

  setup:
    configureLogging(lvlWarn)
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    initProcessorGlobal(interp)
    loadStdlib(interp)

  test "closures capture and isolate variables":
    let result = interp.evalStatements("""
      Maker := Object derive.
      Maker >> makeCounter [ | count |
        count := 0.
        ^[ count := count + 1. ^count ]
      ].

      Maker2 := Maker new.
      Counter1 := Maker2 makeCounter.
      Counter2 := Maker2 makeCounter.

      Result1 := Counter1 value.
      Result2 := Counter1 value.
      Result3 := Counter2 value
    """)

    if result[1].len > 0:
      echo "Closure capture error: ", result[1]
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].intVal == 1)

  test "multiple closures share same captured variable":
    let result = interp.evalStatements("""
      Maker := Object derive.
      Maker >> makePair [ | value incBlock decBlock getBlock arr |
        value := 10.
        incBlock := [ value := value + 1. ^value ].
        decBlock := [ value := value - 1. ^value ].
        getBlock := [ ^value ].
        arr := Array new.
        arr add: getBlock.
        arr add: incBlock.
        arr add: decBlock.
        ^arr
      ].

      Maker2 := Maker new.
      Pair := Maker2 makePair.
      Result1 := (Pair at: 0) value.
      Dummy1 := (Pair at: 1) value.
      Result2 := (Pair at: 0) value.
      Dummy2 := (Pair at: 2) value.
      Result3 := (Pair at: 0) value
    """)

    if result[1].len > 0:
      echo "Shared capture error: ", result[1]
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].intVal == 10)

  test "closures capture different variables from same scope":
    let result = interp.evalStatements("""
      Maker := Object derive.
      Maker >> makeSum: x and: y [ ^[ ^x + y ] ].
      Maker >> makeDiff: x and: y [ ^[ ^x - y ] ].
      Maker >> makeProduct: x and: y [ ^[ ^x * y ] ].

      Maker2 := Maker new.
      SumBlock := Maker2 makeSum: 10 and: 20.
      DiffBlock := Maker2 makeDiff: 10 and: 20.
      ProductBlock := Maker2 makeProduct: 10 and: 20.
      Result1 := SumBlock value.
      Result2 := DiffBlock value.
      Result3 := ProductBlock value
    """)

    if result[1].len > 0:
      echo "Multi-variable capture error: ", result[1]
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].intVal == 200)

  test "nested closures capture multiple levels":
    let result = interp.evalStatements("""
    Maker := Object derive.
    Maker selector: #makeAdder: put: [ :x |
      ^[ :y |
        ^[ :z |
          ^x + y + z
        ]
      ]
    ].

    Maker2 := Maker new.
    Add5 := Maker2 makeAdder: 5.
    Add5and10 := Add5 value: 10.
    Result := Add5and10 value: 15
    """)

    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].intVal == 30)

  test "closures as object methods capture instance variables":
    skip()  # Complex closure behavior needs review

  test "closures outlive their defining scope":
    let result = interp.evalStatements("""
      Factory := Object derive.
      Factory >> create: base [ | multiplier |
        multiplier := base * 2.
        ^[ :val | ^val * multiplier ]
      ].

      Factory2 := Factory new.
      Doubler := Factory2 create: 1.
      Tripler := Factory2 create: 2.

      Result1 := Doubler value: 10.
      Result2 := Tripler value: 10
    """)

    if result[1].len > 0:
      echo "Closure outlive scope error: ", result[1]
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].intVal == 40)

  test "closure with non-local return from captured scope":
    let result = interp.evalStatements("""
      Finder := Object derive.
      Finder >> search: arr [ | elem1 elem2 elem3 |
        elem1 := arr at: 0.
        elem2 := arr at: 1.
        elem3 := arr at: 2.
        elem1 = 2 ifTrue: [ ^elem1 ].
        elem2 = 2 ifTrue: [ ^elem2 ].
        elem3 = 2 ifTrue: [ ^elem3 ].
        ^0
      ].

      Finder2 := Finder new.
      Numbers := #(1 2 3).
      Result := Finder2 search: Numbers
    """)

    if result[1].len > 0:
      echo "Non-local return error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].intVal == 2)
