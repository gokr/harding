#!/usr/bin/env nim
#
# Core tests for Nimtalk
# Tests basic parsing, objects, and evaluation
#

import unittest
import ../src/nimtalk/core/types
import ../src/nimtalk/parser/[lexer, parser]
import ../src/nimtalk/interpreter/[evaluator, objects]

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
    let tokens = lex("Object clone")
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    check node != nil

  test "handles keyword messages":
    let tokens = lex("obj at: 'key'")
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
    let root = initRootObject()
    check root != nil
    check "Object" in root.tags
    check "Proto" in root.tags

  test "object cloning":
    let root = initRootObject()
    let clone = root.clone().toObject()
    check clone != nil
    check clone != root

  test "property access":
    var obj = newObject()
    obj.setProperty("test", toValue(42))
    let val = obj.getProperty("test")
    check val.kind == vkInt
    check val.intVal == 42

suite "Interpreter":
  test "evaluates integers":
    var interp = newInterpreter()
    let tokens = lex("42")
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.eval(node)
    check evalResult.kind == vkInt
    check evalResult.intVal == 42

  test "handles property access":
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    let code = "Object clone"
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.eval(node)
    check evalResult.kind == vkObject

  test "handles message sends":
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

    # Test simple unary message send
    let code = "3 printString"
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.eval(node)

    # Should return a string representation
    check evalResult.kind == vkString

  test "handles canonical Smalltalk test (3 + 4 = 7)":
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

    # Test basic arithmetic addition
    let code = "3 + 4"
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()
    let evalResult = interp.eval(node)

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
      discard interp.eval(node)
