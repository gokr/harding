#!/usr/bin/env nim
#
# Tests for super keyword and >> method definition syntax
#

import std/[unittest, logging, strutils]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/vm

configureLogging(lvlError)

suite "Super Keyword Support":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "super calls parent method":
    let result = interp.evalStatements("""
    Parent := Object derive.
    Parent>>greet [ ^"Hello from parent" ].
    Child := Parent derive.
    Child>>greet [ ^super greet ].
    c := Child new.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello from parent")

  test "super works with >> syntax":
    let result = interp.evalStatements("""
    Parent := Object derive.
    Parent>>greet [ ^"Hello from parent" ].
    Child := Parent derive.
    Child>>greet [ ^super greet ].
    c := Child new.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello from parent")

  test "super chains through multiple levels":
    let result = interp.evalStatements("""
    GrandParent := Object derive.
    GrandParent>>greet [ ^"Hello from grandparent" ].
    Parent := GrandParent derive.
    Parent>>greet [ ^super greet ].
    Child := Parent derive.
    Child>>greet [ ^super greet ].
    c := Child new.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString().contains("grandparent"))

  test "unqualified super looks up in first parent":
    let code = "super greet"
    let (ast, _) = parseExpression(code)

    check(ast != nil)
    check(ast of SuperSendNode)
    let superNode = cast[SuperSendNode](ast)
    check(superNode.selector == "greet")
    check(superNode.explicitParent == "")
    check(superNode.arguments.len == 0)

  test "qualified super looks up in specific parent":
    let (node, _) = parseExpression("super<Parent> method")
    check(node.kind == nkSuperSend)
    let superNode = node.SuperSendNode
    check(superNode.selector == "method")
    check(superNode.explicitParent == "Parent")
    check(superNode.arguments.len == 0)

suite ">> Method Definition Syntax":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test ">> defines unary method":
    let result = interp.evalStatements("""
    Person := Object derive.
    Person>>greet [ ^"Hello, World!" ].
    p := Person new.
    p greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello, World!")

  test ">> defines keyword method with parameters":
    let result = interp.evalStatements("""
    Person := Object derive.
    Person>>name: aName [ ^aName ].
    p := Person new.
    p name: "Alice"
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Alice")

  test ">> defines multi-part keyword method":
    let result = interp.evalStatements("""
    Point := Object derive.
    Point>>moveX: x y: y [ ^x + y ].
    p := Point new.
    p moveX: 3 y: 4
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "7")

  test ">> method returns correct value":
    let result = interp.evalStatements("""
    Obj := Object derive.
    Obj>>getValue [ ^42 ].
    o := Obj new.
    o getValue
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "42")

  test ">> keyword arguments passed correctly":
    let result = interp.evalStatements("""
    Box := Object derive.
    Box>>store: x in: y [ ^y ].
    b := Box new.
    b store: 10 in: 5
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "5")

  test ">> keyword args with multiple parameters each":
    let result = interp.evalStatements("""
    Wrapper := Object derive.
    Wrapper>>combine: x and: y [ ^x ].
    w := Wrapper new.
    w combine: "first" and: "second"
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "first")

  test ">> mixed unary and keyword methods on same object":
    let result = interp.evalStatements("""
    Thing := Object derive.
    Thing>>id [ ^42 ].
    Thing>>label: text [ ^text ].
    t := Thing new.
    t label: "testitem"
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "testitem")

suite "Self Keyword Support":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "self refers to the receiver in methods":
    let result = interp.evalStatements("""
    Counter := Object derive.
    Counter>>getSelf [ self ].
    c := Counter new.
    c getSelf
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "self can access instance variables with accessors":
    let result = interp.evalStatements("""
    Person := Object derivePublic: #(name).
    Person>>setName: n [ name := n ].
    Person>>getName [ ^name ].
    p := Person new.
    p setName: "Alice".
    p getName
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Alice")

  test "self can send messages to itself":
    let result = interp.evalStatements("""
    Builder := Object derivePublic: #(prefix).
    Builder>>setPrefix: p [ prefix := p ].
    Builder>>build [ ^prefix ].
    b := Builder new.
    b setPrefix: "Hello".
    b build
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello")

  test "self works with >> syntax":
    let result = interp.evalStatements("""
    Box := Object derivePublic: #(item).
    Box>>store: x [ item := x ].
    Box>>retrieve [ ^item ].
    b := Box new.
    b store: "test".
    b retrieve
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "test")

  test "self call in inherited method starts lookup in receiver":
    let result = interp.evalStatements("""
    Parent := Object derive.
    Parent>>greet [ ^self greeting ].
    Parent>>greeting [ ^"Hello from Parent" ].
    Child := Parent derive.
    Child>>greeting [ ^"Hello from Child" ].
    c := Child new.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello from Child")
