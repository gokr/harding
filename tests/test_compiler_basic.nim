#!/usr/bin/env nim
#
# Basic compiler tests for Harding
# Tests parsing, code generation, and round-trip compilation

import std/[unittest, strutils, tables]
import ../src/harding/core/types
import ../src/harding/parser/[lexer, parser]
import ../src/harding/compiler/[context, types, analyzer]
import ../src/harding/compiler/symbols as symbols
import ../src/harding/codegen/[expression, blocks, module, numeric]

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
    let m = mangleClass("MyClass")
    check m.startsWith("Class_")
    check m != mangleClass("Myclass")
    check m != mangleClass("My_Class")
    check mangleClass("Point") == mangleClass("Point")
    check mangleClass("Point") != mangleClass("Point2")

  test "encodes Nim keywords and backend names without encoding collisions":
    check mangleIdentifier("object").startsWith("hardingUser")
    check mangleIdentifier("object") != mangleIdentifier("Object")
    check mangleIdentifier("result") != "result"
    check mangleIdentifier("args") != "args"
    check mangleIdentifier("envTyped") != "envTyped"
    check mangleIdentifier("hardingHome") != "hardingHome"
    check mangleIdentifier(mangleIdentifier("object")) != mangleIdentifier("object")
    check mangleIdentifier("ordinary") == "ordinary"
    check mangleSlot("type") == mangleIdentifier("type")

  test "distinct case and punctuation spellings remain distinct in Nim":
    proc nimKey(value: string): string = value.replace("_", "").toLowerAscii()
    check nimKey(mangleIdentifier("fooBar")) != nimKey(mangleIdentifier("foobar"))
    check nimKey(mangleIdentifier("foo_bar")) != nimKey(mangleIdentifier("foobar"))
    check nimKey(mangleSlot("slotValue")) != nimKey(mangleSlot("slotvalue"))
    check mangleSlot("a-b") != mangleSlot("a_b")

  test "method and block declarations use the same identifier encoding":
    let ctx = newGenContext()
    ctx.parameters.add("object")
    check genSymbolAccess(ctx, "object") == mangleIdentifier("object")
    let registry = newBlockRegistry()
    let info = registerBlock(registry, BlockNode(parameters: @["type"],
      body: @[Node(IdentNode(name: "object"))]))
    check generateEnvStructDef(info).contains(mangleIdentifier("object") & ": MutableCell")
    check generateBlockProcSignature(info).contains("hardingArg_" & mangleIdentifier("type"))

  test "mangles slot name":
    let m = mangleSlot("x")
    check m == "x"

  test "class and module names are unique under Nim style folding":
    proc nimKey(value: string): string = value.replace("_", "").toLowerAscii()
    check nimKey(mangleClass("FooBar")) != nimKey(mangleClass("Foobar"))
    check nimKey(mangleClass("MyClass")) != nimKey(mangleClass("My_Class"))
    check mangleClass("Point") == mangleClass("Point")
    check symbols.mangleModuleName("sieve") == "sieve"
    check symbols.mangleModuleName("my-prog") != symbols.mangleModuleName("myprog")
    check symbols.mangleModuleName("my-prog")[0] notin {'0'..'9'}
    check nimKey(symbols.mangleModuleName("MyProg")) != nimKey(symbols.mangleModuleName("myprog"))
    check symbols.mangleModuleName("2fast")[0] notin {'0'..'9'}

suite "Compiler: Analyzer":
  test "extracts derive chain from assignment":
    let tokens = lex("Point := Object derive: #(x, y)")
    var p = initParser(tokens)
    let nodes = p.parseStatements()
    
    let chain = extractDeriveChain(nodes[0])
    check chain[0] == "Point"
    check chain[1] == "Object"
    check chain[2] == "#(x y)"

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

