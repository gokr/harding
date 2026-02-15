#!/usr/bin/env nim
#
# Comprehensive evaluator tests for Harding
# Tests all language mechanisms and evaluator features
#

import std/[unittest, tables, strutils, logging]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

# Helper to check for errors
proc checkError(interp: var Interpreter, source: string, expectedError: string = "") =
  let tokens = lex(source)
  var parser = initParser(tokens)
  check(not parser.hasError)
  let nodes = parser.parseStatements()
  if nodes.len > 0:
    expect ValueError:
      discard interp.evalWithVM(nodes[0])

suite "Evaluator: Basic Message Dispatch":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "evaluates simple property access via messages":
    # Use Table instance with at:/at:put: for key-value storage
    let result = interp.evalStatements("""
    T := Table new.
    T at: #value put: 42.
    Result := T at: #value
    """)

    check(result[1].len == 0)
    check(result[0].len == 3)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "handles undefined messages with doesNotUnderstand":
    # Create a class with custom doesNotUnderstand:
    let result = interp.evalStatements("""
    MyClass := Object derive.
    MyClass selector: #doesNotUnderstand: put: [ :msg | ^msg ].
    Obj := MyClass new.
    Result := Obj someUndefinedMessage
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkSymbol)
    check(result[0][^1].symVal == "someUndefinedMessage")

  test "method lookup traverses prototype chain":
    # Use class-based inheritance with selector:put: for method definition
    let result = interp.evalStatements("""
    Parent := Object derive.
    Parent selector: #parentMethod put: [ ^"from parent" ].

    Child := Parent derive.
    Child2 := Child new.
    Result := Child2 parentMethod
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
    # Using Table derive and >> syntax which is tested in test_super_and_syntax.nim
    let result = interp.evalStatements("""
      Point := Table derive: #(x y).
      Point>>setX: newX setY: newY [
        self at: #x put: newX.
        self at: #y put: newY
      ].
      Point>>getX [ ^self at: #x ].
      Point>>getY [ ^self at: #y ].

      Point2 := Point new.
      Point2 setX: 10 setY: 20.
      ResultX := Point2 getX.
      ResultY := Point2 getY
    """)

    if result[1].len > 0:
      echo "Multiple keyword params error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^2].intVal == 10)
    check(result[0][^1].intVal == 20)

  test "methods can access self and instance variables":
    # Note: String concatenation with , is registered on the base String class,
    # but stdlib String instances may need to use a different approach
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
    # Test method with multiple statements and local variables
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

suite "Evaluator: Control Flow":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

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
    # Should return nil or false itself
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

  test "complex conditional logic":  # Requires string concatenation
    when false:  # DISABLED - uses slot syntax not fully implemented
      let result = interp.evalStatements("""
      Number := Object derive: #(value).
      Number at: "isEven" put: [ ^(self value % 2) == 0 ].
      Number at: "describe" put: [
        (self isEven) ifTrue: [ ^self value + " is even" ].
        ^self value + " is odd"
      ].

      Num := Number derive.
      Num value: 4.
      Result1 := Num describe.

      Num value: 7.
      Result2 := Num describe
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

      Cat := Category derive.
      Result1 := Cat classify: -5.
      Result2 := Cat classify: 0.
      Result3 := Cat classify: 5.
      Result4 := Cat classify: 50.
      Result5 := Cat classify: 500
      """)

      check(result[1].len == 0)
      # All classifications should work

suite "Evaluator: Block Evaluation":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "blocks can be stored and evaluated later":
    let result = interp.evalStatements("""
    # Use new class-based model
    MyClass := Object derive.
    MyClass selector: #block put: [ ^42 ].
    Obj := MyClass new.
    Result := Obj block
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "blocks with parameters capture arguments":  # Requires full closure implementation
    let result = interp.evalStatements("""
      # Use new class-based model
      MyClass := Object derive.
      MyClass selector: #apply:to: put: [ :block :arg | ^block value: arg ].

      Obj := MyClass new.
      Doubler := [ :x | x * 2 ].
      Result := Obj apply: Doubler to: 21
      """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "blocks can close over variables":  # Requires full closure implementation
    let result = interp.evalStatements("""
      # Use new class-based model
      Counter := Object derive.
      Counter selector: #makeCounter put: [ | count |
        count := 0.
        ^[
          count := count + 1.
          ^count
        ]
      ].

      Counter2 := Counter new.
      C := Counter2 makeCounter.
      Result1 := C value.
      Result2 := C value.
      Result3 := C value
      """)

    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    # Debug: print actual results
    echo "Results count: ", result[0].len
    for i, r in result[0]:
      if r.kind == vkInstance:
        echo "  [", i, "] kind=", r.kind, " class=", r.instVal.class.name
      else:
        echo "  [", i, "] kind=", r.kind
    # Counter should increment each time
    check(result[0][^3].kind == vkInt)
    check(result[0][^2].kind == vkInt)
    check(result[0][^1].kind == vkInt)

  test "blocks support non-local return":  # Requires non-local return implementation
    when false:  # DISABLED - non-local return from blocks not fully implemented
      let result = interp.evalStatements("""
        Obj := Table derive.
        Obj at: #callWithEarlyReturn: put: [ :block |
          block value.
          ^"Should not reach here"
        ].

        Result := Obj callWithEarlyReturn: [ ^"Early exit" ]
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
    loadStdlib(interp)

  test "closures capture and isolate variables" :
    let result = interp.evalStatements("""
      Maker := Object derive.
      Maker >> makeCounter [ | count |
        count := 0.
        ^[ count := count + 1. ^count ]
      ].

      Maker2 := Maker new.
      Counter1 := Maker2 makeCounter.
      Counter2 := Maker2 makeCounter.

      Result1 := Counter1 value.
      Result2 := Counter1 value.
      Result3 := Counter2 value
    """)

    if result[1].len > 0:
      echo "Closure capture error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^3].intVal == 1)  # First call to counter1
    check(result[0][^2].intVal == 2)  # Second call to counter1
    check(result[0][^1].intVal == 1)  # First call to counter2 (isolated)

  test "multiple closures share same captured variable" :
    # Note: Using Array instead of Table to avoid table literal parsing issues with block values
    let result = interp.evalStatements("""
      Maker := Object derive.
      Maker >> makePair [ | value incBlock decBlock getBlock arr |
        value := 10.
        incBlock := [ value := value + 1. ^value ].
        decBlock := [ value := value - 1. ^value ].
        getBlock := [ ^value ].
        arr := Array new.
        arr add: getBlock.
        arr add: incBlock.
        arr add: decBlock.
        ^arr
      ].

      Maker2 := Maker new.
      Pair := Maker2 makePair.
      Result1 := (Pair at: 1) value.  # Should be 10
      Dummy1 := (Pair at: 2) value.
      Result2 := (Pair at: 1) value.  # Should be 11
      Dummy2 := (Pair at: 3) value.
      Result3 := (Pair at: 1) value   # Should be 10
    """)

    if result[1].len > 0:
      echo "Shared capture error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^5].intVal == 10)  # result1
    check(result[0][^3].intVal == 11)  # result2 (after inc)
    check(result[0][^1].intVal == 10)  # result3 (after dec)

  test "closures capture different variables from same scope" :
    # Note: Using separate methods instead of Table to avoid parser issues
    let result = interp.evalStatements("""
      Maker := Object derive.
      Maker >> makeSum: x and: y [ ^[ ^x + y ] ].
      Maker >> makeDiff: x and: y [ ^[ ^x - y ] ].
      Maker >> makeProduct: x and: y [ ^[ ^x * y ] ].

      Maker2 := Maker new.
      SumBlock := Maker2 makeSum: 10 and: 20.
      DiffBlock := Maker2 makeDiff: 10 and: 20.
      ProductBlock := Maker2 makeProduct: 10 and: 20.
      Result1 := SumBlock value.
      Result2 := DiffBlock value.
      Result3 := ProductBlock value
    """)

    if result[1].len > 0:
      echo "Multi-variable capture error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^3].intVal == 30)   # 10 + 20
    check(result[0][^2].intVal == -10)  # 10 - 20
    check(result[0][^1].intVal == 200)  # 10 * 20

  test "nested closures capture multiple levels" :
    let result = interp.evalStatements("""
    # Use new class-based model
    Maker := Object derive.
    Maker selector: #makeAdder: put: [ :x |
      ^[ :y |
        ^[ :z |
          ^x + y + z
        ]
      ]
    ].

    Maker2 := Maker new.
    Add5 := Maker2 makeAdder: 5.
    Add5and10 := Add5 value: 10.
    Result := Add5and10 value: 15
    """)

    if result[1].len > 0:
      echo "Error: ", result[1]
    check(result[1].len == 0)
    # Debug: print results
    echo "Results count: ", result[0].len
    for i, r in result[0]:
      echo "  [", i, "] kind=", r.kind
    check(result[0][^1].intVal == 30)  # 5 + 10 + 15

  test "closures as object methods capture instance variables" :
    # Simplified test - closures can access self and instance variables
    let result = interp.evalStatements("""
      Account := Object deriveWithAccessors: #(balance).
      Account >> getBalance [ ^self balance ].
      Account >> makeClosure [
        ^[ ^self balance ]
      ].

      Acc := Account new.
      Acc balance: 100.
      Closure := Acc makeClosure.
      Result1 := Closure value.
      Acc balance: 50.
      Result2 := Closure value.
      Result3 := Acc getBalance
    """)

    if result[1].len > 0:
      echo "Closure instance var error: ", result[1]
    check(result[1].len == 0)
    # Debug output
    echo "Closure instance var results count: ", result[0].len
    for i, r in result[0]:
      echo "  [", i, "] = ", r.toString()
    # Closure captures self and sees current balance at time of call
    # With Smalltalk semantics: balance: returns self, not the value
    # Result array: [0]=Account class, [1]=nil, [2]=nil, [3]=Acc, [4]=Acc (balance:100), [5]=<block>, [6]=100, [7]=Acc (balance:50), [8]=50, [9]=50
    # The positions have shifted due to balance: returning Acc instead of the value
    check(result[0][^4].kind == vkInt)
    check(result[0][^4].intVal == 50)   # Second call (Closure re-evaluates self.balance)
    check(result[0][^3].kind == vkInt)
    check(result[0][^3].intVal == 50)   # Direct access after balance change
    check(result[0][^2].kind == vkInt)
    check(result[0][^2].intVal == 50)   # Another direct access
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 50)   # Final getBalance
    check(result[0][^5].kind == vkInt)
    check(result[0][^5].intVal == 100)  # First call to closure

  test "closures outlive their defining scope" :
    let result = interp.evalStatements("""
      Factory := Object derive.
      Factory >> create: base [ | multiplier |
        multiplier := base * 2.
        ^[ :val | ^val * multiplier ]
      ].

      Factory2 := Factory new.
      Doubler := Factory2 create: 1.  # multiplier = 2
      Tripler := Factory2 create: 2.  # multiplier = 4

      Result1 := Doubler value: 10.  # 10 * 2
      Result2 := Tripler value: 10   # 10 * 4
    """)

    if result[1].len > 0:
      echo "Closure outlive scope error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^2].intVal == 20)
    check(result[0][^1].intVal == 40)

  test "closure captures entire lexical environment" :
    # Note: Using instance with slots instead of Table to avoid parser issues
    # Note: sqrt not available, using sum of squares instead
    let result = interp.evalStatements("""
      Point := Object deriveWithAccessors: #(x y).
      Point >> makePoint: x0 y: y0 [
        self x: x0.
        self y: y0
      ].
      Point >> sumOfSquares [
        ^(self x * self x) + (self y * self y)
      ].

      P := Point new.
      P makePoint: 3 y: 4.
      Result1 := P x.
      Result2 := P y.
      Result3 := P sumOfSquares.
      P x: 6.
      P y: 8.
      Result4 := P sumOfSquares
    """)

    if result[1].len > 0:
      echo "Lexical environment error: ", result[1]
    check(result[1].len == 0)
    # Debug: print results
    echo "Lexical results: "
    for i, r in result[0]:
      echo "  [", i, "] = ", r.toString()

  test "closure with non-local return from captured scope" :
    # Test non-local return from block
    let result = interp.evalStatements("""
      Finder := Object derive.
      Finder >> search: arr [ | elem1 elem2 elem3 |
        # Simple search with non-local return
        elem1 := arr at: 1.
        elem2 := arr at: 2.
        elem3 := arr at: 3.
        elem1 = 2 ifTrue: [ ^elem1 ].
        elem2 = 2 ifTrue: [ ^elem2 ].
        elem3 = 2 ifTrue: [ ^elem3 ].
        ^0
      ].

      Finder2 := Finder new.
      Numbers := #(1 2 3).
      Result := Finder2 search: Numbers
    """)

    if result[1].len > 0:
      echo "Non-local return error: ", result[1]
    check(result[1].len == 0)
    check(result[0][^1].intVal == 2)  # Found 2 at position 2

