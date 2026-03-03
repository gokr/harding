#!/usr/bin/env nim
#
# Tests for closure capture in IfNode/WhileNode control flow specializations.
# Verifies that blocks inside ifTrue:ifFalse: and whileTrue: properly capture
# outer lexical variables for use in nested closures.
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

suite "Closure Capture in IfNode/WhileNode":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    initProcessorGlobal(interp)
    loadStdlib(interp)

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