suite "Compiler: Accessor Registration":
  test "selective accessor registration excludes private directions":
    var p = initParser(lex("Cell := Object derive: #(readOnly, writeOnly, hidden) read: #(readOnly) write: #(writeOnly)"))
    let analysis = buildClassGraph(p.parseStatements())
    let cls = analysis.classes["Cell"]
    check cls.getterSlots == @["readOnly"]
    check cls.setterSlots == @["writeOnly"]
    let registration = genSlotAccessorRegistrations(cls)
    check registration.contains("registerCompiledMethod(\"Cell\", \"readOnly\"")
    check registration.contains("registerCompiledMethod(\"Cell\", \"writeOnly:\"")
    check not registration.contains("registerCompiledMethod(\"Cell\", \"hidden\"")
    check not registration.contains("registerCompiledMethod(\"Cell\", \"readOnly:\"")
    check not registration.contains("registerCompiledMethod(\"Cell\", \"writeOnly\"")

  test "explicit methods suppress generated registrations":
    var p = initParser(lex("Cell := Object derivePublic: #(amount). Cell>>amount [ ^ 99 ]. Cell>>amount: n [ ^ n ]"))
    let analysis = buildClassGraph(p.parseStatements())
    let registration = genSlotAccessorRegistrations(analysis.classes["Cell"])
    check not registration.contains("registerCompiledMethod")

suite "Compiler: Codegen - Expression":
  test "generates integer literal":
    let node = LiteralNode(value: NodeValue(kind: vkInt, intVal: 42))
    let code = genLiteral(node)
    check code.contains("vkInt")
    check code.contains("42")

  test "generates string literal":
    let node = LiteralNode(value: NodeValue(kind: vkString, strVal: "hello"))
    let code = genLiteral(node)
    check code.contains("vkString")
    check code.contains("hello")

  test "generates nil literal":
    let node = LiteralNode(value: NodeValue(kind: vkNil))
    let code = genLiteral(node)
    check code.contains("vkNil")

suite "Compiler: System receiver":
  test "System is canonical unless shadowed by a lexical binding":
    let ctx = newGenContext()
    check genSymbolAccess(ctx, "System") == "compiledSystemClassValue()"
    ctx.locals.add("System")
    check genSymbolAccess(ctx, "System") == mangleIdentifier("System")

suite "Compiler: Script temporaries":
  test "script parsing preserves temporary names and source lines":
    var syntax = initParser(lex("# header\n| counter spare |\ncounter := 3. spare println."))
    let script = syntax.parseScript()
    check not syntax.hasError
    check script.temporaries == @["counter", "spare"]
    check script.body.len == 2
    var counterLine = 0
    for token in syntax.tokens:
      if token.kind == tkAssign:
        counterLine = token.line
        break
    check counterLine == 3
    var ctx = newCompiler()
    let code = genModule(ctx, script.body, "script_temps", scriptTemporaries = script.temporaries)
    check code.contains("var counter = NodeValue(kind: vkNil)")
    check code.contains("var spare = NodeValue(kind: vkNil)")
    check not code.contains("var counter = 3")

  test "main block declares temporaries before closure creation":
    let (nodes, _) = parse("Harding main: [ | total read | read := [total]. total := 42. read value println. ].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "main_temps")
    check code.contains("var total = MutableCell(value: NodeValue(kind: vkNil))")
    check code.contains("var " & mangleIdentifier("read") & " = NodeValue(kind: vkNil)")

  test "malformed script declarations report original source lines":
    var syntax = initParser(lex("# header\n| counter\ncounter := 3."))
    discard syntax.parseScript()
    check syntax.hasError
    check syntax.errorMsg.contains("line 3")

suite "Compiler: Engine binding shims":
  test "class and instance selectors generate distinct receiver-safe shims":
    let (nodes, syntax) = parse("ShimFactory := Object derive: #(). ShimFactory>>identity [ ^ self ]. ShimFactory class>>identity [ ^ self ].")
    require not syntax.hasError
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "shim_factory")
    let className = mangleClass("ShimFactory")
    let selectorName = mangleSelector("identity")
    check code.contains("proc shim_" & className & "_" & selectorName & "*(interp: var Interpreter, self: Instance,")
    check code.contains("proc shim_" & className & "_class_" & selectorName & "*(interp: var Interpreter, self: NodeValue,")
    check code.contains("isClassMethod = true)")
    check code.contains("isClassMethod = false)")
    check code.contains("proc bindCompiledMethodsTo*(interp: var Interpreter)")

