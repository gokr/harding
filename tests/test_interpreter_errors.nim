#!/usr/bin/env nim
#
# Error handling tests for Harding interpreter
# Tests error reporting and handling scenarios
#

import std/[unittest, tables, strutils]
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

suite "Interpreter: Error Handling":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "undefined message raises error":
    expect ValueError:
      discard interp.doit("""
      Object someUndefinedMessage
      """)

  test "error includes message selector":
    let result = interp.evalStatements("""
    Obj := Object derive.
    Obj undefinedMethod
    """)

    check(result[1].len > 0)
    check("undefinedMethod" in result[1])

  test "parse errors are reported":
    let result = interp.evalStatements("""
    Obj := Object derive.
    Obj at:
    """)

    check(result[1].len > 0)

  test "message not understood on nil gives meaningful error":
    let result = interp.evalStatements("""
    nil someMessage
    """)

    check(result[1].len > 0)

suite "Interpreter: Complex Error Scenarios":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "nested message send with undefined method":
    let result = interp.evalStatements("""
    Container := Object deriveWithAccessors: #(inner).
    C := Container new.
    C inner: Object new.
    Result := C inner undefinedMethod
    """)

    check(result[1].len > 0)
    check("undefinedMethod" in result[1])

  test "error in block evaluation is reported":
    let result = interp.evalStatements("""
    [ Object undefinedMethod ] value
    """)

    check(result[1].len > 0)

suite "Interpreter: Special Values":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "nil is a valid value":
    let result = interp.evalStatements("""
    Box := Object deriveWithAccessors: #(value).

    Obj := Box new.
    Obj value: nil.
    Result := Obj value
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
