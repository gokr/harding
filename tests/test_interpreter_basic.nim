#!/usr/bin/env nim
#
# Basic interpreter tests for Harding
# Tests message dispatch, method execution, and global variables
#

import std/[unittest, tables, strutils, logging]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

suite "Interpreter: Basic Message Dispatch":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "handles undefined messages with doesNotUnderstand":
    skip()  # doesNotUnderstand: mechanism needs review

  test "method lookup traverses prototype chain":
    let code = """
Parent := Object derive.
Parent selector: #parentMethod put: [ ^"from parent" ].

Child := Parent derive.
Child2 := Child new.
Child2 parentMethod
"""
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "from parent")

suite "Interpreter: Method Execution with Parameters":
  var interp: Interpreter

  setup:
    configureLogging(lvlWarn)
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "executes methods with keyword parameters":
    let result = interp.evalStatements("""
    Calculator := Object derive.
    Calculator selector: #add:to: put: [ :x :y | ^x + y ].

    Calc := Calculator new.
    Result := Calc add: 5 to: 10
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 15)

  test "executes methods with multiple keyword parameters":
    let result = interp.evalStatements("""
      Point := Object deriveWithAccessors: #(x y).
      Point>>setX: newX setY: newY [
        self x: newX.
        self y: newY
      ].
      Point>>getX [ ^self x ].
      Point>>getY [ ^self y ].

      Point2 := Point new.
      Point2 setX: 10 setY: 20.
      ResultX := Point2 getX.
      ResultY := Point2 getY
    """)

    if result[1].len > 0:
      echo "Multiple keyword params error: ", result[1]
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].intVal == 20)

  test "methods can access self and instance variables":
    let result = interp.evalStatements("""
      Person := Object deriveWithAccessors: #(name age).
      Person >> getName [ ^self name ].
      Person >> getAge [ ^self age ].

      Alice := Person new.
      Alice name: "Alice".
      Alice age: 30.
      Name := Alice getName.
      Age := Alice getAge.
      Result := Name
    """)

    if result[1].len > 0:
      echo "Self/ivar access error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Alice")

  test "methods with complex body execute all statements":
    let result = interp.evalStatements("""
      Counter := Object deriveWithAccessors: #(count).
      Counter >> add: amount [
        | oldValue newValue |
        oldValue := self count.
        newValue := oldValue + amount.
        self count: newValue.
        ^newValue
      ].

      Counter2 := Counter new.
      Counter2 count: 0.
      Result := Counter2 add: 5
    """)

    if result[1].len > 0:
      echo "Complex body error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

suite "Interpreter: Global Variables":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "variables persist across evaluations":
    let result1 = interp.evalStatements("""
    Counter := 0.
    Result := Counter
    """)

    check(result1[1].len == 0)
    check(result1[0][^1].intVal == 0)

    let result2 = interp.evalStatements("""
    Counter := Counter + 1.
    Result := Counter
    """)

    check(result2[1].len == 0)
    check(result2[0][^1].intVal == 1)

  test "globals accessible from methods":
    let result = interp.evalStatements("""
    # Define global
    GlobalValue := 100.

    # Use new class-based model: Object derive creates a class
    MyClass := Object derive.
    MyClass selector: #getGlobal put: [ ^GlobalValue ].

    Obj := MyClass new.
    Result := Obj getGlobal
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 100)
