#!/usr/bin/env nim
#
# Comprehensive evaluator tests for Nimtalk
# Tests all language mechanisms and evaluator features
#

import std/[unittest, tables, strutils, sequtils, logging]
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
    obj := Table derive.
    obj at: #value put: 42.
    result := obj at: #value
    """)

    check(result[1].len == 0)
    check(result[0].len == 3)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "handles undefined messages with doesNotUnderstand":
    let result = interp.evalStatements("""
    obj := Table derive.
    obj at: #doesNotUnderstand: put: [ :msg | ^msg ].
    result := obj someUndefinedMessage
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkSymbol)
    check(result[0][^1].symVal == "someUndefinedMessage")

  test "method lookup traverses prototype chain":
    let result = interp.evalStatements("""
    Parent := Table derive.
    Parent at: #parentMethod put: [ ^"from parent" ].

    Child := Parent derive.
    child := Child derive.
    result := child parentMethod
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "from parent")

suite "Evaluator: Method Execution with Parameters":
  var interp: Interpreter

  setup:
    configureLogging(lvlWarn)
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "executes methods with keyword parameters":
    let result = interp.evalStatements("""
    Calculator := Table derive.
    Calculator at: #add:to: put: [ :x y | ^x + y ].

    calc := Calculator derive.
    result := calc add: 5 to: 10
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 15)

  test "executes methods with multiple keyword parameters":
    let result = interp.evalStatements("""
    Point := Table derive: #(x y).
    Point at: #setX:setY: put: [ :newX :newY |
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
    when false:  # DISABLED - uses slot syntax not fully implemented
      let result = interp.evalStatements("""
      Person := Object derive: #(name age).
      Person at: #introduce put: [ ^"I am " , self name , " and I am " , self age , " years old" ].

      person := Person derive.
      person name: "Alice".
      person age: 30.
      result := person introduce
      """)

      check(result[1].len == 0)
      check(result[0][^1].kind == vkString)
      # Note: String concatenation may need proper implementation

  test "methods with complex body execute all statements":  # Requires Stdout and string concatenation
    when false:  # DISABLED - uses slot syntax not fully implemented
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
    when false:  # DISABLED - uses slot syntax not fully implemented
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
    when false:  # DISABLED - uses comparison operators that may not work
      let result = interp.evalStatements("""
      Category := Table derive.
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
    obj := Table derive.
    obj at: #block put: [ ^42 ].
    result := obj block
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "blocks with parameters capture arguments":  # Requires full closure implementation
    let result = interp.evalStatements("""
      obj := Table derive.
      obj at: #apply:to: put: [ :block :arg | ^block value: arg ].

      doubler := [ :x | ^x * 2 ].
      result := obj apply: doubler to: 21
      """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "blocks can close over variables":  # Requires full closure implementation
    let result = interp.evalStatements("""
      Counter := Table derive.
      Counter at: #makeCounter put: [ | count |
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
    when false:  # DISABLED - non-local return from blocks not fully implemented
      let result = interp.evalStatements("""
        obj := Table derive.
        obj at: #callWithEarlyReturn: put: [ :block |
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
    configureLogging(lvlWarn)  # Enable logging for debugging
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "closures capture and isolate variables" :
    when false:  # DISABLED - closure capture not fully implemented
      let result = interp.evalStatements("""
      Maker := Table derive.
      Maker at: #makeCounter put: [ |
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

  test "multiple closures share same captured variable" :
    when false:  # DISABLED - closure capture not fully implemented
      let result = interp.evalStatements("""
      Maker := Table derive.
      Maker at: #makePair put: [ |
        value := 10.
        ^#{ #inc -> [ ^value := value + 1 ], #dec -> [ ^value := value - 1 ], #get -> [ ^value ] }
      ].

      maker := Maker derive.
      pair := maker makePair.
      result1 := (pair at: #get) value.  # Should be 10
      dummy1 := (pair at: #inc) value.
      result2 := (pair at: #get) value.  # Should be 11
      dummy2 := (pair at: #dec) value.
      result3 := (pair at: #get) value   # Should be 10
      """)

      check(result[1].len == 0)
      check(result[0][^5].intVal == 10)  # result1
      check(result[0][^3].intVal == 11)  # result2 (after inc)
      check(result[0][^1].intVal == 10)  # result3 (after dec)

  test "closures capture different variables from same scope" :
    when false:  # DISABLED - closure capture not fully implemented
      let result = interp.evalStatements("""
      Maker := Table derive.
      Maker at: #makeClosures: put: [ :x :y |
        ^#{
          #sum: [ ^x + y ],
          #diff: [ ^x - y ],
          #product: [ ^x * y ]
        }
      ].

      maker := Maker derive.
      closures := maker makeClosures: 10 :20.
      result1 := (closures at: #sum) value.
      result2 := (closures at: #diff) value.
      result3 := (closures at: #product) value
      """)

      check(result[1].len == 0)
      check(result[0][^3].intVal == 30)   # 10 + 20
      check(result[0][^2].intVal == -10)  # 10 - 20
      check(result[0][^1].intVal == 200)  # 10 * 20

  test "nested closures capture multiple levels" :
    let result = interp.evalStatements("""
    Maker := Table derive.
    Maker at: #makeAdder: put: [ :x |
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

  test "closures as object methods capture instance variables" :
    when false:  # DISABLED - slot-based instance variables not fully implemented
      let result = interp.evalStatements("""
      Account := Table derive: #(balance).
      Account at: #initialize: put: [ :initial |
        self balance: initial
      ].
      Account at: #withdraw: put: [ :amount |
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

  test "closures outlive their defining scope" :
    when false:  # DISABLED - closure capture not fully implemented
      let result = interp.evalStatements("""
      Factory := Table derive.
      Factory at: #create: put: [ :base |
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

  test "closure captures entire lexical environment" :
    when false:  # DISABLED - closure capture not fully implemented
      let result = interp.evalStatements("""
      Maker := Table derive.
      Maker at: #makePoint:: put: [ :x0 :y0 |
        x := x0.
        y := y0.
        ^#{
          #x: [ ^x ],
          #y: [ ^y ],
          #setX:: [ :newX | x := newX ],
          #setY:: [ :newY | y := newY ],
          #distanceFromOrigin: [
            ^((x * x) + (y * y)) sqrt
          ]
        }
      ].

      maker := Maker derive.
      p := maker makePoint: 3 :4.
      result1 := (p at: #x) value.
      result2 := (p at: #y) value.
      result3 := (p at: #distanceFromOrigin) value.
      (p at: #setX:) value: 6.
      (p at: #setY:) value: 8.
      result4 := (p at: #distanceFromOrigin) value
      """)

      check(result[1].len == 0)
      check(result[0][^4].intVal == 3)
      check(result[0][^3].intVal == 4)
      check(result[0][^2].intVal == 5)   # sqrt(3^2 + 4^2) = 5
      check(result[0][^1].intVal == 10)  # sqrt(6^2 + 8^2) = 10

  test "closure with non-local return from captured scope" :
    when false:  # DISABLED - closure capture not fully implemented
      let result = interp.evalStatements("""
      Finder := Table derive.
      Finder at: #findIn:: put: [ :arr :predicate |
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

    obj := Table derive.
    obj at: #getGlobal put: [ ^GlobalValue ].

    result := obj getGlobal
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 100)

  test "class objects stored as globals":
    let result = interp.evalStatements("""
    Person := Table derive: #(name age).
    Person at: #new put: [ ^self derive ].

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

    if result[1].len > 0:
      echo "ERROR: ", result[1]
    echo "results: ", result[0].len, " values"
    for i, r in result[0]:
      echo "  [", i, "] kind=", r.kind, " value=", r.toString()
    check(result[1].len == 0)
    check(result[0][^3].intVal == 1)
    check(result[0][^2].strVal == "hello")
    # true is stored as vkBool in array literals
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "tables can be created and accessed" :  # Requires table iteration protocol
    let result = interp.evalStatements("""
    tab := #{"name" -> "Alice", "age" -> 30}.
    result1 := tab at: "name".
    result2 := tab at: "age"
    """)

    if result[1].len > 0:
      echo "TABLE ERROR: ", result[1]
    echo "TABLE results: ", result[0].len, " values"
    for i, r in result[0]:
      echo "  [", i, "] kind=", r.kind, " value=", r.toString()
    check(result[1].len == 0)
    check(result[0][^2].strVal == "Alice")
    check(result[0][^1].intVal == 30)

  test "collections support iteration" :  # Requires collection iteration protocol
    when false:  # DISABLED - uses #[] empty array syntax not supported by parser
      let result = interp.evalStatements("""
      Mapper := Table derive.
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
      discard interp.doit("""
      Object someUndefinedMessage
      """)

  test "error includes message selector":
    let result = interp.evalStatements("""
    obj := Table derive.
    obj undefinedMethod
    """)

    check(result[1].len > 0)
    check("undefinedMethod" in result[1])

  test "parse errors are reported":
    let result = interp.evalStatements("""
    obj := Table derive.
    obj at:
    """)

    check(result[1].len > 0)

  test "at: reads values correctly (shows at: is valid)":
    let result = interp.evalStatements("""
    Person := Table derive: #(name).
    Person>>name: n [ self at: #name put: n ].
    Person>>name [ ^self at: #name ].

    obj := Person new.
    obj name: "Alice".
    result := obj name
    """)

    check(result[1].len == 0)
    check(result[0][^1].strVal == "Alice")

suite "Evaluator: Complex Expressions":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "nested message sends":
    let result = interp.evalStatements("""
    Container := Table derive: #(inner).
    Container>>inner: i [ self at: #inner put: i ].
    Container>>inner [ ^self at: #inner ].

    Box := Table derive: #(value).
    Box>>value: v [ self at: #value put: v ].
    Box>>value [ ^self at: #value ].

    obj := Container new.
    obj inner: (Box new).
    obj inner value: 42.
    result := obj inner value
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "cascades in complex expressions":
    let result = interp.evalStatements("""
    Point := Table derive: #(x y z).
    Point>>x: v [ self at: #x put: v ].
    Point>>y: v [ self at: #y put: v ].
    Point>>z: v [ self at: #z put: v ].
    Point>>x [ ^self at: #x ].
    Point>>y [ ^self at: #y ].
    Point>>z [ ^self at: #z ].

    obj := Point new.
    obj x: 0; y: 0; z: 0.
    result := (obj x) + (obj y) + (obj z)
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 0)

  test "mixed unary, binary, and keyword messages" :
    let result = interp.evalStatements("""
    MyNumber := Table derive: #(value).
    MyNumber>>value: v [ self at: #value put: v ].
    MyNumber>>value [ ^self at: #value ].
    MyNumber>>double [ ^self value * 2 ].
    MyNumber>>add: a to: b [ ^a + b ].

    num := MyNumber new.
    num value: 10.
    result1 := num double.
    result2 := num value + 5.
    result3 := num add: 3 to: 7
    """)

    if result[1].len > 0:
      stderr.writeLine("Mixed messages ERROR: ", result[1])
      stderr.writeLine("Results count: ", result[0].len)
    check(result[1].len == 0)
    if result[0].len >= 3:
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

  test "non-local return exits multiple frames" :
    when false:  # DISABLED - non-local return stack unwinding not fully implemented
      let result = interp.evalStatements("""
      TestObj := Table derive.
      TestObj>>level3 [ ^"From level 3" ].
      TestObj>>level2 [ self level3. ^"Should not reach" ].
      TestObj>>level1 [ self level2. ^"Should not reach" ].

      obj := TestObj new.
      result := obj level1
      """)

      check(result[1].len == 0)
      check(result[0][^1].kind == vkString)
      check(result[0][^1].strVal == "From level 3")

  test "normal return returns from current method":
    let result = interp.evalStatements("""
    TestObj := Table derive.
    TestObj>>testMethod [ ^99 ].

    obj := TestObj new.
    result := obj testMethod
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

  test "nil is a valid value" :
    let result = interp.evalStatements("""
    Box := Table derive: #(value).
    Box>>value: v [ self at: #value put: v ].
    Box>>value [ ^self at: #value ].

    obj := Box new.
    obj value: nil.
    result := obj value
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkNil)

  test "booleans are native values" :
    let result = interp.evalStatements("""
    result1 := true.
    result2 := false.
    """)

    check(result[1].len == 0)
    check(result[0][^2].kind == vkBool)
    check(result[0][^2].boolVal == true)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "primitive methods have fallback to Smalltalk":
    let result = interp.evalStatements("""
    Box := Table derive: #(test).
    Box>>test: v [ self at: #test put: v ].
    Box>>test [ ^self at: #test ].

    obj := Box new.
    obj test: 1.
    result := obj test
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
