#!/usr/bin/env nim
#
# Tests for constant literal optimization
# Verifies that constant arrays/tables are cached at parse time
#

import std/[unittest, tables, logging]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser, constant_analysis]
import ../src/harding/interpreter/[vm, objects]

suite "Constant Literal Optimization":
  var interp: Interpreter

  setup:
    configureLogging(lvlWarn)
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "constant array literal is analyzed as constant":
    # Parse a constant array and verify it's marked as constant
    let (nodes, parser) = parse("#(1 2 3)")
    check(nodes.len == 1)
    check(nodes[0].kind == nkArray)
    let arr = cast[ArrayNode](nodes[0])
    
    check(arr.isConstant == true)
    check(arr.elements.len == 3)
    check(arr.cachedValue.kind == vkArray)
    check(arr.cachedValue.arrayVal.len == 3)
    check(arr.cachedValue.arrayVal[0].intVal == 1)
    check(arr.cachedValue.arrayVal[1].intVal == 2)
    check(arr.cachedValue.arrayVal[2].intVal == 3)

  test "empty array is analyzed as constant":
    let (nodes, parser) = parse("#()")
    check(nodes.len == 1)
    check(nodes[0].kind == nkArray)
    let arr = cast[ArrayNode](nodes[0])
    
    check(arr.isConstant == true)
    check(arr.elements.len == 0)
    check(arr.cachedValue.kind == vkArray)
    check(arr.cachedValue.arrayVal.len == 0)

  test "array with non-constant elements is not cached":
    # Array with variable is not constant
    let code = """
    X := 1.
    Arr := #(X).
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)  # Should still work, just not cached

  test "constant table literal is analyzed as constant":
    let (nodes, parser) = parse("#{\"a\" -> 1, \"b\" -> 2}")
    check(nodes.len == 1)
    check(nodes[0].kind == nkTable)
    let tbl = cast[TableNode](nodes[0])
    
    check(tbl.isConstant == true)
    check(tbl.entries.len == 2)
    check(tbl.cachedValue.kind == vkTable)
    check(tbl.cachedValue.tableVal.len == 2)

  test "empty table is analyzed as constant":
    let (nodes, parser) = parse("#{}")
    check(nodes.len == 1)
    check(nodes[0].kind == nkTable)
    let tbl = cast[TableNode](nodes[0])
    
    check(tbl.isConstant == true)
    check(tbl.entries.len == 0)
    check(tbl.cachedValue.kind == vkTable)
    check(tbl.cachedValue.tableVal.len == 0)

  test "table with non-constant values is not cached":
    let code = """
    X := 1.
    Tbl := #{"key" -> X}.
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)  # Should still work, just not cached

  test "constant array works correctly at runtime":
    let code = """
    Arr := #(1 2 3).
    Arr at: 0
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 1)

  test "constant table works correctly at runtime":
    let code = """
    Tbl := #{"name" -> "test", "value" -> 42}.
    Tbl at: "value"
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 42)

  test "nested array is not cached (conservative approach)":
    # Nested arrays are not marked as constant to avoid type mismatch issues
    let (nodes, parser) = parse("#(#())")
    check(nodes.len == 1)
    check(nodes[0].kind == nkArray)
    let arr = cast[ArrayNode](nodes[0])
    
    # Outer array should not be constant because it contains a nested array
    check(arr.isConstant == false)
    check(arr.elements.len == 1)

  test "array with mixed literals and symbols is constant":
    let (nodes, parser) = parse("#(1 #symbol \"string\")")
    check(nodes.len == 1)
    check(nodes[0].kind == nkArray)
    let arr = cast[ArrayNode](nodes[0])
    
    check(arr.isConstant == true)
    check(arr.elements.len == 3)
    check(arr.cachedValue.kind == vkArray)
    check(arr.cachedValue.arrayVal[0].kind == vkInt)
    check(arr.cachedValue.arrayVal[1].kind == vkSymbol)
    check(arr.cachedValue.arrayVal[2].kind == vkString)

  test "multiple evaluations of same constant array work":
    let code = """
    Arr := #(1 2 3).
    First := Arr at: 0.
    Second := Arr at: 1.
    Third := Arr at: 2.
    First + Second + Third
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 6)  # 1 + 2 + 3 = 6

  test "table with nested constant values works at runtime":
    let code = """
    Tbl := #{"arr" -> #(1 2), "val" -> 42}.
    Tbl at: "val"
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 42)
