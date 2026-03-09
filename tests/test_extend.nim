#
# test_extend.nim - Tests for method batching (extend:, extendClass:)
#

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
loadStdlib(sharedInterp)

suite "Method Batching (extend:":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "extend: adds multiple methods to a class":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass extend: [
        self >> method1 [ ^1 ].
        self >> method2 [ ^2 ]
      ].
      obj := MyClass new.
      Result1 := obj method1.
      Result2 := obj method2
    """)
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "extendClass: adds class methods":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass extendClass: [
        self >> classMethod1 [ ^"class" ]
      ].
      Result := MyClass classMethod1
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "class")

  test "extend: methods are immediately available":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass extend: [
        self >> greet [ ^"hello" ]
      ].
      obj := MyClass new.
      Result := obj greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "multiple extend: calls work":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass extend: [
        self >> methodA [ ^"A" ]
      ].
      MyClass extend: [
        self >> methodB [ ^"B" ]
      ].
      obj := MyClass new.
      Result1 := obj methodA.
      Result2 := obj methodB
    """)
    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].strVal == "B")

  test "extend: can reference self":
    let result = interp.evalStatements("""
      SelfTestClass := Object derive.
      SelfTestClass extend: [
        self >> whoami [ ^self class name ]
      ].
      obj := SelfTestClass new.
      Result := obj whoami
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "SelfTestClass")

  test "extend: works with accessors":
    let result = interp.evalStatements("""
      MyClass := Object derivePublic: #(value).
      MyClass extend: [
        self >> doubled [ ^value * 2 ]
      ].
      obj := MyClass new.
      obj::value := 21.
      Result := obj doubled
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)
