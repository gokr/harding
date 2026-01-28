#!/usr/bin/env nim
#
# Tests for super keyword and >> method definition syntax
#

import std/[unittest, logging, strutils]
import ../src/nimtalk/core/types
import ../src/nimtalk/interpreter/evaluator

configureLogging(lvlError)

suite "Super Keyword Support":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "super calls parent method":
    let result = interp.evalStatements("""
    Parent := Dictionary derive.
    Parent at: "greet" put: [ "Hello from parent" ].
    Child := Parent derive.
    Child at: "greet" put: [ super greet ].
    c := Child derive.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello from parent")

  test "super works with >> syntax":
    let result = interp.evalStatements("""
    Parent := Dictionary derive.
    Parent>>greet [ "Hello from parent" ].
    Child := Parent derive.
    Child>>greet [ super greet ].
    c := Child derive.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello from parent")

  test "super chains through multiple levels":
    let result = interp.evalStatements("""
    GrandParent := Dictionary derive.
    GrandParent>>greet [ "Hello from grandparent" ].
    Parent := GrandParent derive.
    Parent>>greet [ super greet ].
    Child := Parent derive.
    Child>>greet [ super greet ].
    c := Child derive.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString().contains("grandparent"))

suite ">> Method Definition Syntax":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test ">> defines unary method":
    let result = interp.evalStatements("""
    Person := Dictionary derive.
    Person>>greet [ "Hello, World!" ].
    p := Person derive.
    p greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello, World!")

  test ">> defines keyword method with parameters":
    let result = interp.evalStatements("""
    Person := Dictionary derive.
    Person>>name: aName [ aName ].
    p := Person derive.
    p name: "Alice"
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Alice")

  test ">> defines multi-part keyword method":
    let result = interp.evalStatements("""
    Point := Dictionary derive.
    Point>>moveX: x y: y [ x + y ].
    p := Point derive.
    p moveX: 3 y: 4
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "7")

  test ">> method returns correct value":
    let result = interp.evalStatements("""
    Obj := Dictionary derive.
    Obj>>getValue [ 42 ].
    o := Obj derive.
    o getValue
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "42")

  test ">> keyword arguments passed correctly":
    let result = interp.evalStatements("""
    Box := Dictionary derive.
    Box>>store: x in: y [ y ].
    b := Box derive.
    b store: 10 in: 5
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "5")  # Should return second arg (y)

  test ">> keyword args with multiple parameters each":
    let result = interp.evalStatements("""
    Wrapper := Dictionary derive.
    Wrapper>>combine: x and: y [ x ].
    w := Wrapper derive.
    w combine: "first" and: "second"
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "first")

  test ">> mixed unary and keyword methods on same object":
    let result = interp.evalStatements("""
    Thing := Dictionary derive.
    Thing>>id [ 42 ].
    Thing>>label: text [ text ].
    t := Thing derive.
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
    Counter := Dictionary derive.
    Counter>>getSelf [ self ].
    c := Counter derive.
    c getSelf
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkObject)

  test "self can access instance variables":
    let result = interp.evalStatements("""
    Person := Dictionary derive.
    Person>>setName: n [ self at: "name" put: n ].
    Person>>getName [ self at: "name" ].
    p := Person derive.
    p setName: "Alice".
    p getName
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Alice")

  test "self can send messages to itself":
    let result = interp.evalStatements("""
    Builder := Dictionary derive.
    Builder>>setPrefix: p [ self at: "prefix" put: p ].
    Builder>>build [ self at: "prefix" ].
    b := Builder derive.
    b setPrefix: "Hello".
    b build
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello")

  test "self works with >> syntax":
    let result = interp.evalStatements("""
    Box := Dictionary derive.
    Box>>store: x [ self at: "item" put: x ].
    Box>>retrieve [ self at: "item" ].
    b := Box derive.
    b store: "test".
    b retrieve
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "test")

  test "self call in inherited method starts lookup in receiver":
    let result = interp.evalStatements("""
    Parent := Dictionary derive.
    Parent>>greet [ self greeting ].
    Parent>>greeting [ "Hello from Parent" ].
    Child := Parent derive.
    Child>>greeting [ "Hello from Child" ].
    c := Child derive.
    c greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].toString() == "Hello from Child")
