#!/usr/bin/env nim
#
# Basic compiler tests for Harding
# Tests parsing, code generation, and round-trip compilation

import std/[unittest, strutils, os, tables]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/compiler/[context, types, symbols, analyzer]
import ../src/harding/codegen/[expression, blocks]

suite "Compiler: Lexer and Parser":
  test "lexes simple integer literal":
    let tokens = lex("42")
    check tokens.len >= 1
    check tokens[0].kind == tkInt

  test "lexes string literal":
    let tokens = lex("\"hello\"")
    check tokens.len >= 1
    check tokens[0].kind == tkString

  test "lexes triple-quoted multiline string literal":
    let expected = """line 1
He said "hello"
"two quotes" are fine
backslash-n: \n
"""
    let source = "\"\"\"" & expected & "\"\"\""
    let tokens = lex(source)
    check tokens.len >= 1
    check tokens[0].kind == tkString
    check tokens[0].value == expected

  test "lexes indentation-aware triple-quoted string literal":
    let source = "\"\"\"\n      alpha\n        beta\n      gamma\n    \"\"\""
    let tokens = lex(source)
    check tokens.len >= 1
    check tokens[0].kind == tkString
    check tokens[0].value == "alpha\n  beta\ngamma\n"

  test "lexes triple-quoted symbol string":
    let source = "#\"\"\"line 1\n  line 2 with \"quotes\"\n\"\"\""
    let tokens = lex(source)
    check tokens.len >= 1
    check tokens[0].kind == tkSymbol
    check tokens[0].value == "line 1\n  line 2 with \"quotes\"\n"

  test "lexes identifier":
    let tokens = lex("foo")
    check tokens.len >= 1
    check tokens[0].kind == tkIdent

  test "lexes message selector":
    let tokens = lex("at:put:")
    check tokens.len >= 1
    check tokens[0].kind == tkKeyword

suite "Compiler: Parser":
  test "parses integer literal":
    let tokens = lex("42")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkLiteral
    check nodes[0].LiteralNode.value.kind == vkInt

  test "parses string literal":
    let tokens = lex("\"hello\"")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkLiteral
    check nodes[0].LiteralNode.value.kind == vkString
    check nodes[0].LiteralNode.value.strVal == "hello"

  test "parses triple-quoted multiline string literal":
    let expected = """line 1
He said "hello"
"two quotes" are fine
backslash-n: \n
"""
    let source = "\"\"\"" & expected & "\"\"\""
    let tokens = lex(source)
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkLiteral
    check nodes[0].LiteralNode.value.kind == vkString
    check nodes[0].LiteralNode.value.strVal == expected

  test "parses indentation-aware triple-quoted string literal":
    let source = "\"\"\"\n      alpha\n        beta\n      gamma\n    \"\"\""
    let tokens = lex(source)
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkLiteral
    check nodes[0].LiteralNode.value.kind == vkString
    check nodes[0].LiteralNode.value.strVal == "alpha\n  beta\ngamma\n"

  test "parses triple-quoted symbol string literal":
    let source = "#\"\"\"line 1\n  line 2 with \"quotes\"\n\"\"\""
    let tokens = lex(source)
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkLiteral
    check nodes[0].LiteralNode.value.kind == vkSymbol
    check nodes[0].LiteralNode.value.symVal == "line 1\n  line 2 with \"quotes\"\n"

  test "triple-quoted multiline string keeps interpolation markers literally":
    let expected = """Hello #{name}
Value: #{1 + 2}
"""
    let source = "\"\"\"" & expected & "\"\"\""
    let tokens = lex(source)
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].LiteralNode.value.strVal == expected

  test "parses assignment":
    let tokens = lex("x := 10")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkAssign
    check nodes[0].AssignNode.variable == "x"

  test "parses unary message":
    let tokens = lex("foo size")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage
    check nodes[0].MessageNode.selector == "size"

  test "parses binary message":
    let tokens = lex("3 + 4")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage
    check nodes[0].MessageNode.selector == "+"

  test "parses keyword message":
    let tokens = lex("dict at: #key put: #value")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkMessage
    check nodes[0].MessageNode.selector == "at:put:"

  test "parses block literal":
    let tokens = lex("[x | x + 1]")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    check nodes.len == 1
    check nodes[0].kind == nkBlock

