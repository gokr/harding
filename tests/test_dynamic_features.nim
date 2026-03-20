#
# test_dynamic_features.nim - Tests for dynamic features including perform: and reflection
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm

var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
loadStdlib(sharedInterp)


suite "Dynamic Message Sending (perform:)":
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
    let result = interp.evalStatements("""
      MyClass := Object derive.
      Obj := MyClass new.
      Result := Obj perform: #nonExistentMethod
    """)
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


suite "Reflection: respondsTo:":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Integer responds to #+":
    let (result, err) = interp.doit("42 respondsTo: #+")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "String responds to #size":
    let (result, err) = interp.doit("\"hello\" respondsTo: #size")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "respondsTo: returns false for unknown selector":
    let (result, err) = interp.doit("42 respondsTo: #unknownMethodXYZ")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "respondsTo: detects custom method":
    let results = interp.evalStatements("""
      Greeter := Object derive: #()
      Greeter >> hello [ ^ "hi" ]
      g := Greeter new
      Result := g respondsTo: #hello
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "Array responds to #do:":
    let (result, err) = interp.doit("#(1 2 3) respondsTo: #do:")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)


suite "Reflection: isKindOf:":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "integer isKindOf: Integer":
    let (result, err) = interp.doit("42 isKindOf: Integer")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "string isKindOf: String":
    let (result, err) = interp.doit("\"hello\" isKindOf: String")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "instance isKindOf: its own class":
    let results = interp.evalStatements("""
      Dog := Object derive: #(name)
      d := Dog new
      Result := d isKindOf: Dog
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "integer isKindOf: unrelated class returns false":
    let (result, err) = interp.doit("42 isKindOf: String")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)


suite "Reflection: slotNames":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "slotNames returns array of correct size":
    let results = interp.evalStatements("""
      Dog := Object derive: #(name breed age)
      Result := Dog slotNames size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 3)

  test "slotNames contains correct names":
    let results = interp.evalStatements("""
      Cat := Object derive: #(name color)
      names := Cat slotNames
      Result := names size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 2)

  test "slotAt: returns slot value":
    let results = interp.evalStatements("""
      Person := Object derive: #(name age)
      p := Person new
      p slotAt: #name put: "Alice"
      Result := p slotAt: #name
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkString)
    check(results[0][^1].strVal == "Alice")

  test "slotAt:put: sets slot value":
    let results = interp.evalStatements("""
      Person := Object derive: #(name age)
      p := Person new
      p slotAt: #age put: 30
      Result := p slotAt: #age
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 30)


suite "Reflection: hasProperty: and properties":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "hasProperty: returns true for existing slot":
    let results = interp.evalStatements("""
      Animal := Object derive: #(name)
      a := Animal new
      Result := a hasProperty: #name
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "hasProperty: returns false for absent slot":
    let results = interp.evalStatements("""
      Animal := Object derive: #(name)
      a := Animal new
      Result := a hasProperty: #age
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == false)

  test "properties returns correct size":
    let results = interp.evalStatements("""
      Vehicle := Object derive: #(make model year)
      v := Vehicle new
      Result := v properties size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal == 3)


suite "Reflection: class and class name":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "42 class returns a class value":
    let (result, err) = interp.doit("42 class")
    check(err.len == 0)
    check(result.kind == vkClass)

  test "42 class name returns Integer":
    let (result, err) = interp.doit("42 class name")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Integer")

  test "custom class has correct name":
    let results = interp.evalStatements("""
      MySpecialClass := Object derive: #()
      inst := MySpecialClass new
      Result := inst class name
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkString)
    check(results[0][^1].strVal == "MySpecialClass")


suite "Reflection: allInstanceMethods":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "allInstanceMethods returns an array":
    let results = interp.evalStatements("""
      Result := Integer allInstanceMethods
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInstance)
    check(results[0][^1].instVal.kind == ikArray)

  test "allInstanceMethods array is non-empty":
    let results = interp.evalStatements("""
      methods := Integer allInstanceMethods
      Result := methods size
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkInt)
    check(results[0][^1].intVal > 0)

  test "custom method appears in allInstanceMethods":
    let results = interp.evalStatements("""
      Widget := Object derive: #()
      Widget >> render [ ^ "widget" ]
      methods := Widget allInstanceMethods
      found := false.
      methods do: [:m |
        m = #render ifTrue: [ found := true ]
      ].
      Result := found
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)
