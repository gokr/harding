#!/usr/bin/env nim
#
# Control flow tests for Harding interpreter
# Tests conditionals, loops, and times repeat
#

import std/[unittest, tables, strutils]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

suite "Interpreter: Conditionals":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "ifTrue: executes block when receiver is true":
    let result = interp.evalStatements("""
    Result := true ifTrue: [ 42 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "ifTrue: does not execute block when receiver is false":
    let result = interp.evalStatements("""
    Result := false ifTrue: [ 42 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkNil or result[0][^1].kind == vkInstance)

  test "ifFalse: executes block when receiver is false":
    let result = interp.evalStatements("""
    Result := false ifFalse: [ 99 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

  test "ifFalse: does not execute block when receiver is true":
    let result = interp.evalStatements("""
    Result := true ifFalse: [ 99 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkNil or result[0][^1].kind == vkInstance)

  test "ifTrue:ifFalse: handles both branches":
    let result = interp.evalStatements("""
    Result1 := true ifTrue: [ 1 ] ifFalse: [ 0 ].
    Result2 := false ifTrue: [ 1 ] ifFalse: [ 0 ]
    """)

    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].intVal == 0)

suite "Interpreter: Loops":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "whileTrue: executes while condition is true":
    let result = interp.evalStatements("""
    Counter := Object deriveWithAccessors: #(count).
    Counter >> increment [ self count: (self count + 1) ].

    C := Counter new.
    C count: 0.
    [ C count < 5 ] whileTrue: [ C increment ].
    Result := C count
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 5)

  test "whileFalse: executes while condition is false":
    let result = interp.evalStatements("""
    Counter := Object deriveWithAccessors: #(value).
    Counter >> increment [ self value: (self value + 1) ].

    C := Counter new.
    C value: 0.
    [ C value >= 5 ] whileFalse: [ C increment ].
    Result := C value
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 5)

  test "timesRepeat: executes n times":
    let result = interp.evalStatements("""
    Counter := Object deriveWithAccessors: #(count).
    Counter >> increment [ self count: (self count + 1) ].

    C := Counter new.
    C count: 0.
    5 timesRepeat: [ C increment ].
    Result := C count
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 5)
