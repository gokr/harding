#!/usr/bin/env nim
#
# Consolidated interpreter core tests
# Merges: test_interpreter_basic, test_interpreter_controlflow, test_interpreter_returns,
#         test_interpreter_errors, test_super_and_syntax
#

import std/[unittest, tables, strutils, logging]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]
import ./stdlib_test_support

# Shared interpreter for all suites
var sharedInterp = newSharedStdlibInterpreter()

# Helper to create fresh interpreter when needed (for error isolation)
proc newFreshInterp(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initSymbolTable()
  loadStdlib(result)

suite "Interpreter: Basic Message Dispatch":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

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
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

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
      Point := Object derivePublic: #(x y).
      Point>>setX: newX setY: newY [
        x := newX.
        y := newY
      ].
      Point>>getX [ ^x ].
      Point>>getY [ ^y ].

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

suite "Interpreter: Multiline Strings":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "evaluates triple-quoted multiline string literals as raw strings":
    let expected = """line 1
He said "hello"
"two quotes" are fine
backslash-n: \n
"""
    let code = "\"\"\"" & expected & "\"\"\""
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == expected)

  test "dedents indentation-aware triple-quoted strings":
    let code = "\"\"\"\n      alpha\n        beta\n      gamma\n    \"\"\""
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "alpha\n  beta\ngamma\n")

  test "evaluates triple-quoted symbol strings":
    let code = "#\"\"\"line 1\n  line 2 with \"quotes\"\n\"\"\""
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkSymbol)
    check(result.symVal == "line 1\n  line 2 with \"quotes\"\n")

suite "Interpreter: Process and Activation Introspection":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "exposes current process and scheduler":
    let (result, err) = interp.doit("""
      (Process current className) , "|" , (Scheduler current className) , "|" , (Processor current className)
    """)
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Process|Scheduler|Process")

  test "exposes current activation details":
    let (result, err) = interp.doit("""
      Probe := Object derive.
      Probe>>activationInfo [
        | act |
        act := Process current currentActivation.
        ^ (act className) , "|" , (act selector) , "|" , (act receiver className) , "|" , (act cacheKey)
      ].
      Probe new activationInfo
    """)
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal.contains("Activation|activationInfo|Probe|Probe>>activationInfo@"))

  test "object activation and thisContext are convenience aliases":
    let (result, err) = interp.doit("""
      Probe := Object derive.
      Probe>>activationAliases [
        ^ (self activation selector) , "|" , (self thisContext selector)
      ].
      Probe new activationAliases
    """)
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "activationAliases|activationAliases")

  test "htmlEscape escapes html-sensitive characters":
    let (result, err) = interp.doit("""
      "<tag attr=\"x\">& text" htmlEscape
    """)
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "&lt;tag attr=&quot;x&quot;&gt;&amp; text")

  test "methods can access self and slots":
    let result = interp.evalStatements("""
      Person := Object derivePublic: #(name age).
      Person >> getName [ ^name ].
      Person >> getAge [ ^age ].

      Alice := Person new.
      Alice::name := "Alice".
      Alice::age := 30.
      Name := Alice getName.
      Age := Alice getAge.
      Result := Name
    """)

    if result[1].len > 0:
      echo "Self/slot access error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Alice")

  test "methods with complex body execute all statements":
    let result = interp.evalStatements("""
      Counter := Object derivePublic: #(count).
      Counter >> add: amount [
        | oldValue newValue |
        oldValue := count.
        newValue := oldValue + amount.
        count := newValue.
        ^newValue
      ].

      Counter2 := Counter new.
      Counter2::count := 0.
      Result := Counter2 add: 5
    """)

    if result[1].len > 0:
      echo "Complex body error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

suite "Interpreter: Global Variables":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

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

suite "Interpreter: Conditionals":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "ifTrue: executes block when receiver is true":
    let result = interp.evalStatements("""
    Result := true ifTrue: [ 42 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "ifTrue: does not execute block when receiver is false":
    let result = interp.evalStatements("""
    Result := false ifTrue: [ 42 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkNil or result[0][^1].kind == vkInstance)

  test "ifFalse: executes block when receiver is false":
    let result = interp.evalStatements("""
    Result := false ifFalse: [ 99 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

  test "ifFalse: does not execute block when receiver is true":
    let result = interp.evalStatements("""
    Result := true ifFalse: [ 99 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkNil or result[0][^1].kind == vkInstance)

  test "ifTrue:ifFalse: handles both branches":
    let result = interp.evalStatements("""
    Result1 := true ifTrue: [ 1 ] ifFalse: [ 0 ].
    Result2 := false ifTrue: [ 1 ] ifFalse: [ 0 ]
    """)

    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].intVal == 0)

