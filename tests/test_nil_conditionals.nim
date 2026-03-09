#!/usr/bin/env nim
#
# Tests for nil handling with isNil/notNil
# This tests the fix for the bug where notNil was returning true
# when the receiver was nil (because slots contain nilInstance, not vkNil)
#

import std/[unittest, tables, strutils]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

suite "Nil isNil/notNil":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "nil isNil returns true":
    let result = interp.evalStatements("""
    Result := nil isNil
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "nil notNil returns false":
    let result = interp.evalStatements("""
    Result := nil notNil
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "object isNil returns false":
    let result = interp.evalStatements("""
    Obj := Object new.
    Result := Obj isNil
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "object notNil returns true":
    let result = interp.evalStatements("""
    Obj := Object new.
    Result := Obj notNil
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "slot with nil value - notNil returns false":
    let result = interp.evalStatements("""
    TestClass := Object derivePublic: #(slotValue).
    
    Obj := TestClass new.
    Result := Obj::slotValue notNil
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "slot with object value - notNil returns true":
    let result = interp.evalStatements("""
    TestClass := Object derivePublic: #(slotValue).
    
    Obj := TestClass new.
    Obj::slotValue := "something".
    Result := Obj::slotValue notNil
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "slot with nil - isNil returns true":
    let result = interp.evalStatements("""
    TestClass := Object derivePublic: #(slotValue).
    
    Obj := TestClass new.
    Result := Obj::slotValue isNil
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)