suite "Compiler: Shared runtime support":
  test "generated modules import helpers instead of defining them":
    let (nodes, _) = parse("1 + 2.")
    var ctx = newCompiler("build/nested/output", "shared_support")
    let code = genModule(ctx, nodes, "shared_support")
    check code.contains("harding/runtime/compiled_support")
    check not code.contains("proc nt_plus*")
    check not code.contains("proc createBlock*")
    check not code.contains("CompiledReturnTarget* =")
    check not code.contains("HardingObject* ")
    check not code.contains("var globals*")
    check code.countLines < 70

suite "Compiler: Guarded default allocation":
  test "statically named classes use a guarded native allocation helper":
    let (nodes, _) = parse("Box := Object derive: #(). Box new.")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "guarded_allocation")
    check code.contains("discard guardedNew_" & mangleClass("Box") & "()")
    check code.contains("canDirectAllocate(\"Box\", allocate" & mangleClass("Box") & ")")
    check code.contains("allocationVersion_" & mangleClass("Box") & " != compiledClassDispatchVersion")
    check code.contains("return compiledNewInstance(\"Box\", allocate" & mangleClass("Box") & ")")
    check code.contains("return sendMessage(currentRuntime[], compiledClassValue(\"Box\"), \"new\", @[])")

  test "a locally shadowed class receiver stays on ordinary dispatch":
    let genCtx = newGenContext(compiledClasses = @["Box"])
    genCtx.parameters.add("Box")
    let send = MessageNode(receiver: IdentNode(name: "Box"), selector: "new")
    let code = genMessage(genCtx, send)
    check not code.contains("guardedNew_")
    check code.contains("sendMessage(currentRuntime[], " & mangleIdentifier("Box"))

