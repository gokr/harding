#!/usr/bin/env nim
#
# Core tests for Harding
# Tests basic parsing, objects, and evaluation
#

import std/logging
import std/tables
import unittest
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

# Configure logging for tests - set to ERROR by default to keep test output clean
configureLogging(lvlError)

suite "Tokenizer":
  test "recognizes integer literals":
    let tokens = lex("42")
    check tokens.len == 2
    check tokens[0].kind == tkInt
    check tokens[0].value == "42"

  test "recognizes string literals":
    let tokens = lex("\"hello\"")
    check tokens.len == 2
    check tokens[0].kind == tkString
    check tokens[0].value == "hello"

  test "recognizes identifiers":
    let tokens = lex("foo")
    check tokens.len == 2
    check tokens[0].kind == tkIdent
    check tokens[0].value == "foo"

  test "recognizes keywords":
    let tokens = lex("at:")
    check tokens.len == 2
    check tokens[0].kind == tkKeyword
    check tokens[0].value == "at:"

  test "handles keyword sequences":
    let tokens = lex("at:put:")
    check tokens.len == 2
    check tokens[0].kind == tkKeyword
    check tokens[0].value == "at:put:"

  test "recognizes symbols":
    let tokens = lex("#selector")
    check tokens.len == 2
    check tokens[0].kind == tkSymbol
    check tokens[0].value == "selector"

suite "Parser":
  test "creates literal nodes":
    let tokens = lex("42")
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    check node != nil
    check node of LiteralNode

  test "handles unary messages":
    # For now, just test that it doesn't crash
    let tokens = lex("Object new")
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    check node != nil

  test "handles keyword messages":
    let tokens = lex("obj at: #key")
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    check node != nil

  test "reports errors for invalid input":
    let tokens = lex("@")
    var parser = initParser(tokens)
    discard parser.parseExpression()
    check parser.hasError or parser.peek().kind == tkError

suite "Object system":
  test "root object initialization":
    let root = initRootClass()
    check root != nil
    check "Root" in root.tags

  test "object creation":
    # Test that we can create new instances
    let root = initRootClass()
    check root != nil
    check "Root" in root.tags

  test "property access (using Table instance)":
    # In new system, "properties" are stored in a Table instance
    # Table keys are now NodeValue (any value type, not just strings)
    let root = initRootClass()
    var entries = initTable[NodeValue, NodeValue]()
    entries[toValue("test")] = toValue(42)
    let dict = Instance(kind: ikTable, class: root, entries: entries)
    let val = dict.entries[toValue("test")]
    check val.kind == vkInt
    check val.intVal == 42

  test "table with arbitrary NodeValue keys":
    # Test that tables can use any NodeValue as key
    var entries = initTable[NodeValue, NodeValue]()

    # Integer key
    entries[toValue(1)] = toValue("one")
    # String key
    entries[toValue("name")] = toValue("Alice")
    # Symbol key
    entries[toSymbol("age")] = toValue(30)
    # Float key
    entries[toValue(3.14)] = toValue("pi")
    # Nil key
    entries[nilValue()] = toValue("nilValue")

    check entries[toValue(1)].strVal == "one"
    check entries[toValue("name")].strVal == "Alice"
    check entries[toSymbol("age")].intVal == 30
    check entries[toValue(3.14)].strVal == "pi"
    check entries[nilValue()].strVal == "nilValue"

  test "NodeValue hash and equality consistency":
    # Ensure that equal values have equal hashes
    let int1 = toValue(42)
    let int2 = toValue(42)
    let int3 = toValue(99)

    # Equal values should be equal
    check int1 == int2
    check int1 != int3

    # Equal values should have equal hashes
    check hash(int1) == hash(int2)

    # String values
    let str1 = toValue("hello")
    let str2 = toValue("hello")
    let str3 = toValue("world")

    check str1 == str2
    check str1 != str3
    check hash(str1) == hash(str2)

  test "Table class with integer keys":
    # Test using integer keys directly through the Table class
    discard initCoreClasses()
    var entries = initTable[NodeValue, NodeValue]()
    entries[toValue(1)] = toValue(100)
    entries[toValue(2)] = toValue(200)
    entries[toValue(99)] = toValue("ninety-nine")

    let t = newTableInstance(tableClass, entries)
    check getTableValue(t, toValue(1)).intVal == 100
    check getTableValue(t, toValue(2)).intVal == 200
    check getTableValue(t, toValue(99)).strVal == "ninety-nine"

  test "Table class with mixed type keys":
    # Test mixing different key types in the same table
    discard initCoreClasses()
    var entries = initTable[NodeValue, NodeValue]()
    entries[toValue(1)] = toValue("integer key")
    entries[toValue("string")] = toValue("string key")
    entries[toValue(2.5)] = toValue("float key")
    entries[toSymbol("sym")] = toValue("symbol key")

    let t = newTableInstance(tableClass, entries)
    check getTableValue(t, toValue(1)).strVal == "integer key"
    check getTableValue(t, toValue("string")).strVal == "string key"
    check getTableValue(t, toValue(2.5)).strVal == "float key"
    check getTableValue(t, toSymbol("sym")).strVal == "symbol key"

suite "Interpreter":
  test "evaluates integers":
    var interp = newInterpreter()
    let tokens = lex("42")
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.evalWithVM(node)
    check evalResult.kind == vkInt
    check evalResult.intVal == 42

  test "handles Object new":
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    let code = "Object new"
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.evalWithVM(node)
    check evalResult.kind == vkInstance  # New Instance model

  test "handles message sends":
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)  # Load stdlib for printString method

    # Test simple unary message send
    let code = "3 printString"
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.evalWithVM(node)

    # Should return a string representation
    check evalResult.kind == vkString

  test "handles canonical Smalltalk test (3 + 4 = 7)":
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)  # Load stdlib for + operator

    # Test basic arithmetic addition
    let code = "3 + 4"
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.evalWithVM(node)

    # Should evaluate to 7
    check evalResult.kind == vkInt
    check evalResult.intVal == 7

  test "handles undefined messages gracefully":
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

    let code = "self someUndefinedMessage"
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()

    expect ValueError:
      discard interp.evalWithVM(node)
