#!/usr/bin/env nim
#
# Consolidated closure tests
# Merges: test_interpreter_closures, test_closure_capture
#

import std/[unittest, tables, strutils, logging]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ./stdlib_test_support

# Shared interpreter for all suites
var sharedInterp = newSharedStdlibInterpreter()

suite "Interpreter: Block Evaluation":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

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
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

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
    let code = """
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
Add5and10 value: 15
"""
    let (result, err) = interp.doit(code)

    if err.len > 0:
      echo "Error: ", err
    check(err.len == 0)
    check(result.intVal == 30)

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

suite "Closure Capture in Control Flow":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "captured variables survive IfNode blocks":
    let result = interp.evalStatements("""
      Tester := Object derive.
      Tester >> run [ | captured res |
        captured := 42.
        res := nil.
        true ifTrue: [
          | holder |
          holder := Array new.
          holder add: [res := captured].
          (holder at: 0) value.
        ].
        ^res
      ].
      Result := Tester new run
    """)
    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "captured variables in nested blocks inside ifTrue":
    let result = interp.evalStatements("""
      Tester := Object derive.
      Tester >> run [ | x callback |
        x := "hello".
        callback := nil.
        true ifTrue: [
          callback := [x].
        ].
        ^callback value
      ].
      Result := Tester new run
    """)
    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "captured variables in ifFalse branch":
    let result = interp.evalStatements("""
      Tester := Object derive.
      Tester >> run [ | x callback |
        x := 99.
        callback := nil.
        false ifTrue: [
          callback := [0].
        ] ifFalse: [
          callback := [x].
        ].
        ^callback value
      ].
      Result := Tester new run
    """)
    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

  test "captured variables in whileTrue nested blocks":
    let result = interp.evalStatements("""
      Tester := Object derive.
      Tester >> run [ | count callbacks |
        count := 0.
        callbacks := Array new.
        [count < 3] whileTrue: [
          | current |
          current := count.
          callbacks add: [current].
          count := count + 1.
        ].
        ^(callbacks at: 2) value
      ].
      Result := Tester new run
    """)
    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "captured class variable in do: iteration":
    ## Class variable capture works in do: blocks
    let result = interp.evalStatements("""
      TestClass := Object derive: #(value).
      TestClass>>initialize [
        value := 42.
      ].
      TestClass>>getValue [
        ^ value.
      ].
      
      CapturedClass := TestClass.
      Results := Array new.
      
      #(1) do: [:each |
        Results add: (CapturedClass new getValue).
      ].
      
      Results at: 0
    """)
    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)
