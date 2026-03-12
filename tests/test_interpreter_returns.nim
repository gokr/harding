#!/usr/bin/env nim
#
# Return value and call stack tests for Harding interpreter
# Tests non-local returns and call stack behavior
#

import std/[unittest, tables, strutils]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

suite "Interpreter: Non-Local Returns":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "non-local return from block exits multiple frames":
    let result = interp.evalStatements("""
      TestObj := Object derive.
      TestObj >> callBlock: block [
        block value.
        ^"Should not reach from callBlock"
      ].
      TestObj >> middle: block [
        self callBlock: block.
        ^"Should not reach from middle"
      ].
      TestObj >> outer [
        self middle: [ ^"Returned from block" ].
        ^"Should not reach from outer"
      ].

      Obj := TestObj new.
      Result := Obj outer
    """)

    if result[1].len > 0:
      echo "Non-local return frames error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Returned from block")

  test "normal return returns from current method":
    let result = interp.evalStatements("""
    TestObj := Object derive.
    TestObj>>testMethod [ ^99 ].

    Obj := TestObj new.
    Result := Obj testMethod
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

  test "early return with ^ works in conditionals":
    let result = interp.evalStatements("""
      TestObj := Object derive.
      TestObj>>testMethod [
        true ifTrue: [ ^7 ].
        ^9
      ].

      Obj := TestObj new.
      Result := Obj testMethod
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 7)

  test "non-local return through Set iteration exits method":
    let result = interp.evalStatements("""
      TestObj := Object derive.
      TestObj>>firstGreaterThanTwo [
        | s |
        s := Set new.
        s add: 1.
        s add: 3.
        s add: 5.
        s do: [:each |
          each > 2 ifTrue: [ ^each ]
        ].
        ^nil
      ].

      Obj := TestObj new.
      Result := Obj firstGreaterThanTwo
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal > 2)

  test "non-local return through Array iteration exits method":
    let result = interp.evalStatements("""
      TestObj := Object derive.
      TestObj>>firstGreaterThanTwo [
        | arr |
        arr := #(1 3 5).
        arr do: [:each |
          each > 2 ifTrue: [ ^each ]
        ].
        ^nil
      ].

      Obj := TestObj new.
      Result := Obj firstGreaterThanTwo
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "non-local return through whileTrue exits method":
    let result = interp.evalStatements("""
      TestObj := Object derivePublic: #(count).
      TestObj>>run [
        count := 0.
        [ count < 5 ] whileTrue: [
          count := count + 1.
          count = 3 ifTrue: [ ^count ]
        ].
        ^nil
      ].

      Obj := TestObj new.
      Result := Obj run
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "implicit return of self when no explicit return":
    let result = interp.evalStatements("""
    Builder := Object derivePublic: #(value).
    Builder >> setValue: v [
      value := v
    ].

    B := Builder new.
    Result := B setValue: 42
    """)

    if result[1].len > 0:
      echo "Implicit return error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)
