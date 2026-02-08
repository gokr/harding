#
# test_perform.nim - Tests for dynamic message sending (perform:)
#

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/[vm, objects]

var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
loadStdlib(sharedInterp)

suite "Dynamic Message Sending":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "perform: sends message dynamically with unary selector":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass >> greet [ ^"hello" ].
      obj := MyClass new.
      Result := obj perform: #greet
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "perform: with keyword selector (perform:with:)":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass >> greet: name [ ^"hello " , name ].
      obj := MyClass new.
      Result := obj perform: #greet: with: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello world")

  test "perform:with:with: sends two-argument message":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass >> add: a to: b [ ^a + b ].
      obj := MyClass new.
      Result := obj perform: #add:to: with: 3 with: 4
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 7)

  test "perform: with computed selector":
    let result = interp.evalStatements("""
      MyClass := Object derive.
      MyClass >> methodA [ ^"A" ].
      MyClass >> methodB [ ^"B" ].
      obj := MyClass new.
      selector := #methodB.
      Result := obj perform: selector
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "B")

  test "perform: returns nil on non-existent selector (KNOWN BEHAVIOR)":
    # Note: Currently perform: returns nil for non-existent selectors
    # rather than raising an error. This may change in the future.
    let result = interp.evalStatements("""
      MyClass := Object derive.
      Obj := MyClass new.
      Result := Obj perform: #nonExistentMethod
    """)
    # Currently returns nil instead of error
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)
    check(result[0][^1].toString() == "nil")

  test "perform: inherits from parent class":
    let result = interp.evalStatements("""
      Parent := Object derive.
      Parent >> parentMethod [ ^"from parent" ].
      Child := Parent derive.
      obj := Child new.
      Result := obj perform: #parentMethod
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "from parent")
