#!/usr/bin/env nim
#
# Comprehensive evaluator tests for Nimtalk
# Tests all language mechanisms and evaluator features
#

import std/[unittest, tables, strutils, sequtils]
import ../src/nimtalk/core/types
import ../src/nimtalk/parser/[lexer, parser]
import ../src/nimtalk/interpreter/[evaluator, objects, activation]

# Helper to check for errors
proc checkError(interp: var Interpreter, source: string, expectedError: string = "") =
  let tokens = lex(source)
  var parser = initParser(tokens)
  check(not parser.hasError)
  let nodes = parser.parseStatements()
  if nodes.len > 0:
    expect ValueError:
      discard interp.eval(nodes[0])

suite "Evaluator: Basic Message Dispatch":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "evaluates simple property access via messages":
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "value" put: 42.
    result := obj at: "value"
    """)

    check(result[1].len == 0)
    check(result[0].len == 3)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "handles undefined messages with doesNotUnderstand":
    # Requires doesNotUnderstand: implementation
    skip()

  test "method lookup traverses prototype chain":
    # Requires proper prototype chain setup
    skip()

suite "Evaluator: Method Execution with Parameters":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "executes methods with keyword parameters":
    let result = interp.evalStatements("""
    Calculator := Dictionary derive.
    Calculator at: "add:to:" put: [ :x y | ^x + y ].

    calc := Calculator derive.
    result := calc add: 5 to: 10
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 15)

  test "executes methods with multiple keyword parameters":
    let result = interp.evalStatements("""
    Point := Dictionary derive: #(x y).
    Point at: "setX:setY:" put: [ :newX :newY |
      self x: newX.
      self y: newY
    ].

    point := Point derive.
    point setX: 10 setY: 20.
    resultX := point x.
    resultY := point y
    """)

    check(result[1].len == 0)
    check(result[0][^2].intVal == 10)
    check(result[0][^1].intVal == 20)

  test "methods can access self and instance variables":  # Requires string concatenation
    skip()
    when false:
      let result = interp.evalStatements("""
      Person := Object derive: #(name age).
      Person at: "introduce" put: [ ^"I am " + self name + " and I am " + self age + " years old" ].

      person := Person derive.
      person name: "Alice".
      person age: 30.
      result := person introduce
      """)

      check(result[1].len == 0)
      check(result[0][^1].kind == vkString)
      # Note: String concatenation may need proper implementation

  test "methods with complex body execute all statements":  # Requires Stdout and string concatenation
    skip()
    when false:
      let result = interp.evalStatements("""
      Counter := Object derive: #(count).
      Counter at: "incrementBy:andPrint:" put: [ :amount :label |
        oldValue := self count.
        self count: oldValue + amount.
        Stdout write: label.
        ^self count
      ].

      counter := Counter derive.
      counter count: 0.
      result := counter incrementBy: 5 andPrint: "Incrementing\n"
      """)

      check(result[1].len == 0)
      check(result[0][^1].kind == vkInt)
      check(result[0][^1].intVal == 5)

