#!/usr/bin/env nim
#
# Tests for json{} literal syntax and Json class
#

import std/[unittest, strutils, json]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/interpreter/[vm, objects]

suite "Json Literal Syntax":
  test "parses json{} literal with empty object":
    let tokens = lex("json{}")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage
    let msg = cast[MessageNode](nodes[0])
    check msg.selector == "buildDynamic:"
    check msg.receiver.kind == nkIdent
    check cast[IdentNode](msg.receiver).name == "Json"
    check msg.arguments.len == 1

  test "parses json{} literal with simple object":
    let tokens = lex("json{\"x\": 10}")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage

  test "normalizes prefix to TitleCase":
    # json, Json, JSON should all become "Json"
    let testCases = ["json{}", "Json{}", "JSON{}"]
    for testCase in testCases:
      let tokens = lex(testCase)
      var p = initParser(tokens)
      let nodes = p.parseStatements()
      check nodes.len == 1
      let msg = cast[MessageNode](nodes[0])
      check cast[IdentNode](msg.receiver).name == "Json"

  test "parses json{} with nested Table":
    let tokens = lex("json{\"outer\": #{\"inner\" -> 1}}")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage

  test "handles json{} with arrays":
    let tokens = lex("json{\"items\": #(1 2 3)}")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage

  test "handles complex json{} content":
    let tokens = lex("json{\"name\": \"Alice\", \"age\": 30, \"active\": true}")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage

suite "Json Class":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

  test "Json parseLiteral: returns JSON string":
    # Test that Json parseLiteral: method exists and returns a string
    let (results, err) = interp.evalStatements("Result := Json parseLiteral: \"x: 10\"")
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    check results[^1].strVal.contains("x")

  test "Json parse: converts JSON to Harding objects":
    # Parse simple JSON object
    let (results, err) = interp.evalStatements("Result := Json parse: \"{}\"")
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkInstance

  test "Json stringify: converts Harding to JSON":
    let (results, err) = interp.evalStatements("""
    Result := Json stringify: #{"a" -> 1, "b" -> 2}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    check results[^1].strVal.contains("\"a\"")
    check results[^1].strVal.contains("\"b\"")

  test "json{} literal produces valid JSON":
    let (results, err) = interp.evalStatements("""
    Result := json{"status": "ok", "count": 42}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    # Verify it's valid JSON by parsing it
    let parsed = parseJson(results[^1].strVal)
    check parsed.hasKey("status")
    check parsed.hasKey("count")
    check parsed["count"].getInt() == 42

  test "empty json{} returns empty object":
    let (results, err) = interp.evalStatements("""
    Result := json{}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    check results[^1].strVal == "{}"

  test "json{} with nested Tables":
    let (results, err) = interp.evalStatements("""
    Result := json{"person": #{"name" -> "Alice", "age" -> 30}}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    let parsed = parseJson(results[^1].strVal)
    check parsed["person"]["name"].getStr() == "Alice"
    check parsed["person"]["age"].getInt() == 30

  test "json{} with arrays":
    let (results, err) = interp.evalStatements("""
    Result := json{"items": #(1 2 3)}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    let parsed = parseJson(results[^1].strVal)
    check parsed["items"].len == 3
    check parsed["items"][0].getInt() == 1

  test "json{} preserves JSON structure":
    let (results, err) = interp.evalStatements("""
    Result := json{"nested": {"deep": {"value": 123}}}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    let parsed = parseJson(results[^1].strVal)
    check parsed["nested"]["deep"]["value"].getInt() == 123

  test "json{} with JSON array syntax [1, 2, 3]":
    let (results, err) = interp.evalStatements("""
    Result := json{"items": [1, 2, 3]}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    let parsed = parseJson(results[^1].strVal)
    check parsed["items"].len == 3
    check parsed["items"][0].getInt() == 1
    check parsed["items"][2].getInt() == 3

  test "json{} with arrays of objects":
    let (results, err) = interp.evalStatements("""
    Result := json{"users": [{"name": "Alice"}, {"name": "Bob"}]}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    let parsed = parseJson(results[^1].strVal)
    check parsed["users"].len == 2
    check parsed["users"][0]["name"].getStr() == "Alice"
    check parsed["users"][1]["name"].getStr() == "Bob"

  test "json{} with nested arrays":
    let (results, err) = interp.evalStatements("""
    Result := json{"matrix": [[1, 2], [3, 4]]}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    let parsed = parseJson(results[^1].strVal)
    check parsed["matrix"][0][1].getInt() == 2
    check parsed["matrix"][1][0].getInt() == 3

  test "json{} with empty array":
    let (results, err) = interp.evalStatements("""
    Result := json{"items": []}
    """)
    check err.len == 0
    check results.len >= 1
    check results[^1].kind == vkString
    let parsed = parseJson(results[^1].strVal)
    check parsed["items"].len == 0
