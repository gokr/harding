## Tests for Smalltalk message precedence rules
## Precedence: unary > binary > keyword (left-to-right for same type)
##
## These tests validate that:
## 1. Unary messages have higher precedence than binary
## 2. Binary operators are left-to-right associative
## 3. Binary operators have higher precedence than keyword messages
## 4. Arguments to keyword messages can contain binary expressions

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/[vm, objects]

suite "Message Precedence: Unary > Binary > Keyword":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "unary has higher precedence than binary":
    # obj foo + bar should parse as (obj foo) + bar, not obj (foo + bar)
    let result = interp.evalStatements("""
    TestObj := Object derive.
    TestObj >> value [ ^10 ].
    TestObj >> double [ ^self value * 2 ].

    Obj := TestObj new.
    Result := Obj double + 5
    """)

    if result[1].len > 0:
      stderr.writeLine("Unary > Binary ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 25)  # (10 * 2) + 5 = 25

  test "binary operators are left-to-right associative":
    # a + b * c should parse as (a + b) * c, not a + (b * c)
    let result = interp.evalStatements("""
    # Left-to-right: (10 + 5) * 2 = 30, not 10 + (5 * 2) = 20
    Result := 10 + 5 * 2
    """)

    if result[1].len > 0:
      stderr.writeLine("Binary left-to-right ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 30)  # (10 + 5) * 2 = 30

  test "binary has higher precedence than keyword":
    # arr at: 1 + 2 should be arr at: (1 + 2) = arr at: 3 = 3
    let result = interp.evalStatements("""
    Arr := #(1 2 3 4 5).
    Result := Arr at: 1 + 2
    """)

    if result[1].len > 0:
      stderr.writeLine("Binary > Keyword ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 3)  # Arr at: (1 + 2) = Arr at: 3 = 3

  test "comma binary operator in keyword argument":
    # Test that comma operator is parsed as part of the keyword argument
    # Note: We use + operator instead of comma since comma for strings is not implemented
    let result = interp.evalStatements("""
    # Test parsing: 5 + 3 should be parsed as one argument to at:
    Arr := #(1 2 3 4 5 6 7 8).
    Result := Arr at: 5 + 3
    """)

    if result[1].len > 0:
      stderr.writeLine("Comma in keyword arg ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      # Should be 8 (5 + 3 = 8, Arr at: 8 = 8)
      check(result[0][^1].intVal == 8)

  test "unary then binary then keyword":
    # Complex chain: c items at: 2
    # Should be: (c items) at: 2
    let result = interp.evalStatements("""
    Container := Table derive: #(items).
    Container >> items [ ^self at: #items ].

    C := Container new.
    C at: #items put: #(1 2 3).
    # C items at: 2 should be #(1 2 3) at: 2 = 2
    Result := C items at: 2
    """)

    if result[1].len > 0:
      stderr.writeLine("Unary+binary+keyword ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 2)

  test "multiple unary messages left-to-right":
    # obj foo bar baz should be ((obj foo) bar) baz
    let result = interp.evalStatements("""
    Chain := Object derive.
    Chain >> first [ ^self ].
    Chain >> second [ ^self ].
    Chain >> third [ ^42 ].

    C := Chain new.
    Result := C first second third
    """)

    if result[1].len > 0:
      stderr.writeLine("Unary left-to-right ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 42)

  test "parentheses override precedence":
    # obj foo: (bar + baz) should have parentheses evaluated first
    let result = interp.evalStatements("""
    MathObj := Object derive.
    MathObj >> add: a and: b [ ^a + b ].

    M := MathObj new.
    # With parens: 3 + 4 = 7, then add: 7 and: 5 = 12
    Result := M add: (3 + 4) and: 5
    """)

    if result[1].len > 0:
      stderr.writeLine("Parentheses ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 12)

  test "keyword message with complex binary expression argument":
    # obj key: a + b * c should be obj key: ((a + b) * c)
    let result = interp.evalStatements("""
    Box := Table derive: #(value).
    Box >> value: v [ self at: #value put: v ].
    Box >> value [ ^self at: #value ].

    B := Box new.
    # B value: 2 + 3 * 4 should set value to (2 + 3) * 4 = 20
    B value: 2 + 3 * 4.
    Result := B value
    """)

    if result[1].len > 0:
      stderr.writeLine("Keyword with binary ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 20)

  test "explicit parentheses work as workaround":
    # Verify explicit parentheses work correctly
    let result = interp.evalStatements("""
    # With explicit parentheses: (5 + 3) should be 8
    Arr := #(1 2 3 4 5 6 7 8).
    Result := Arr at: (5 + 3)
    """)

    if result[1].len > 0:
      stderr.writeLine("Explicit parens ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 8)

  test "binary minus in keyword argument":
    # arr at: 10 - 3 should be arr at: (10 - 3) = arr at: 7
    let result = interp.evalStatements("""
    Arr := #(10 20 30 40 50 60 70 80).
    Result := Arr at: 10 - 3
    """)

    if result[1].len > 0:
      stderr.writeLine("Binary minus ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 70)  # Arr at: 7 = 70

  test "arithmetic in keyword arguments":
    # Multiple arithmetic operations in keyword argument
    let result = interp.evalStatements("""
    Calculator := Object derive.
    Calculator >> calculate: expr [ ^expr ].

    Calc := Calculator new.
    # Should compute: ((10 + 5) * 2) - 3 = 27
    Result := Calc calculate: 10 + 5 * 2 - 3
    """)

    if result[1].len > 0:
      stderr.writeLine("Arithmetic ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      check(result[0][^1].intVal == 27)  # ((10 + 5) * 2) - 3 = 27

  test "user reported case - writeline with binary":
    # This replicates the user's issue: writeline: "Hey", (3 + 4) printString
    # But using + instead of comma since comma operator is not implemented for strings
    let result = interp.evalStatements("""
    Output := Table derive: #(buffer).
    Output >> initialize [ self at: #buffer put: 0 ].
    Output >> add: n [ self at: #buffer put: ((self at: #buffer) + n) ].
    Output >> total [ ^self at: #buffer ].

    Out := Output new.
    Out initialize.
    # Should add (3 + 4) = 7
    Out add: 3 + 4.
    Result := Out total
    """)

    if result[1].len > 0:
      stderr.writeLine("User case ERROR: ", result[1])
    check(result[1].len == 0)
    if result[0].len >= 1:
      # Should be 7 (3 + 4 = 7)
      check(result[0][^1].intVal == 7)
