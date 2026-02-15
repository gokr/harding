import unittest
import ../src/harding/core/types
import ../src/harding/parser/parser
import ../src/harding/interpreter/vm

suite "Cascade Tests":
  setup:
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()

  test "Parse simple cascade with unary messages":
    let source = "obj foo; bar; baz"
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    check(node != nil)
    check(node.kind == nkCascade)

    let cascade = node.CascadeNode
    check(cascade.messages.len == 3)
    check(cascade.messages[0].selector == "foo")
    check(cascade.messages[1].selector == "bar")
    check(cascade.messages[2].selector == "baz")

  test "Parse cascade with keyword messages":
    let source = "obj at: 1 put: #a; at: 2 put: #b"
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    check(node != nil)
    check(node.kind == nkCascade)

    let cascade = node.CascadeNode
    check(cascade.messages.len == 2)
    check(cascade.messages[0].selector == "at:put:")
    check(cascade.messages[1].selector == "at:put:")

  test "Parse cascade with mixed message types":
    let source = "obj clear; add: 5; size"
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    check(node != nil)
    check(node.kind == nkCascade)

    let cascade = node.CascadeNode
    check(cascade.messages.len == 3)
    check(cascade.messages[0].selector == "clear")
    check(cascade.messages[1].selector == "add:")
    check(cascade.messages[2].selector == "size")

  test "Evaluate cascade with receiver chaining":
    # Test cascade where each message result is used as receiver for next
    # With new cascade semantics: obj msg1; msg2 sends msg1 to obj,
    # then sends msg2 to the result of msg1
    # Note: This test verifies the new semantics (not traditional Smalltalk)
    skip()  # Skip this test - cascade semantics are in flux

  test "AST printing for cascade":
    let source = "counter increment; increment; value"
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    let astStr = printAST(node)
    # Just check that we got some AST output
    check(astStr.len > 0)

  test "Parse multiline cascade with keyword messages":
    let source = """
obj at: 1 put: #a;
  at: 2 put: #b
"""
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    check(node != nil)
    check(node.kind == nkCascade)

    let cascade = node.CascadeNode
    check(cascade.messages.len == 2)
    check(cascade.messages[0].selector == "at:put:")
    check(cascade.messages[1].selector == "at:put:")

  test "Parse multiline cascade with mixed message types":
    let source = """
obj clear;
  add: 5;
  size
"""
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    check(node != nil)
    check(node.kind == nkCascade)

    let cascade = node.CascadeNode
    check(cascade.messages.len == 3)
    check(cascade.messages[0].selector == "clear")
    check(cascade.messages[1].selector == "add:")
    check(cascade.messages[2].selector == "size")

  test "Parse multiline cascade with multiple newlines":
    let source = """
obj at: 1 put: #a;


  at: 2 put: #b;
    at: 3 put: #c
"""
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    check(node != nil)
    check(node.kind == nkCascade)

    let cascade = node.CascadeNode
    check(cascade.messages.len == 3)
    check(cascade.messages[0].selector == "at:put:")
    check(cascade.messages[1].selector == "at:put:")
    check(cascade.messages[2].selector == "at:put:")

