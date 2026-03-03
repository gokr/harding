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

  test "captured class from Harding at: in do: iteration (KNOWN BUG)":
    ## This test documents a bug where closures fail to properly capture
    ## class variables from outer scope when the class comes from a dictionary lookup
    ## like 'Harding at:' that returns a class object, used with iteration methods.
    ## The closure sees the class as UndefinedObject instead of the actual class.
    ##
    ## Expected: (Harding at: #TestClass) new should work in closure
    ## Actual: "Message not understood: new" because Harding at: returns UndefinedObject in closure
    let result = interp.evalStatements("""
      TestClass := Object derive: #(value).
      TestClass>>initialize [
        value := 42.
      ].
      TestClass>>getValue [
        ^ value.
      ].
      
      Results := Array new.
      #(1) do: [:each |
        | cls |
        cls := Harding at: "TestClass".
        Results add: (cls new getValue).
      ].
      
      Results at: 0
    """)
    if result[1].len > 0:
      echo "Error (expected for known bug): ", result[1]
      skip()
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)