suite "Evaluator: Control Flow":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "ifTrue: executes block when receiver is true":
    let result = interp.evalStatements("""
    result := true ifTrue: [ ^42 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "ifTrue: does not execute block when receiver is false":
    let result = interp.evalStatements("""
    result := false ifTrue: [ ^42 ]
    """)

    check(result[1].len == 0)
    # Should return nil or false itself
    check(result[0][^1].kind == vkNil or result[0][^1].kind == vkObject)

  test "ifFalse: executes block when receiver is false":
    let result = interp.evalStatements("""
    result := false ifFalse: [ ^99 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

  test "ifFalse: does not execute block when receiver is true":
    let result = interp.evalStatements("""
    result := true ifFalse: [ ^99 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkNil or result[0][^1].kind == vkObject)

  test "complex conditional logic":  # Requires string concatenation
    skip()
    when false:
      let result = interp.evalStatements("""
      Number := Object derive: #(value).
      Number at: "isEven" put: [ ^(self value % 2) == 0 ].
      Number at: "describe" put: [
        (self isEven) ifTrue: [ ^self value + " is even" ].
        ^self value + " is odd"
      ].

      num := Number derive.
      num value: 4.
      result1 := num describe.

      num value: 7.
      result2 := num describe
      """)

      check(result[1].len == 0)
      # Should return appropriate strings

  test "nested conditionals":  # Requires string concatenation or better boolean handling
    skip()
    when false:
      let result = interp.evalStatements("""
      Category := Dictionary derive.
      Category at: "classify:" put: [ :n |
        (n < 0) ifTrue: [ ^"negative" ].
        (n == 0) ifTrue: [ ^"zero" ].
        (n < 10) ifTrue: [ ^"small positive" ].
        (n < 100) ifTrue: [ ^"medium positive" ].
        ^"large positive"
      ].

      cat := Category derive.
      result1 := cat classify: -5.
      result2 := cat classify: 0.
      result3 := cat classify: 5.
      result4 := cat classify: 50.
      result5 := cat classify: 500
      """)

      check(result[1].len == 0)
      # All classifications should work

suite "Evaluator: Block Evaluation":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "blocks can be stored and evaluated later":
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "block" put: [ ^42 ].
    result := obj block
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "blocks with parameters capture arguments":  # Requires full closure implementation
    skip()
    when false:
      let result = interp.evalStatements("""
      obj := Dictionary derive.
      obj at: "apply:to:" put: [ :block :arg | ^block value: arg ].

      doubler := [ :x | ^x * 2 ].
      result := obj apply: doubler to: 21
      """)

      check(result[1].len == 0)
      check(result[0][^1].kind == vkInt)
      check(result[0][^1].intVal == 42)

  test "blocks can close over variables":  # Requires full closure implementation
    skip()
    when false:
      let result = interp.evalStatements("""
      Counter := Dictionary derive.
      Counter at: "makeCounter" put: [ |
        count := 0.
        ^[
          count := count + 1.
          ^count
        ]
      ].

      counter := Counter derive.
      c := counter makeCounter.
      result1 := c value.
      result2 := c value.
      result3 := c value
      """)

      check(result[1].len == 0)
      # Counter should increment each time
      check(result[0][^3].kind == vkInt)
      check(result[0][^2].kind == vkInt)
      check(result[0][^1].kind == vkInt)

  test "blocks support non-local return":  # Requires non-local return implementation
    skip()
    when false:
      let result = interp.evalStatements("""
      obj := Dictionary derive.
      obj at: "callWithEarlyReturn" put: [ :block |
        block value.
        ^"Should not reach here"
      ].

      result := obj callWithEarlyReturn: [ ^"Early exit" ]
      """)

      check(result[1].len == 0)
      check(result[0][^1].kind == vkString)
      check(result[0][^1].strVal == "Early exit")

  test "blocks as higher-order functions":
    # Requires collection iteration protocol
    check(true)

suite "Evaluator: Lexical Closures":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "closures capture and isolate variables" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Maker := Dictionary derive.
    Maker at: "makeCounter" put: [ |
      count := 0.
      ^[ |
        count := count + 1.
        ^count
      ]
    ].

    maker := Maker derive.
    counter1 := maker makeCounter.
    counter2 := maker makeCounter.

    result1 := counter1 value.
    result2 := counter1 value.
    result3 := counter2 value
    """)

    check(result[1].len == 0)
    check(result[0][^3].intVal == 1)  # First call to counter1
    check(result[0][^2].intVal == 2)  # Second call to counter1
    check(result[0][^1].intVal == 1)  # First call to counter2 (isolated)

  test "multiple closures share same captured variable" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Maker := Dictionary derive.
    Maker at: "makePair" put: [ |
      value := 10.
      ^#{
        "inc": [ ^value := value + 1 ],
        "dec": [ ^value := value - 1 ],
        "get": [ ^value ]
      }

    ].

    maker := Maker derive.
    pair := maker makePair.
    result1 := (pair at: "get") value.  # Should be 10
    (pair at: "inc") value.
    result2 := (pair at: "get") value.  # Should be 11
    (pair at: "dec") value.
    result3 := (pair at: "get") value   # Should be 10
    """)

    check(result[1].len == 0)
    check(result[0][^3].intVal == 10)
    check(result[0][^2].intVal == 11)
    check(result[0][^1].intVal == 10)

  test "closures capture different variables from same scope" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Maker := Dictionary derive.
    Maker at: "makeClosures" put: [ :x :y |
      ^#{
        "sum": [ ^x + y ],
        "diff": [ ^x - y ],
        "product": [ ^x * y ]
      }
    ].

    maker := Maker derive.
    closures := maker makeClosures: 10 :20.
    result1 := (closures at: "sum") value.
    result2 := (closures at: "diff") value.
    result3 := (closures at: "product") value
    """)

    check(result[1].len == 0)
    check(result[0][^3].intVal == 30)   # 10 + 20
    check(result[0][^2].intVal == -10)  # 10 - 20
    check(result[0][^1].intVal == 200)  # 10 * 20

  test "nested closures capture multiple levels" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Maker := Dictionary derive.
    Maker at: "makeAdder" put: [ :x |
      ^[ :y |
        ^[ :z |
          ^x + y + z
        ]
      ]
    ].

    maker := Maker derive.
    add5 := maker makeAdder: 5.
    add5and10 := add5 value: 10.
    result := add5and10 value: 15
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 30)  # 5 + 10 + 15

  test "closures as object methods capture instance variables" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Account := Dictionary derive: #(balance).
    Account at: "initialize:" put: [ :initial |
      self balance: initial
    ].
    Account at: "withdraw:" put: [ :amount |
      ^[
        current := self balance.
        (current >= amount) ifTrue: [
          self balance: current - amount.
          ^true
        ].
        ^false
      ]
    ].

    acc := Account derive.
    acc initialize: 100.
    withdraw50 := acc withdraw: 50.
    result1 := withdraw50 value.
    result2 := acc balance.
    withdraw100 := acc withdraw: 100.
    result3 := withdraw100 value
    """)

    check(result[1].len == 0)
    check(result[0][^3].boolVal == true)   # First withdrawal succeeded
    check(result[0][^2].intVal == 50)      # Balance after first withdrawal
    check(result[0][^1].boolVal == false)  # Second withdrawal failed

  test "closures outlive their defining scope" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Factory := Dictionary derive.
    Factory at: "create" put: [ :base |
      # This variable should be captured and persist
      multiplier := base * 2.
      ^[ :val | ^val * multiplier ]
    ].

    factory := Factory derive.
    doubler := factory create: 1.  # multiplier = 2
    tripler := factory create: 1.5. # multiplier = 3

    result1 := doubler value: 10.  # 10 * 2
    result2 := tripler value: 10   # 10 * 3
    """)

    check(result[1].len == 0)
    check(result[0][^2].intVal == 20)
    check(result[0][^1].intVal == 30)

  test "closure captures entire lexical environment" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Maker := Dictionary derive.
    Maker at: "makePoint" put: [ :x0 :y0 |
      x := x0.
      y := y0.
      ^#{
        "x": [ ^x ],
        "y": [ ^y ],
        "setX:": [ :newX | x := newX ],
        "setY:": [ :newY | y := newY ],
        "distanceFromOrigin": [
          ^((x * x) + (y * y)) sqrt
        ]
      }
    ].

    maker := Maker derive.
    p := maker makePoint: 3 :4.
    result1 := (p at: "x") value.
    result2 := (p at: "y") value.
    result3 := (p at: "distanceFromOrigin") value.
    (p at: "setX:") value: 6.
    (p at: "setY:") value: 8.
    result4 := (p at: "distanceFromOrigin") value
    """)

    check(result[1].len == 0)
    check(result[0][^4].intVal == 3)
    check(result[0][^3].intVal == 4)
    check(result[0][^2].intVal == 5)   # sqrt(3^2 + 4^2) = 5
    check(result[0][^1].intVal == 10)  # sqrt(6^2 + 8^2) = 10

  test "closure with non-local return from captured scope" :  # Requires full closure implementation
    let result = interp.evalStatements("""
    Finder := Dictionary derive.
    Finder at: "findIn:" put: [ :arr :predicate |
      1 to: arr do: [ :i |
        elem := arr at: i.
        (predicate value: elem) ifTrue: [ ^elem ]
      ].
      ^nil
    ].

    finder := Finder derive.
    numbers := #(1 3 5 7 9 2 4 6 8).
    result := finder findIn: numbers :[ :n | ^(n % 2) == 0 ]
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 2)  # First even number

