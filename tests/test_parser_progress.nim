import std/[unittest, strutils]
import ../src/harding/parser/parser
import ../src/harding/core/types

suite "Block parser progress":
  test "large blocks are bounded by source progress not statement count":
    let source = "[| total | total := 0.\n" & "total := total + 1.\n".repeat(250) & "total]"
    let (nodes, syntax) = parse(source)
    require not syntax.hasError
    require nodes.len == 1 and nodes[0] of BlockNode
    check BlockNode(nodes[0]).body.len == 252

  test "large methods with separators and nested blocks parse":
    let source = "LongMethod := Object derive: #(). LongMethod>>run [\n" &
      "true ifTrue: [1].\n".repeat(150) & "^42]"
    let (nodes, syntax) = parse(source)
    check not syntax.hasError
    check nodes.len == 2

  test "malformed blocks still terminate with errors":
    for source in ["[1. 2.", "[| unfinished"]:
      let (_, syntax) = parse(source)
      check syntax.hasError