suite "Interpreter: Loops":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "whileTrue: executes while condition is true":
    let result = interp.evalStatements("""
    Counter := Object derivePublic: #(count).
    Counter >> increment [ count := (count + 1) ].

    C := Counter new.
    C::count := 0.
    [ C::count < 5 ] whileTrue: [ C increment ].
    Result := C::count
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 5)

  test "whileFalse: executes while condition is false":
    let result = interp.evalStatements("""
    Counter := Object derivePublic: #(value).
    Counter >> increment [ value := (value + 1) ].

    C := Counter new.
    C::value := 0.
    [ C::value >= 5 ] whileFalse: [ C increment ].
    Result := C::value
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 5)

  test "timesRepeat: executes n times":
    let result = interp.evalStatements("""
    Counter := Object derivePublic: #(count).
    Counter >> increment [ count := (count + 1) ].

    C := Counter new.
    C::count := 0.
    5 timesRepeat: [ C increment ].
    Result := C::count
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 5)

suite "Interpreter: Non-Local Returns":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

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

  test "method-owned nested block return exits the enclosing method":
    let result = interp.evalStatements("""
      Finder := Object derive.
      Finder>>firstPositive: arr [
        arr do: [:each |
          each > 0 ifTrue: [ ^each ]
        ].
        ^nil
      ].

      Result := Finder new firstPositive: #(-2 -1 7 9)
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 7)

  test "script-owned block return stays local to the block":
    let (resultValue, err) = sharedInterp.evalScriptBlock("[ blk := [ ^41 ]. blk value ]")
    check(err.len == 0)
    check(resultValue.kind == vkInt)
    check(resultValue.intVal == 41)

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

suite "Interpreter: Error Handling":
  test "undefined message raises error":
    expect ValueError:
      discard sharedInterp.doit("""
      Object someUndefinedMessage
      """)

  test "error includes message selector":
    let result = sharedInterp.evalStatements("""
    Obj := Object derive.
    Obj undefinedMethod
    """)

    check(result[1].len > 0)
    check("undefinedMethod" in result[1])

  test "parse errors are reported":
    let result = sharedInterp.evalStatements("""
    Obj := Object derive.
    Obj at:
    """)

    check(result[1].len > 0)

  test "message not understood on nil gives meaningful error":
    let result = sharedInterp.evalStatements("""
    nil someMessage
    """)

    check(result[1].len > 0)

  test "nested message send with undefined method":
    let result = sharedInterp.evalStatements("""
    Container := Object derivePublic: #(inner).
    C := Container new.
    C::inner := Object new.
    Result := C::inner undefinedMethod
    """)

    check(result[1].len > 0)
    check("undefinedMethod" in result[1])

  test "named access can be receiver and keyword argument":
    let result = sharedInterp.evalStatements("""
    Holder := Object derivePublic: #(server router).
    H := Holder new.
    H::server := #{}.
    H::router := 42.
    H::server at: "x" put: H::router.
    Result := H::server at: "x"
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "error in block evaluation is reported":
    let result = sharedInterp.evalStatements("""
    [ Object undefinedMethod ] value
    """)

    check(result[1].len > 0)

suite "Interpreter: Special Values":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "nil is a valid value":
    let result = interp.evalStatements("""
    Box := Object derivePublic: #(value).

    Obj := Box new.
    Obj::value := nil.
    Result := Obj::value
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)
    check(result[0][^1].toString() == "nil")

  test "booleans are native values":
    let result = interp.evalStatements("""
    Result1 := true.
    Result2 := false.
    """)

    check(result[1].len == 0)
    check(result[0].len == 1)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "arithmetic with wrapped Nim values":
    let result = interp.evalStatements("""
    A := 10.
    B := 20.
    Result := A + B
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 30)

suite "Super Keyword Support":
  var interp {.used.}: Interpreter

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
  var interp {.used.}: Interpreter

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
  var interp {.used.}: Interpreter

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