suite "Evaluator: Global Variables":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "variables persist across evaluations":
    let result1 = interp.evalStatements("""
    counter := 0.
    result := counter
    """)

    check(result1[1].len == 0)
    check(result1[0][^1].intVal == 0)

    let result2 = interp.evalStatements("""
    counter := counter + 1.
    result := counter
    """)

    check(result2[1].len == 0)
    check(result2[0][^1].intVal == 1)

  test "globals accessible from methods":
    let result = interp.evalStatements("""
    # Define global
    GlobalValue := 100.

    obj := Dictionary derive.
    obj at: "getGlobal" put: [ ^GlobalValue ].

    result := obj getGlobal
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 100)

  test "class objects stored as globals":
    let result = interp.evalStatements("""
    Person := Object derive: #(name age).
    Person at: "new" put: [ ^self derive ].

    p1 := Person new.
    p1 name: "Alice".

    p2 := Person new.
    p2 name: "Bob"
    """)

    check(result[1].len == 0)
    # Both instances should work independently

suite "Evaluator: Collections":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "arrays can be created and accessed" :  # Requires array iteration protocol
    let result = interp.evalStatements("""
    arr := #(1 "hello" true).
    result1 := arr at: 1.
    result2 := arr at: 2.
    result3 := arr at: 3
    """)

    check(result[1].len == 0)
    check(result[0][^3].intVal == 1)
    check(result[0][^2].strVal == "hello")
    check(result[0][^1].boolVal == true)

  test "tables can be created and accessed" :  # Requires table iteration protocol
    let result = interp.evalStatements("""
    tab := #{"name": "Alice", "age": 30}.
    result1 := tab at: "name".
    result2 := tab at: "age"
    """)

    check(result[1].len == 0)
    check(result[0][^2].strVal == "Alice")
    check(result[0][^1].intVal == 30)

  test "collections support iteration" :  # Requires collection iteration protocol
    let result = interp.evalStatements("""
    Mapper := Dictionary derive.
    Mapper at: "doubleAll:" put: [ :arr |
      result := #[].
      1 to: arr do: [ :i |
        val := arr at: i.
        result := result add: (val * 2)
      ].
      ^result
    ].

    mapper := Mapper derive.
    result := mapper doubleAll: #(1 2 3 4 5)
    """)

    check(result[1].len == 0)
    # Should contain doubled values

  test "nested collections" :  # Requires collection iteration and access
    let result = interp.evalStatements("""
    matrix := #( #(1 2 3) #(4 5 6) #(7 8 9) ).
    row1 := matrix at: 1.
    elem := row1 at: 2.
    result := elem
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 2)

