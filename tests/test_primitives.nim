#!/usr/bin/env nim
#
# Tests for primitive syntax in Nimtalk
# Tests both declarative and inline primitive syntax
#

import std/[unittest, strutils]
import ../src/nimtalk/core/types
import ../src/nimtalk/parser/[lexer, parser]
import ../src/nimtalk/interpreter/[evaluator, objects]

suite "Primitive Syntax: Declarative Form":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "declarative primitive without arguments works (clone)":
    # Test: instance clone using primitive
    let result = interp.evalStatements("""
    obj := Table new.
    clone := obj clone.
    clone at: #key put: 42.
    result := clone at: #key
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "declarative primitive with one argument works (at:)":
    # Test: at: primitive
    let result = interp.evalStatements("""
    obj := Table new.
    obj at: #key put: 42.
    result := obj at: #key
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "declarative primitive with two arguments works (at:put:)":
    # Test: at:put: primitive
    let result = interp.evalStatements("""
    obj := Table new.
    obj at: "test" put: 99.
    result := obj at: "test"
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

  test "multiple primitives on same class work":
    let result = interp.evalStatements("""
    obj := Table new.
    obj at: #a put: 1.
    obj at: #b put: 2.
    obj at: #c put: 3.
    result1 := obj at: #a.
    result2 := obj at: #b.
    result3 := obj at: #c
    """)

    check(result[1].len == 0)
    check(result[0][^3].intVal == 1)
    check(result[0][^2].intVal == 2)
    check(result[0][^1].intVal == 3)

  test "primitive method can be called on instances":
    let result = interp.evalStatements("""
    # Create instance and use primitive methods
    obj := Table new.
    obj at: #value put: 123.
    result := obj at: #value
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 123)

  test "clone primitive creates independent instance":
    let result = interp.evalStatements("""
    obj1 := Table new.
    obj1 at: #x put: 10.
    obj2 := obj1 clone.
    obj2 at: #x put: 20.
    result1 := obj1 at: #x.
    result2 := obj2 at: #x
    """)

    check(result[1].len == 0)
    check(result[0][^2].intVal == 10)
    check(result[0][^1].intVal == 20)

suite "Primitive Syntax: Inline Form":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "inline primitive clone":
    # Test: method with <primitive primitiveClone> inside (unary selector)
    let result = interp.evalStatements("""
    MyObj := Object derive.
    MyObj selector: #myClone put: [
      ^<primitive primitiveClone>
    ].

    obj := MyObj new.
    clone := obj myClone.
    result := obj == clone
    """)

    # Cloned objects are not identity-equal
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

suite "Primitive Syntax: Error Handling":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "primitive with wrong arity should report error":
    let tokens = lex("Object>>bad [ ^<primitive primitiveAt:> ]")
    var parser = initParser(tokens)
    let nodes = parser.parseStatements()

    # Should have a parse error due to missing argument after keyword
    check(parser.hasError)

  test "non-existent primitive selector should error at runtime":
    let result = interp.evalStatements("""
    MyObj := Table derive.
    MyObj selector: #callBadPrimitive put: [
      ^<primitive nonExistentPrimitive>
    ].

    obj := MyObj new.
    result := obj callBadPrimitive
    """)

    # Should have an error message
    check(result[1].len > 0)

suite "Primitive Syntax: Integration Tests":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "primitive works with cascades":
    let result = interp.evalStatements("""
    obj := Table new.
    obj at: #a put: 1; at: #b put: 2; at: #c put: 3.
    result1 := obj at: #a.
    result2 := obj at: #b.
    result3 := obj at: #c
    """)

    check(result[1].len == 0)
    check(result[0][^3].intVal == 1)
    check(result[0][^2].intVal == 2)
    check(result[0][^1].intVal == 3)

  test "inline primitive with keyword message syntax parses correctly":
    # Test that the keyword message syntax parses correctly
    let tokens = lex("[ :key :val | <primitive primitiveAt: key put: val> ]")
    var parser = initParser(tokens)
    let nodes = parser.parseStatements()

    check(not parser.hasError)
    check(nodes.len == 1)
    # Verify the block parsed correctly
    let blk = nodes[0].BlockNode
    check(blk.parameters == @["key", "val"])