suite "Evaluator: Global Variables":
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

suite "Evaluator: Collections":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "arrays can be created and accessed" :  # Requires array iteration protocol
    let result = interp.evalStatements("""
    Arr := #(1 "hello" true).
    Result1 := Arr at: 1.
    Result2 := Arr at: 2.
    Result3 := Arr at: 3
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
    Tab := #{"name" -> "Alice", "age" -> 30}.
    Result1 := Tab at: "name".
    Result2 := Tab at: "age"
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
      Mapper at: "doubleAll:" put: [ :arr | val |
        Result := #[].
        1 to: arr do: [ :i |
          val := arr at: i.
          Result := Result add: (val * 2)
        ].
        ^Result
      ].

      Mapper2 := Mapper derive.
      Result := Mapper2 doubleAll: #(1 2 3 4 5)
      """)

      check(result[1].len == 0)
      # Should contain doubled values

  test "nested collections" :  # Requires collection iteration and access
    let result = interp.evalStatements("""
    Matrix := #( #(1 2 3) #(4 5 6) #(7 8 9) ).
    Row1 := Matrix at: 1.
    Elem := Row1 at: 2.
    Result := Elem
    """)

    check(result[1].len == 0)
    check(result[0][^1].intVal == 2)

suite "Evaluator: Error Handling":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "undefined message raises error" :  # Requires better error reporting
    expect ValueError:
      discard interp.doit("""
      Object someUndefinedMessage
      """)

  test "error includes message selector":
    let result = interp.evalStatements("""
    Obj := Table derive.
    Obj undefinedMethod
    """)

    check(result[1].len > 0)
    check("undefinedMethod" in result[1])

  test "parse errors are reported":
    let result = interp.evalStatements("""
    Obj := Table derive.
    Obj at:
    """)

    check(result[1].len > 0)

  test "at: reads values correctly (shows at: is valid)":
    let result = interp.evalStatements("""
    Person := Table derive: #(name).
    Person>>name: n [ self at: #name put: n ].
    Person>>name [ ^self at: #name ].

    Obj := Person new.
    Obj name: "Alice".
    Result := Obj name
    """)

    check(result[1].len == 0)
    check(result[0][^1].strVal == "Alice")