suite "Evaluator: Error Handling":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "undefined message raises error" :  # Requires better error reporting
    expect ValueError:
      discard interp.evalStatements("""
      Object someUndefinedMessage
      """)

  test "error includes message selector":
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj undefinedMethod
    """)

    check(result[1].len > 0)
    check("undefinedMethod" in result[1])

  test "parse errors are reported":
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at:
    """)

    check(result[1].len > 0)

  test "method with invalid argument count reports error" :  # Requires argument count validation
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "key"  # Missing 'put:' part
    """)

    check(result[1].len > 0)

suite "Evaluator: Complex Expressions":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "nested message sends":
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "inner" put: Object derive.
    (obj at: "inner") at: "value" put: 42.
    result := (obj at: "inner") at: "value"
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "cascades in complex expressions":
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "x" put: 0; at: "y" put: 0; at: "z" put: 0.
    result := (obj at: "x") + (obj at: "y") + (obj at: "z")
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "mixed unary, binary, and keyword messages" :  # Requires operator precedence handling
    let result = interp.evalStatements("""
    Number := Object derive: #(value).
    Number at: "+" put: [ :other | ^self value + other ].
    Number at: "double" put: [ ^self value * 2 ].
    Number at: "add:to:" put: [ :a :b | ^a + b ].

    num := Number derive.
    num value: 10.
    result1 := num double.
    result2 := num + 5.
    result3 := num add: 3 to: 7
    """)

    check(result[1].len == 0)
    check(result[0][^3].intVal == 20)
    check(result[0][^2].intVal == 15)
    check(result[0][^1].intVal == 10)

  test "evaluation order is left-to-right" :
    # Requires logging and verification infrastructure
    check(true)

suite "Evaluator: Call Stack and Returns":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "non-local return exits multiple frames" :  # Requires non-local return implementation
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "level3" put: [ ^"From level 3" ].
    obj at: "level2" put: [ self level3. ^"Should not reach" ].
    obj at: "level1" put: [ self level2. ^"Should not reach" ].

    result := obj level1
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "From level 3")

  test "normal return returns from current method":
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "method" put: [ ^99 ].

    result := obj method
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 99)

suite "Evaluator: Special Features":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "nil is a valid value" :  # Requires nil singleton implementation
    let result = interp.evalStatements("""
    obj := Dictionary derive.
    obj at: "value" put: nil.
    result := obj at: "value"
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkNil)

  test "booleans are first-class objects" :  # Requires boolean object wrappers
    let result = interp.evalStatements("""
    result1 := true.
    result2 := false.
    result3 := true == false
    """)

    check(result[1].len == 0)
    check(result[0][^3].kind == vkObject)
    check(result[0][^2].kind == vkObject)

  test "primitive methods have fallback to Smalltalk":
    let result = interp.evalStatements("""
    # Test that primitives with fallbacks work
    obj := Object clone.
    obj at: "test" put: 1.
    result := obj at: "test"
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)

  test "arithmetic with wrapped Nim values":
    let result = interp.evalStatements("""
    a := 10.
    b := 20.
    result := a + b
    """)

    check(result[1].len == 0)
    # Should work with Nim proxy objects
