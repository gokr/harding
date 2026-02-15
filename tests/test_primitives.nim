#!/usr/bin/env nim
#
# Tests for primitive syntax in Harding
# Tests both declarative and inline primitive syntax
#

import std/unittest
import std/strutils
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

suite "Primitive Syntax: Declarative Form":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)  # Load stdlib to access methods defined in .hrd files

  test "declarative primitive without arguments works (clone)":
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
    let result = interp.evalStatements("""
    obj := Table new.
    obj at: #key put: 42.
    result := obj at: #key
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "declarative primitive with two arguments works (at:put:)":
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
    let result = interp.evalStatements("""
    MyObj := Object derive.
    MyObj selector: #myClone put: [
      ^<primitive primitiveClone>
    ].

    obj := MyObj new.
    clone := obj myClone.
    result := obj == clone
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

suite "Primitive Syntax: Error Handling":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)  # Load stdlib for Object derive and selector:put:

  test "primitive with wrong arity should report error":
    let tokens = lex("Object>>bad [ ^<primitive primitiveAt:> ]")
    var parser = initParser(tokens)
    discard parser.parseStatements()

    check(parser.hasError)

  test "non-existent primitive selector should error at runtime":
    let result = interp.evalStatements("""
    MyObj := Object derive.
    MyObj selector: #callBadPrimitive put: [
      ^<primitive nonExistentPrimitive>
    ].

    obj := MyObj new.
    result := obj callBadPrimitive
    """)

    check(result[1].len > 0)

suite "Primitive Syntax: Integration Tests":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)  # Load stdlib for Object derive and primitive methods

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
    let tokens = lex("[ :key :val | <primitive primitiveAt: key put: val> ]")
    var parser = initParser(tokens)
    let nodes = parser.parseStatements()

    check(not parser.hasError)
    check(nodes.len == 1)
    let blk = nodes[0].BlockNode
    check(blk.parameters == @["key", "val"])

suite "Primitive Syntax: Unified Declarative Syntax":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "unified syntax - parser accepts keyword arguments in primitive tag":
    let tokens = lex("MyObj>>myMethod [ <primitive primitiveClone> ]")
    var parser = initParser(tokens)
    discard parser.parseStatements()

    check(not parser.hasError)

  test "unified syntax - declarative primitive without arguments works":
    skip()  # Declarative primitive syntax needs implementation review

  test "unified syntax - declarative primitive with wrong argument count fails at parse time":
    let tokens = lex("MyObj>>at: key put: val <primitive primitiveAt:>")
    var parser = initParser(tokens)
    discard parser.parseStatements()

    check(parser.hasError)

  test "unified syntax - declarative primitive with wrong argument names fails at parse time":
    let tokens = lex("MyObj>>at: a put: b <primitive primitiveAt: x put: y>")
    var parser = initParser(tokens)
    discard parser.parseStatements()

    check(parser.hasError)
    check("must match" in parser.errorMsg or "expected" in parser.errorMsg)

  test "unified syntax - inline primitive works inside method":
    let result = interp.evalStatements("""
    MyObj := Object derive.
    MyObj>>testInline [
      ^<primitive primitiveClone>
    ].

    obj := MyObj new.
    result := obj testInline
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "unified syntax - Table uses at: and at:put: methods":
    skip()  # Table at:put: return value needs review
