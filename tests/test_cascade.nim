import unittest
import ../src/harding/core/types
import ../src/harding/parser/parser
import ../src/harding/interpreter/vm
import ./stdlib_test_support

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
    check(cast[MessageNode](cascade.messages[0]).selector == "foo")
    check(cast[MessageNode](cascade.messages[1]).selector == "bar")
    check(cast[MessageNode](cascade.messages[2]).selector == "baz")

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
    check(cast[MessageNode](cascade.messages[0]).selector == "at:put:")
    check(cast[MessageNode](cascade.messages[1]).selector == "at:put:")

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
    check(cast[MessageNode](cascade.messages[0]).selector == "clear")
    check(cast[MessageNode](cascade.messages[1]).selector == "add:")
    check(cast[MessageNode](cascade.messages[2]).selector == "size")

  test "cascade messages retain the receiver rather than chaining results":
    let (values, error) = interp.evalStatements("""
      CascadeReceiver := Object derive: #().
      CascadeReceiver>>first [ ^ 1 ].
      CascadeReceiver>>second [ ^ 2 ].
      CascadeReceiver new first; second
    """)
    require error.len == 0
    require values.len > 0
    check values[^1].intVal == 2

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
    check(cast[MessageNode](cascade.messages[0]).selector == "at:put:")
    check(cast[MessageNode](cascade.messages[1]).selector == "at:put:")

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
    check(cast[MessageNode](cascade.messages[0]).selector == "clear")
    check(cast[MessageNode](cascade.messages[1]).selector == "add:")
    check(cast[MessageNode](cascade.messages[2]).selector == "size")

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
    check(cast[MessageNode](cascade.messages[0]).selector == "at:put:")
    check(cast[MessageNode](cascade.messages[1]).selector == "at:put:")
    check(cast[MessageNode](cascade.messages[2]).selector == "at:put:")

  test "Evaluate cascade containing a control-flow segment":
    ## The parser rewrites ifTrue:/whileTrue: into nkIf/nkWhile with the cascade
    ## receiver substituted, so cascade segments are not all MessageNodes. A blind
    ## cast crashed the VM on `b printString; ifTrue: [...]`.
    let (values, error) = interp.evalStatements("b := true. b printString; ifTrue: [7].")
    check error.len == 0
    check values.len > 0
    check values[^1].kind == vkInt
    check values[^1].intVal == 7

  test "Evaluate cascade evaluates its receiver once":
    let (values, error) = interp.evalStatements("""
      CascadeProbe := Object derive: #(hits).
      CascadeProbe>>touch [ hits := hits + 1 ].
      CascadeProbe>>hits [ ^ hits ].
      CascadeProbe>>hits: value [ hits := value ].
      Target := CascadeProbe new.
      Target hits: 0.
      Target touch; touch; touch.
      Target hits.
    """)
    check error.len == 0
    check values.len > 0
    check values[^1].kind == vkInt
    check values[^1].intVal == 3

suite "Cascades inside parentheses":
  # These cases use builtin collections, so they need a stdlib interpreter.
  var interp = newSharedStdlibInterpreter()

  test "parse: cascade inside parentheses":
    let (nodes, parser) = parse("(obj foo; bar)")
    check not parser.hasError
    check nodes.len == 1
    check nodes[0] != nil
    check nodes[0].kind == nkCascade

  test "parse: cascade inside parentheses followed by a unary message":
    let (nodes, parser) = parse("(obj foo; bar) size")
    check not parser.hasError
    check nodes.len == 1

  test "parenthesized cascade retains its receiver across messages":
    let (values, error) = interp.evalStatements("""
      K := Object derive: #(count).
      K>>initialize [ count := 0. ^ self ].
      K>>bump [ count := count + 1 ].
      K>>count [ ^ count ].
      Result := (K new initialize; bump; bump) count.
    """)
    check error.len == 0
    check values.len > 0
    check values[^1].kind == vkInt
    check values[^1].intVal == 2

  test "cascade on a parenthesized receiver inside parentheses":
    let (values, error) = interp.evalStatements("""
      Arr := Array new.
      Result := ((Arr) add: 1; add: 2; yourself) size.
    """)
    check error.len == 0
    check values.len > 0
    check values[^1].intVal == 2

  test "a parenthesized cascade answers the last message, like a statement":
    # Smalltalk semantics: `obj a; b` answers what `b` answers, not the
    # receiver. `yourself` is how a caller recovers the receiver.
    let (values, error) = interp.evalStatements("""
      Arr := Array new.
      Last := (Arr add: 1; add: 2).
      Whole := (Arr add: 3; yourself).
      Result := array{Last = 2, Whole isKindOf: Array}
    """)
    check error.len == 0
    check values.len > 0
    let flags = values[^1].instVal.elements
    check flags[0].boolVal
    check flags[1].boolVal

  test "parenthesized cascade is a keyword argument and evaluates its receiver once":
    let (values, error) = interp.evalStatements("""
      CascadeFactory := Object derive: #(calls).
      CascadeFactory>>initialize [ calls := 0. ^self ].
      CascadeFactory>>make [ calls := calls + 1. ^Array new ].
      CascadeFactory>>calls [ ^calls ].
      factory := CascadeFactory new.
      receiver := Array new.
      receiver add: (factory make add: 1; add: 2; yourself).
      ((receiver first size) = 2) and: [ factory calls = 1 ]
    """)
    require error.len == 0
    require values.len > 0
    check values[^1].boolVal

  test "parenthesized cascades allow unary and binary messages across lines":
    let (values, error) = interp.evalStatements("""
      a := Array new.
      ((a add: 1;
          add: 2;
          yourself) size) + (1 + 2; + 3)
    """)
    require error.len == 0
    require values.len > 0
    check values[^1].intVal == 6

  test "cascade inside parentheses can be nested in a larger expression":
    let (values, error) = interp.evalStatements("""
      Arr := Array new.
      Result := ((Arr add: 1; add: 2; yourself) inject: 0 into: [:a :b | a + b]).
    """)
    check error.len == 0
    check values.len > 0
    check values[^1].intVal == 3
