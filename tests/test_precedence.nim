## Test Smalltalk-style message precedence rules
## Precedence (highest to lowest):
## 1. Unary messages (identifier starting with lowercase)
## 2. Binary operators (+, -, *, /, <, >, =, etc.)
## 3. Keyword messages (ending with :)
## 4. Assignment (:=)
## For same precedence: left-to-right evaluation

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm

suite "Parser Precedence - Unary Messages":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "unary message binds tighter than binary":
    # "1 + 2 negated" should be "1 + (2 negated)" = "1 + -2" = -1
    let (result, err) = interp.doit("1 + 2 negated")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == -1)

  test "unary chain binds left to right":
    # "10 negated abs" should be "(10 negated) abs" = "-10 abs" = 10
    let (result, err) = interp.doit("10 negated abs")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 10)

  test "unary before keyword argument":
    # "arr at: 1 + 1" should be "arr at: (1 + 1)"
    let (result, err) = interp.doit("Arr := #(10, 20, 30). Arr at: 1 + 1")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 30)

  test "multiple unary messages left-to-right":
    let result = interp.evalStatements("""
    Chain := Object derive.
    Chain >> first [ ^self ].
    Chain >> second [ ^self ].
    Chain >> third [ ^42 ].

    C := Chain new.
    Result := C first second third
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 42)


suite "Parser Precedence - Binary Operators":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "binary operators left to right":
    # "10 - 5 - 2" should be "(10 - 5) - 2" = 3
    let (result, err) = interp.doit("10 - 5 - 2")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 3)

  test "binary before keyword":
    let (result, err) = interp.doit("Arr := #(10, 20, 30, 40, 50, 60, 70, 80, 90, 100). Arr at: 1 + 2")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 40)

  test "binary in keyword argument (concatenation operator)":
    let result = interp.evalStatements("""
    Arr := #(10, 20, 30, 40, 50, 60, 70, 80).
    Result := Arr at: 2 + 3
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 60)

  test "binary minus in keyword argument":
    let result = interp.evalStatements("""
    Arr := #(10, 20, 30, 40, 50, 60, 70, 80).
    Result := Arr at: 10 - 3
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 80)


suite "Message Precedence: Unary > Binary > Keyword":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "unary has higher precedence than binary":
    let result = interp.evalStatements("""
    TestObj := Object derive.
    TestObj >> value [ ^10 ].
    TestObj >> double [ ^self value * 2 ].

    Obj := TestObj new.
    Result := Obj double + 5
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 25)  # (10 * 2) + 5 = 25

  test "binary operators are left-to-right associative":
    let result = interp.evalStatements("""
    Result := 10 + 5 * 2
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 30)  # (10 + 5) * 2 = 30

  test "binary has higher precedence than keyword":
    let result = interp.evalStatements("""
    Arr := #(1, 2, 3, 4, 5).
    Result := Arr at: 1 + 2
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 4)  # Arr at: (1 + 2) = Arr at: 3 = 4

  test "unary then binary then keyword":
    let result = interp.evalStatements("""
    Container := Table derive: #(items).
    Container >> items [ ^self at: #items ].

    C := Container new.
    C at: #items put: #(1, 2, 3).
    Result := C items at: 2
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 3)  # #(1, 2, 3) at: 2 = 3

  test "keyword message with complex binary expression argument":
    let result = interp.evalStatements("""
    Box := Table derive: #(value).
    Box >> value: v [ self at: #value put: v ].
    Box >> value [ ^self at: #value ].

    B := Box new.
    B value: 2 + 3 * 4.
    Result := B value
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 20)  # (2 + 3) * 4 = 20

  test "arithmetic in keyword arguments":
    let result = interp.evalStatements("""
    Calculator := Object derive.
    Calculator >> calculate: expr [ ^expr ].

    Calc := Calculator new.
    Result := Calc calculate: 10 + 5 * 2 - 3
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 27)  # ((10 + 5) * 2) - 3 = 27


suite "Parser Precedence - Assignment":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "assignment after all operations":
    let (result, err) = interp.doit("X := 1 + 2 * 3. X")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 9)

  test "assignment with keyword message":
    let (result, err) = interp.doit("Arr := #(10, 20, 30). X := Arr at: 1. X")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)


suite "Parser Precedence - Parentheses Override":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "parentheses override precedence":
    let (result, err) = interp.doit("(1 + 2) * 3")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 9)

  test "parentheses in keyword argument":
    let (result, err) = interp.doit("Arr := #(10, 20, 30, 40). Arr at: (1 + 2)")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 40)

  test "explicit parentheses work correctly":
    let result = interp.evalStatements("""
    Arr := #(10, 20, 30, 40, 50, 60, 70, 80).
    Result := Arr at: (2 + 3)
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 60)

  test "parentheses with keyword args":
    let result = interp.evalStatements("""
    MathObj := Object derive.
    MathObj >> add: a and: b [ ^a + b ].

    M := MathObj new.
    Result := M add: (3 + 4) and: 5
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 12)


suite "Parser Precedence - Message Cascades":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "cascade sends multiple messages to same receiver":
    let (result, err) = interp.doit("Arr := #(10, 20, 30). Arr at: 0; at: 1")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)


suite "Parser Precedence - Named Access":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "named access accepts quoted symbol with spaces":
    let result = interp.evalStatements("""
    T := Table new.
    T at: #"ju ju" put: 99.
    Result := T::#"ju ju"
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].kind == vkInt)
      check(result[0][^1].intVal == 99)

  test "named access accepts quoted symbol with punctuation":
    let result = interp.evalStatements("""
    T := Table new.
    T at: #"hx-post" put: "/todos".
    Result := T::#"hx-post"
    """)
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].kind == vkString)
      check(result[0][^1].strVal == "/todos")


suite "Parser Precedence - Complex Combinations":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)

  test "complex expression with all precedence levels":
    let (result, err) = interp.doit("Arr := #(10, 20, 30). X := 0. Arr at: X + 1")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)

  test "binary after unary in keyword arg":
    let (result, err) = interp.doit("Arr := #(-10, 20, 30). X := 0. Arr at: X negated + 1")
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 20)