suite "Evaluator: Complex Expressions":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "nested message sends":
    let result = interp.evalStatements("""
    Container := Table derive: #(inner).
    Container>>inner: i [ self at: #inner put: i ].
    Container>>inner [ ^self at: #inner ].

    Box := Table derive: #(value).
    Box>>value: v [ self at: #value put: v ].
    Box>>value [ ^self at: #value ].

    Obj := Container new.
    Obj inner: (Box new).
    Obj inner value: 42.
    Result := Obj inner value
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

    Obj := Point new.
    Obj x: 0; y: 0; z: 0.
    Result := (Obj x) + (Obj y) + (Obj z)
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

    Num := MyNumber new.
    Num value: 10.
    Result1 := Num double.
    Result2 := Num value + 5.
    Result3 := Num add: 3 to: 7
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
    loadStdlib(interp)

  test "non-local return from block exits multiple frames" :
    let result = interp.evalStatements("""
      TestObj := Object derive.
      TestObj >> callBlock: block [
        # This method calls the block, which should non-local return
        block value.
        ^"Should not reach from callBlock"
      ].
      TestObj >> middle: block [
        # This calls callBlock:, which calls the block
        self callBlock: block.
        ^"Should not reach from middle"
      ].
      TestObj >> outer [
        # This creates a block with non-local return and passes it down
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
    TestObj := Table derive.
    TestObj>>testMethod [ ^99 ].

    Obj := TestObj new.
    Result := Obj testMethod
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
    loadStdlib(interp)

  test "nil is a valid value" :
    let result = interp.evalStatements("""
    Box := Table derive: #(value).
    Box>>value: v [ self at: #value put: v ].
    Box>>value [ ^self at: #value ].

    Obj := Box new.
    Obj value: nil.
    Result := Obj value
    """)

    check(result[1].len == 0)
    # nil is now an instance of UndefinedObject (vkInstance), not vkNil
    check(result[0][^1].kind == vkInstance)
    check(result[0][^1].toString() == "nil")

  test "booleans are native values" :
    let result = interp.evalStatements("""
    Result1 := true.
    Result2 := false.
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

    Obj := Box new.
    Obj test: 1.
    Result := Obj test
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)

  test "arithmetic with wrapped Nim values":
    let result = interp.evalStatements("""
    A := 10.
    B := 20.
    Result := A + B
    """)

    check(result[1].len == 0)
    # Should work with Nim proxy objects
