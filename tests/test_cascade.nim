import unittest
import ../src/nimtalk/core/types
import ../src/nimtalk/parser/lexer
import ../src/nimtalk/parser/parser
import ../src/nimtalk/interpreter/evaluator
import ../src/nimtalk/interpreter/objects
import ../src/nimtalk/interpreter/activation

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
    let source = "obj at: 1 put: 'a'; at: 2 put: 'b'"
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

  test "Evaluate simple cascade with counter object":
    let source = """
    counter := Object derive.
    counter at: "value" put: 0.
    counter at: "increment" put: [ self at: "value" put: ((self at: "value") + 1) ].
    counter at: "get" put: [ ^self at: "value" ].
    counter increment; increment.
    result := counter get
    """
    let (results, err) = interp.evalStatements(source)

    check(err.len == 0)
    if err.len > 0:
      echo "Error: ", err
    check(results[^1].kind == vkInt)
    check(results[^1].intVal == 2)
  ##  test "Evaluate cascade with keyword messages":
  ##    let source = """
  ##    dict := Object derive.
  ##    dict at: "storage" put: #{}.
  ##    dict at: "set:" put: [ :key value |
  ##      storage := self at: "storage".
  ##      storage at: key put: value.
  ##      self at: "storage" put: storage
  ##    ].
  ##    dict at: "get:" put: [ storage := self at: "storage". ^storage at: 1 ].
  ##    dict set: "name" value: "Alice"; set: "age" value: 30.
  ##    result1 := dict get: "name".
  ##    result2 := dict get: "age"
  ##    """
  ##    let (results, err) = interp.evalStatements(source)
  ##
  ##    check(err.len == 0)
  ##    if err.len > 0:
  ##      echo "Error: ", err
  ##    # The cascade should have set both values
  ##    # Note: This should work once dict methods are properly implemented
  ##
  ##  test "Cascade receiver evaluated only once":
  ##    let source = """
  ##    counter := Object derive.
  ##    counter at: "count" put: 0.
  ##    counter at: "add:" put: [ :n | self at: "count" put: ((self at: "count") + n) ].
  ##    counter at: "value" put: [ ^self at: "count" ].
  ##    total := counter add: 5; add: 10; value
  ##    """
  ##    let (results, err) = interp.evalStatements(source)
  ##
  ##    check(err.len == 0)
  ##    if err.len > 0:
  ##      echo "Error: ", err
  ##    check(results[^1].kind == vkInt)
  ##    check(results[^1].intVal == 15)
  ##
  ##  test "Nested cascades":
  ##    let source = """
  ##    obj := Object derive.
  ##    inner := Object derive.
  ##    inner at: "value" put: 0.
  ##    inner at: "inc" put: [ self at: "value" put: ((self at: "value") + 1) ].
  ##    obj at: "inner" put: inner.
  ##    (obj at: "inner") inc; inc
  ##    result := (obj at: "inner") at: "value"
  ##    """
  ##    let (results, err) = interp.evalStatements(source)
  ##
  ##    check(err.len == 0)
  ##    if err.len > 0:
  ##      echo "Error: ", err
  ##    check(results[^1].kind == vkInt)
  ##    check(results[^1].intVal == 2)
  ##
  ##  test "Cascade returns result of last message":
  ##    let source = """
  ##    obj := Object derive.
  ##    obj at: "x" put: 10.
  ##    obj at: "y" put: 20.
  ##    obj at: "sum" put: [ ^(self at: "x") + (self at: "y") ].
  ##    obj at: "double" put: [ self at: "x" put: ((self at: "x") * 2). ^self ].
  ##    result := obj double; sum
  ##    """
  ##    let (results, err) = interp.evalStatements(source)
  ##
  ##    check(err.len == 0)
  ##    if err.len > 0:
  ##      echo "Error: ", err
  ##    check(results[^1].kind == vkInt)
  ##    check(results[^1].intVal == 30)  # After double, x=20, y=20, sum=40
  ##
  ##  test "Single message (no cascade) still works":
  ##    let source = """
  ##    obj := Object derive.
  ##    obj at: "value" put: 42.
  ##    result := obj at: "value"
  ##    """
  ##    let (results, err) = interp.evalStatements(source)
  ##
  ##    check(err.len == 0)
  ##    if err.len > 0:
  ##      echo "Error: ", err
  ##    check(results[^1].kind == vkInt)
  ##    check(results[^1].intVal == 42)
  ##
  ##  test "Cascade with temporary variables":
  ##    let source = """
  ##    obj := Object derive.
  ##    obj at: "items" put: #[].
  ##    obj at: "add:" put: [ :item | items := self at: "items". items.add(item). self at: "items" put: items ].
  ##    obj at: "size" put: [ items := self at: "items". ^items.len ].
  ##    obj add: 10; add: 20; add: 30.
  ##    result := obj size
  ##    """
  ##    let (results, err) = interp.evalStatements(source)
  ##
  ##    check(err.len == 0)
  ##    if err.len > 0:
  ##      echo "Error: ", err
  ##    check(results[^1].kind == vkInt)
  ##    check(results[^1].intVal == 3)

  test "AST printing for cascade":
    let source = "counter increment; increment; value"
    let (nodes, parser) = parse(source)

    check(not parser.hasError)
    check(nodes.len == 1)
    let node = nodes[0]
    let astStr = printAST(node)
    # Just check that we got some AST output
    check(astStr.len > 0)