suite "Compiler: Context":
  test "creates compiler context":
    var ctx = newCompiler("./build", "test")
    check ctx.outputDir == "./build"
    check ctx.moduleName == "test"
    check ctx.classes.len == 0

  test "creates class info":
    let cls = newClassInfo("Point")
    check cls.name == "Point"
    check cls.parent == nil
    check cls.slots.len == 0

  test "adds slot to class":
    let cls = newClassInfo("Point")
    let idx = cls.addSlot("x", tcInt)
    check idx == 0
    check cls.slots.len == 1
    check cls.slots[0].name == "x"

  test "gets slot index":
    let cls = newClassInfo("Point")
    discard cls.addSlot("x", tcInt)
    discard cls.addSlot("y", tcInt)
    check cls.getSlotIndex("x") == 0
    check cls.getSlotIndex("y") == 1

suite "Compiler: Symbols":
  test "mangles selector for keyword":
    let m = mangleSelector("at:put:")
    check m.contains("nt_")
    check m.contains("at")
    check m.contains("put")

  test "mangles selector for binary operator":
    let m = mangleSelector("+")
    check m.contains("nt_")
    check m.contains("plus")

  test "mangles class name":
    let m = mangleClass("Point")
    check m.startsWith("Class_")
    check m.contains("Point")

  test "mangles slot name":
    let m = mangleSlot("x")
    check m == "x"

suite "Compiler: Analyzer":
  test "extracts derive chain from assignment":
    let tokens = lex("Point := Object derive: #(x, y)")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    
    let chain = extractDeriveChain(nodes[0])
    check chain[0] == "Point"
    check chain[1] == "Object"
    check chain[2] == "#(x, y)"

  test "builds class graph":
    let source = """
      Point := Object derive: #(x, y)
      Point3D := Point derive: #(z)
    """
    let tokens = lex(source)
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    
    let result = buildClassGraph(nodes)
    check len(result.classes) >= 2
    check "Point" in result.classes
    check "Point3D" in result.classes

  test "parses type list":
    let slots = parseTypeList("#(x:, Int, y:, Float, name)")
    check slots.len == 3
    check slots[0].name == "x"
    check slots[0].constraint == tcInt
    check slots[1].name == "y"
    check slots[1].constraint == tcFloat
    check slots[2].name == "name"
    check slots[2].constraint == tcNone

suite "Compiler: Codegen - Expression":
  test "generates integer literal":
    let ctx = newGenContext(nil)
    let node = LiteralNode(value: NodeValue(kind: vkInt, intVal: 42))
    let code = genLiteral(node)
    check code.contains("vkInt")
    check code.contains("42")

  test "generates string literal":
    let ctx = newGenContext(nil)
    let node = LiteralNode(value: NodeValue(kind: vkString, strVal: "hello"))
    let code = genLiteral(node)
    check code.contains("vkString")
    check code.contains("hello")

  test "generates nil literal":
    let ctx = newGenContext(nil)
    let node = LiteralNode(value: NodeValue(kind: vkNil))
    let code = genLiteral(node)
    check code.contains("vkNil")

suite "Compiler: Codegen - Blocks":
  test "creates block registry":
    let reg = newBlockRegistry()
    check reg.blocks.len == 0
    check reg.blockCounter == 0

  test "generates block name":
    let reg = newBlockRegistry()
    let name = reg.generateBlockName()
    check name.startsWith("harding_block_")

  test "analyzes block captures":
    let blockNode = BlockNode(
      parameters: @["x"],
      temporaries: @["temp"],
      body: @[Node(IdentNode(name: "counter"))]
    )
    let captures = analyzeCaptures(blockNode, @["global"])
    check "counter" in captures
    check "x" notin captures
    check "temp" notin captures

  test "registers block":
    let reg = newBlockRegistry()
    let blockNode = BlockNode(parameters: @["x"], body: @[])
    let info = registerBlock(reg, blockNode)
    
    check reg.blocks.len == 1
    check info.nimName.startsWith("harding_block_")
    check info.paramCount == 1

# Skip integration test for now - genModule has complex dependencies
# TODO: Re-enable after fixing test setup
# suite "Compiler: Integration":
#   test "round-trip: parse and generate module":
#     let source = "x := 10"
#     let tokens = lex(source)
#     var p = initParser(tokens)
#     let nodes = p.parseStatements()
#     
#     var ctx = newCompiler("./build", "test")
#     let nimCode = genModule(ctx, nodes, "test", false, "test.hrd")
#     
#     check nimCode.len > 0
#     check nimCode.contains("proc main")
#     check nimCode.contains("NodeValue")

# Note: Tests run via nimble test (uses testament), not unittest.main()
