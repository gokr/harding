#
# test_literals.nim - Tests for literals including newlines and constant optimization
#

import std/[unittest, tables, logging, strutils]
import ../src/harding/core/types
import ../src/harding/parser/parser
import ../src/harding/interpreter/vm
import ./stdlib_test_support

var sharedInterp = newSharedStdlibInterpreter()


suite "Array Literals with Newlines":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "array literal with newline between elements":
    let result = interp.evalStatements("""
      Arr := #(
        1,
        2,
        3
      ).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "array literal with mixed newlines and spaces":
    let result = interp.evalStatements("""
      Arr := #(1,
        2, 3,
        4).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 4)

  test "array literal with comma separators":
    let result = interp.evalStatements("""
      Arr := #(1, 2, 3, 4).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 4)

  test "array literal without commas is rejected":
    let result = interp.evalStatements("""
      Arr := #(1 2 3).
      Result := Arr size
    """)
    check(result[1].len > 0)

  test "array literal with elements on separate lines":
    let result = interp.evalStatements("""
      Arr := #(
        "first",
        "second",
        "third"
      ).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "nested array literal with newlines":
    let result = interp.evalStatements("""
      Arr := #(
        #(1, 2),
        #(3, 4),
        #(5, 6)
      ).
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)


suite "Table Literals with Newlines":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "table literal with newline between entries":
    let result = interp.evalStatements("""
      T := #{
        "a" -> 1
        "b" -> 2
        "c" -> 3
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "table literal with mixed newlines and commas":
    let result = interp.evalStatements("""
      T := #{ "a" -> 1,
        "b" -> 2,
        "c" -> 3 }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "table literal with entries on separate lines":
    let result = interp.evalStatements("""
      T := #{
        "name" -> "Alice"
        "age" -> 30
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "table literal value can be a unary message without parentheses":
    let result = interp.evalStatements("""
      Friend := Object derive.
      Friend selector: #name put: [ ^"Alice" ].
      myFriend := Friend new.
      T := #{ "his name" -> myFriend name }.
      Result := T at: "his name"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Alice")

  test "table literal newline entries do not require trailing commas":
    let result = interp.evalStatements("""
      T := #{
        "count" -> #(1, 2, 3) size
        "age" -> 42
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "nested table literal with newlines":
    let result = interp.evalStatements("""
      T := #{
        "first" -> #{ "x" -> 1 }
        "second" -> #{ "y" -> 2 }
      }.
      Result := T size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)


suite "Quoted Symbol Literals":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "quoted symbol literal with whitespace parses and evaluates":
    let result = interp.evalStatements("Result := #\"my symbol\"")
    check(result[1].len == 0)
    check(result[0][^1].kind == vkSymbol)
    check(result[0][^1].symVal == "my symbol")

  test "quoted symbol literal with whitespace prints as symbol":
    let result = interp.evalStatements("Result := #\"my symbol\" printString")
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "#my symbol")


suite "Constant Literal Optimization":
  var interp: Interpreter

  setup:
    configureLogging(lvlWarn)
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "constant array literal is analyzed as constant":
    let (nodes, parser) = parse("#(1, 2, 3)")
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
    let code = """
    X := 1.
    Arr := #(X).
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)

  test "constant table literal is analyzed as constant":
    let (nodes, parser) = parse("#{\"a\" -> 1, \"b\" -> 2}".replace("\\", ""))
    check(nodes.len == 1)
    check(nodes[0].kind == nkTable)
    let tbl = cast[TableNode](nodes[0])

    check(tbl.isConstant == true)
    check(tbl.entries.len == 2)
    check(tbl.cachedValue.kind == vkTable)
    check(tbl.cachedValue.tableVal.len == 2)

  test "empty table is analyzed as constant":
    let (nodes, parser) = parse("#{ }")
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
    check(err.len == 0)

  test "constant array works correctly at runtime":
    let code = """
    Arr := #(1, 2, 3).
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
    let (nodes, parser) = parse("#(#())")
    check(nodes.len == 1)
    check(nodes[0].kind == nkArray)
    let arr = cast[ArrayNode](nodes[0])

    check(arr.isConstant == false)
    check(arr.elements.len == 1)

  test "array with mixed literals and symbols is constant":
    let (nodes, parser) = parse("#(1, #symbol, \"string\")")
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
    Arr := #(1, 2, 3).
    First := Arr at: 0.
    Second := Arr at: 1.
    Third := Arr at: 2.
    First + Second + Third
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 6)

  test "table with nested constant values works at runtime":
    let code = """
    Tbl := #{"arr" -> #(1, 2), "val" -> 42}.
    Tbl at: "val"
    """
    let (result, err) = interp.doit(code)
    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 42)