suite "Compiler: Method return convention":
  test "implicit literal and empty methods answer self":
    let (nodes, _) = parse("ReturnRules := Object derive: #(). ReturnRules>>literal [42]. ReturnRules>>empty [].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "implicit_returns")
    check code.contains("discard NodeValue(kind: vkInt, intVal: 42)\n  return self")
    check code.contains("proc " & mangleClass("ReturnRules") & "_nt_empty*(self: NodeValue, args: seq[NodeValue]): NodeValue =\n  return self")

  test "class-side fallthrough also answers its receiver":
    let (nodes, _) = parse("ReturnRules := Object derive: #(). ReturnRules class>>empty [].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "class_return")
    check code.contains("proc " & mangleClass("ReturnRules") & "_class_nt_empty*(self: NodeValue, args: seq[NodeValue]): NodeValue =\n  return self")

  test "explicit return is not followed by an implicit return":
    let (nodes, _) = parse("ReturnRules := Object derive: #(). ReturnRules>>explicit [^ 42].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "explicit_return")
    check code.contains("return NodeValue(kind: vkInt, intVal: 42)")
    check not code.contains("return NodeValue(kind: vkInt, intVal: 42)\n  return self")

suite "Compiler: Cached ordinary sends":
  test "pure generic sends expand a per-site cache":
    let ctx = newGenContext()
    ctx.locals.add("receiver")
    let send = MessageNode(receiver: IdentNode(name: "receiver"), selector: "answer")
    check genMessage(ctx, send).contains("cachedSend(currentRuntime[], receiver")
    ctx.mixed = true
    check genMessage(ctx, send).contains("sendMessageHybrid(receiver")
    check not genMessage(ctx, send).contains("cachedSend")

suite "Compiler: Conservative numeric representations":
  test "method temporaries unbox while arguments and slots remain dynamic":
    let (nodes, _) = parse("Counter := Object derive: #(slot). Counter>>sum: limit [ | total k | total := 0. k := 0. [k < limit] whileTrue: [total := total + k. k := k + 1]. ^ total ].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "numeric_method")
    check code.contains("var total = 0")
    check code.contains("var k = 0")
    check code.contains("intVal: (total + k)")
    check code.contains("var limit = (if args.len > 0: args[0]")
    check not code.contains("var total = NodeValue")

  test "mixed-mode methods retain boxed temporaries":
    let (nodes, _) = parse("Counter := Object derive: #(). Counter>>probe [ | k | k := 0. k := k + 1. ^ k ].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "numeric_mixed", mixed = true)
    check code.contains("var k = NodeValue(kind: vkNil)")
    check not code.contains("intVal: (k + 1)")

  test "method temporary reads before initialization preserve nil":
    let (nodes, _) = parse("Counter := Object derive: #(). Counter>>probe [ | count | count println. count := 1. ^ count ].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "numeric_early_read")
    check code.contains("var " & mangleIdentifier("count") & " = NodeValue(kind: vkNil)")

  test "slot dependencies cannot be mistaken for native lexical variables":
    let (nodes, _) = parse("slot := 1. k := 0. k := k + slot.")
    let bindings = analyzeNumericBindings(nodes, @[], @["k"])
    check "slot" notin bindings
    check "k" notin bindings

  test "method captures, type changes and lexical slot names remain dynamic":
    let (nodes, _) = parse("Counter := Object derive: #(amount). Counter>>probe [ | count | count := 0. callback := [count := count + 1]. amount := 3. ^ callback ].")
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "numeric_capture")
    check code.contains("var " & mangleIdentifier("count") & " = MutableCell")
    check not code.contains("var amount = 0")


  test "monomorphic initialized script locals become native numbers":
    let (nodes, _) = parse("total := 0. i := 0. [i < 10] whileTrue: [total := total + i. i := i + 1]. total println.")
    let bindings = analyzeNumericBindings(nodes, @[])
    check bindings.getOrDefault("total") == nrInt
    check bindings.getOrDefault("i") == nrInt
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "native_numbers")
    check code.contains("intVal: (total + i)")
    check not code.contains("nt_plus(total")

  test "type changes and dependencies fall back to dynamic":
    let (nodes, _) = parse("a := 1. b := 2. a := 1.5. b := b + a.")
    let bindings = analyzeNumericBindings(nodes, @[])
    check "a" notin bindings
    check "b" notin bindings

  test "captured and shadowed variables remain dynamic":
    let (nodes, _) = parse("x := 1. y := 2. blk := [:y | y + 1].")
    let bindings = analyzeNumericBindings(nodes, @["x"])
    check "x" notin bindings
    check "y" notin bindings

  test "conditional initialization cannot replace nil with zero":
    let (nodes, _) = parse("x println. x := 1.")
    check "x" notin analyzeNumericBindings(nodes, @[])
    let (conditional, _) = parse("false ifTrue: [x := 2]. x println. x := 1.")
    check "x" notin analyzeNumericBindings(conditional, @[])

  test "real closures and unknown block consumers disable local unboxing":
    let (nodes, _) = parse("x := 1. callback := [x := 2].")
    check "x" notin analyzeNumericBindings(nodes, @[])
    let (unknown, _) = parse("x := 1. Object new use: [x := 2].")
    check "x" notin analyzeNumericBindings(unknown, @[])

  test "division remains on the existing runtime path":
    let (nodes, _) = parse("x := 1. x := x // 0.")
    check "x" notin analyzeNumericBindings(nodes, @[])

  test "literal arithmetic is not folded into compile-time overflow":
    let (nodes, _) = parse("9223372036854775807 + 1")
    check numericKind(nodes[0], initTable[string, NumericRepresentation]()) == nrDynamic

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

  test "captures references through specialized control flow":
    let condition = IdentNode(name: "ready")
    let readValue = IdentNode(name: "value")
    let access = NamedAccessNode(receiver: readValue, memberName: "field")
    let branch = BlockNode(body: @[Node(access)])
    let conditional = IfNode(condition: condition, thenBranch: branch)
    let loop = WhileNode(condition: condition, body: BlockNode(body: @[Node(conditional)]))
    let captures = analyzeCaptures(BlockNode(body: @[Node(loop)]))
    check "ready" in captures
    check "value" in captures

  test "specialized literal control flow does not allocate capture cells":
    let value = IdentNode(name: "value")
    let branch = BlockNode(body: @[Node(value)])
    let conditional = IfNode(condition: LiteralNode(value: NodeValue(kind: vkBool, boolVal: true)),
                             thenBranch: branch)
    let loop = WhileNode(condition: branch, body: BlockNode(body: @[Node(conditional)]))
    let registry = newBlockRegistry()
    collectBlocks(registry, loop)
    check registry.blocks.len == 0
    check scopeCaptureCellNames(@[Node(loop)]).len == 0

    var p = initParser(lex("Counter := Object derive: #(). Counter>>sum: n [ | total k | total := 0. k := 0. [k < n] whileTrue: [total := total + k. k := k + 1]. ^ total ]."))
    var ctx = newCompiler()
    let code = genModule(ctx, p.parseStatements(), "inline_counter")
    check not code.contains("var total = MutableCell")
    check not code.contains("var k = MutableCell")
    check not code.contains("var n = MutableCell")
    check not code.contains("let hardingHome =")

  test "escaping closures nested in inline branches still share cells":
    let value = IdentNode(name: "value")
    let escaping = BlockNode(body: @[Node(value)])
    let branch = BlockNode(body: @[Node(escaping)])
    let conditional = IfNode(condition: LiteralNode(value: NodeValue(kind: vkBool, boolVal: true)),
                             thenBranch: branch)
    let registry = newBlockRegistry()
    collectBlocks(registry, conditional)
    check registry.blocks.len == 1
    check registry.blocks[0].blockNode == escaping
    check "value" in scopeCaptureCellNames(@[Node(conditional)])

  test "non-local returning branches retain real block environments":
    let value = IdentNode(name: "value")
    let branch = BlockNode(body: @[Node(ReturnNode(expression: value))])
    let conditional = IfNode(condition: LiteralNode(value: NodeValue(kind: vkBool, boolVal: true)),
                             thenBranch: branch)
    let registry = newBlockRegistry()
    collectBlocks(registry, conditional)
    check registry.blocks.len == 1
    check "value" in registry.blocks[0].captures

  test "write-only enclosing temporaries share their binding":
    let assignment = AssignNode(variable: "value", expression: LiteralNode(value: nilValue()))
    let captures = analyzeCaptures(BlockNode(body: @[Node(assignment)]), @[], @[], @["value"])
    check "value" in captures
    check "value" in scopeCaptureCellNames(@[Node(BlockNode(body: @[Node(assignment)]))], @["value"])

  test "native instance wrappers retain their storage":
    var p = initParser(lex("Box := Object derivePublic: #(item)."))
    var ctx = newCompiler()
    let code = genModule(ctx, p.parseStatements(), "owned_storage")
    check code.contains(mangleClass("Box") & "Obj* {.inheritable.} = object of HardingObject")
    check code.contains("compiledOwner: self")
    check code.contains("inst.nimValue = cast[pointer](self)")

  test "method-owned blocks retain home even without variable captures":
    let reg = newBlockRegistry()
    var info = registerBlock(reg, BlockNode(body: @[]))
    info.ownerMethodId = 1000
    check generateEnvStructDef(info).contains("home: CompiledReturnTarget")
    check generateBlockProcSignature(info).contains("env: pointer")

  test "method boundary compares activation identity and invalidates target":
    var p = initParser(lex("Returner := Object derive: #(). Returner>>run [ | blk | blk := [^ 42]. ^ blk value ]"))
    let nodes = p.parseStatements()
    var ctx = newCompiler()
    let code = genModule(ctx, nodes, "return_target")
    check code.contains("CompiledReturnTarget(active: true)")
    check code.contains("if nlr.target == hardingHome:")
    check code.contains("hardingHome.active = false")
    check code.contains("raiseNonLocalReturn(hardingHome,")
    check not code.contains("targetId")

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
