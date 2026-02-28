#
# test_stdlib_strings.nim - Tests for string standard library functionality
# Includes: Strings, Strings - Advanced, Symbol
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

# Shared interpreter initialized once for all suites
var sharedInterp = newSharedStdlibInterpreter()

suite "Stdlib: Strings":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "string size returns length":
    let result = interp.evalStatements("""
      S := "hello".
      Result := S size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

  test "string uppercase works":
    let result = interp.evalStatements("""
      S := "hello" uppercase.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "HELLO")

  test "string lowercase works":
    let result = interp.evalStatements("""
      S := "HELLO" lowercase.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "string trim works":
    let result = interp.evalStatements("""
      S := "  hello  " trim.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "string split: works":
    let result = interp.evalStatements("""
      Arr := "a,b,c" split: ",".
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "string concatenation with , (comma)":
    let result = interp.evalStatements("""
      S1 := "Hello".
      S2 := " World".
      Result := S1 , S2
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Hello World")

  test "string concatenation chains":
    let result = interp.evalStatements("""
      Result := "a" , "b" , "c" , "d"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "abcd")

  test "string concatenation with number (auto-conversion)":
    # Auto-conversion of numbers to strings via toString
    let result = interp.evalStatements("""
      Result := "The answer is " , 42
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "The answer is 42")

  test "string concatenation with empty string":
    let result = interp.evalStatements("""
      Result := "hello" , ""
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello")

  test "string less-than comparison works":
    let result = interp.evalStatements("""
      Result := "alpha" < "beta"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

suite "Stdlib: Strings - Advanced":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "indexOf: returns position of substring":
    let result = interp.evalStatements("""
      Result := "hello world" indexOf: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal > 0)

  test "indexOf: returns -1 when not found":
    let result = interp.evalStatements("""
      Result := "hello" indexOf: "xyz"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == -1)

  test "includesSubString: returns true when present":
    let result = interp.evalStatements("""
      Result := "hello world" includesSubString: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "includesSubString: returns false when absent":
    let result = interp.evalStatements("""
      Result := "hello" includesSubString: "xyz"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "replace:with: replaces substring":
    let result = interp.evalStatements("""
      Result := "hello world" replace: "world" with: "there"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "hello there")

  test "asInteger converts string to integer":
    let result = interp.evalStatements("""
      Result := "42" asInteger
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "asSymbol converts string to symbol":
    let result = interp.evalStatements("""
      Result := "hello" asSymbol
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkSymbol)

  test "repeat: repeats string":
    let result = interp.evalStatements("""
      Result := "ab" repeat: 3
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "ababab")

  test "from:to: extracts substring":
    let result = interp.evalStatements("""
      Result := "hello" from: 1 to: 3
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "ell")

  test "startsWith: returns true for matching prefix":
    let result = interp.evalStatements("""
      Result := "hello world" startsWith: "hello"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "startsWith: returns false for non-matching prefix":
    let result = interp.evalStatements("""
      Result := "hello world" startsWith: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "endsWith: returns true for matching suffix":
    let result = interp.evalStatements("""
      Result := "hello world" endsWith: "world"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "endsWith: returns false for non-matching suffix":
    let result = interp.evalStatements("""
      Result := "hello world" endsWith: "hello"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

suite "Stdlib: Symbol":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "symbol literal has vkSymbol kind":
    let (result, err) = interp.doit("#foo")
    check(err.len == 0)
    check(result.kind == vkSymbol)

  test "symbol name is accessible via asString":
    let results = interp.evalStatements("""
      S := #foo asString.
      T := #foo asString.
      Result := S = T
    """)
    check(results[1].len == 0)
    check(results[0][^1].kind == vkBool)
    check(results[0][^1].boolVal == true)

  test "different symbols are not equal":
    let (result, err) = interp.doit("#foo = #bar")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "symbol asString returns string":
    let (result, err) = interp.doit("#hello asString")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "hello")

  test "symbol printString returns #-prefixed form":
    let (result, err) = interp.doit("#hello printString")
    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "#hello")

  test "string asSymbol produces vkSymbol":
    let (result, err) = interp.doit("\"hello\" asSymbol")
    check(err.len == 0)
    check(result.kind == vkSymbol)
