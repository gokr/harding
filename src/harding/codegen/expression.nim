import std/[strutils, sequtils, strformat, sets, tables]
import ../core/types
import ../compiler/context
import ../compiler/symbols
import ./blocks

# ============================================================================
# Expression Code Generation
# Generates Nim code from AST expressions
# ============================================================================

type
  GenContext* = ref object
    cls*: ClassInfo
    inBlock*: bool
    mixed*: bool                   ## Mixed mode: embed interpreter for fallback
    locals*: seq[string]          ## Local variable names (temporaries)
    parameters*: seq[string]      ## Parameter names
    globals*: seq[string]         ## Known global variable names
    blockRegistry*: BlockRegistry ## Registry for blocks to compile
    variableTypes*: Table[string, string]  ## Variable name -> class name (for native type optimization)
    classRegistry*: TableRef[string, ClassInfo]  ## Reference to class registry for slot lookup

# Forward declaration
proc genExpression*(ctx: GenContext, node: Node): string
proc genStatement*(ctx: GenContext, node: Node): string

proc newGenContext*(cls: ClassInfo = nil, mixed: bool = false, classRegistry: TableRef[string, ClassInfo] = nil): GenContext =
  ## Create new generation context
  result = GenContext(
    cls: cls,
    inBlock: false,
    mixed: mixed,
    locals: @[],
    parameters: @[],
    globals: @[],
    blockRegistry: newBlockRegistry(),
    variableTypes: initTable[string, string](),
    classRegistry: classRegistry
  )

proc indentBlock*(code: string, spaces: int = 2): string =
  ## Indent each non-empty line of multi-line code by the given number of spaces
  let prefix = " ".repeat(spaces)
  for line in code.splitLines():
    if line.len > 0:
      result.add(prefix & line & "\n")

proc isLocal*(ctx: GenContext, name: string): bool =
  ## Check if name is a local variable or parameter
  return name in ctx.locals or name in ctx.parameters

proc isSlot*(ctx: GenContext, name: string): bool =
  ## Check if name is a slot in the current class
  if ctx.cls == nil:
    return false
  return ctx.cls.getSlotIndex(name) >= 0

proc getSlotIndex*(ctx: GenContext, name: string): int =
  ## Get slot index for name, returns -1 if not a slot
  if ctx.cls == nil:
    return -1
  return ctx.cls.getSlotIndex(name)

proc escapeNimString*(s: string): string =
  ## Escape a string for use in Nim code
  ## Handles backslashes, quotes, and other special characters
  result = s
  # Escape backslashes first (before we add new ones)
  result = result.replace("\\", "\\\\")
  # Escape double quotes
  result = result.replace("\"", "\\\"")
  # Escape newlines
  result = result.replace("\n", "\\n")
  # Escape carriage returns
  result = result.replace("\r", "\\r")
  # Escape tabs
  result = result.replace("\t", "\\t")

proc genLiteral*(node: LiteralNode): string =
  ## Generate code for literal node
  let value = node.value
  case value.kind
  of vkInt:
    return fmt("NodeValue(kind: vkInt, intVal: {value.intVal})")
  of vkFloat:
    return fmt("NodeValue(kind: vkFloat, floatVal: {value.floatVal})")
  of vkString:
    let escaped = escapeNimString(value.strVal)
    return fmt("NodeValue(kind: vkString, strVal: \"{escaped}\")")
  of vkSymbol:
    # Symbols need runtime lookup
    let escaped = escapeNimString(value.symVal)
    return fmt("NodeValue(kind: vkSymbol, symVal: \"{escaped}\")")
  of vkBool:
    return fmt("NodeValue(kind: vkBool, boolVal: {value.boolVal})")
  of vkNil:
    return "NodeValue(kind: vkNil)"
  of vkInstance:
    return "self.toValue()"
  else:
    return "NodeValue(kind: vkNil)"

proc genSymbolAccess*(ctx: GenContext, name: string): string =
  ## Generate code for symbol/variable access
  ## Priority: parameters > locals > slots > globals

  if name == "self":
    return "self.toValue()"

  if name == "nil":
    return "NodeValue(kind: vkNil)"

  if name == "true":
    return "NodeValue(kind: vkBool, boolVal: true)"

  if name == "false":
    return "NodeValue(kind: vkBool, boolVal: false)"

  # Check if it's a parameter
  if name in ctx.parameters:
    return name

  # Check if it's a local variable
  if name in ctx.locals:
    return name

  # Check if it's a slot
  if ctx.cls != nil:
    let slotIdx = ctx.cls.getSlotIndex(name)
    if slotIdx >= 0:
      return fmt("self.slots[{slotIdx}]")

  # Check if it's a known global (class or global variable)
  if name in ctx.globals:
    # Globals are stored in a globals table
    return fmt("getGlobal(\"{name}\")")

  # Fallback: treat as symbol
  return fmt("NodeValue(kind: vkSymbol, symVal: \"{name}\")")

proc genMessage*(ctx: GenContext, node: MessageNode): string =
  ## Generate code for message send

  # Generate receiver
  var receiverCode: string
  if node.receiver != nil:
    receiverCode = genExpression(ctx, node.receiver)
  else:
    receiverCode = "self.toValue()"

  # Check for inline control flow with literal blocks
  case node.selector
  of "ifTrue:ifFalse:":
    # Inline if/else when both blocks are literals
    if node.arguments.len >= 2 and
       node.arguments[0].kind == nkBlock and
       node.arguments[1].kind == nkBlock:
      let thenBlock = node.arguments[0].BlockNode
      let elseBlock = node.arguments[1].BlockNode
      var code = "(if isTruthy(" & receiverCode & "):\n"
      # Generate then block body - last expression is the value
      for i, stmt in thenBlock.body:
        if i == thenBlock.body.len - 1:
          code.add("      " & genExpression(ctx, stmt) & "\n")
        else:
          code.add("      " & genStatement(ctx, stmt) & "\n")
      code.add("    else:\n")
      # Generate else block body
      for i, stmt in elseBlock.body:
        if i == elseBlock.body.len - 1:
          code.add("      " & genExpression(ctx, stmt) & "\n")
        else:
          code.add("      " & genStatement(ctx, stmt) & "\n")
      code.add("  )")
      return code

  of "ifTrue:":
    # Inline if when block is literal
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let thenBlock = node.arguments[0].BlockNode
      var code = "(if isTruthy(" & receiverCode & "):\n"
      for i, stmt in thenBlock.body:
        if i == thenBlock.body.len - 1:
          code.add("      " & genExpression(ctx, stmt) & "\n")
        else:
          code.add("      " & genStatement(ctx, stmt) & "\n")
      code.add("    else:\n")
      code.add("      nilValue()\n")
      code.add("  )")
      return code

  of "ifFalse:":
    # Inline ifFalse when block is literal
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let thenBlock = node.arguments[0].BlockNode
      var code = "(if not isTruthy(" & receiverCode & "):\n"
      for i, stmt in thenBlock.body:
        if i == thenBlock.body.len - 1:
          code.add("      " & genExpression(ctx, stmt) & "\n")
        else:
          code.add("      " & genStatement(ctx, stmt) & "\n")
      code.add("    else:\n")
      code.add("      nilValue()\n")
      code.add("  )")
      return code

  of "whileTrue:":
    # Inline whileTrue when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let bodyBlock = node.arguments[0].BlockNode
      var condCode = receiverCode
      if node.receiver != nil and node.receiver.kind == nkBlock:
        let condBlock = node.receiver.BlockNode
        if condBlock.body.len > 0:
          condCode = genExpression(ctx, condBlock.body[condBlock.body.len - 1])
      var code = "(block:\n"
      code.add("    while isTruthy(" & condCode & "):\n")
      for stmt in bodyBlock.body:
        let stmtCode = genStatement(ctx, stmt)
        code.add(indentBlock(stmtCode, 6))
      code.add("    nilValue())")
      return code

  of "whileFalse:":
    # Inline whileFalse when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let bodyBlock = node.arguments[0].BlockNode
      var condCode = receiverCode
      if node.receiver != nil and node.receiver.kind == nkBlock:
        let condBlock = node.receiver.BlockNode
        if condBlock.body.len > 0:
          condCode = genExpression(ctx, condBlock.body[condBlock.body.len - 1])
      var code = "(block:\n"
      code.add("    while not isTruthy(" & condCode & "):\n")
      for stmt in bodyBlock.body:
        let stmtCode = genStatement(ctx, stmt)
        code.add(indentBlock(stmtCode, 6))
      code.add("    nilValue())")
      return code

  of "do:":
    # Inline do: for Arrays when block is literal
    # Compiles to: for i, elem in arr.arrayVal: block(elem)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let bodyBlock = node.arguments[0].BlockNode
      if bodyBlock.parameters.len >= 1:
        let elemName = bodyBlock.parameters[0]
        # Create a new context with the loop variable as a local
        var doCtx = GenContext(
          cls: ctx.cls,
          inBlock: ctx.inBlock,
          mixed: ctx.mixed,
          locals: ctx.locals & @[elemName],
          parameters: ctx.parameters,
          globals: ctx.globals,
          blockRegistry: ctx.blockRegistry
        )
        var code = "(block:\n"
        code.add("    for hardingDoIdx, " & elemName & " in " & receiverCode & ".arrayVal:\n")
        for stmt in bodyBlock.body:
          let stmtCode = genStatement(doCtx, stmt)
          code.add(indentBlock(stmtCode, 6))
        code.add("    nilValue())")
        return code

  of "collect:":
    # Inline collect: for Arrays when block is literal
    # Compiles to: result = @[]; for elem in arr: result.add(block(elem)); return result
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let bodyBlock = node.arguments[0].BlockNode
      if bodyBlock.parameters.len >= 1:
        let elemName = bodyBlock.parameters[0]
        # Create a new context with the loop variable as a local
        var collectCtx = GenContext(
          cls: ctx.cls,
          inBlock: ctx.inBlock,
          mixed: ctx.mixed,
          locals: ctx.locals & @[elemName],
          parameters: ctx.parameters,
          globals: ctx.globals,
          blockRegistry: ctx.blockRegistry
        )
        var code = "(block:\n"
        code.add("    var hardingCollectResult: seq[NodeValue] = @[]\n")
        code.add("    for hardingCollectIdx, " & elemName & " in " & receiverCode & ".arrayVal:\n")
        # Generate all statements except the last one
        for i in 0..<bodyBlock.body.len-1:
          let stmtCode = genStatement(collectCtx, bodyBlock.body[i])
          code.add(indentBlock(stmtCode, 6))
        # The last statement's value is what we collect
        if bodyBlock.body.len > 0:
          let lastStmt = bodyBlock.body[^1]
          let valueCode = genExpression(collectCtx, lastStmt)
          code.add("      hardingCollectResult.add(" & valueCode & ")\n")
        code.add("    NodeValue(kind: vkArray, arrayVal: hardingCollectResult))")
        return code

  of "select:":
    # Inline select: for Arrays when block is literal
    # Compiles to: result = @[]; for elem in arr: if block(elem): result.add(elem); return result
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let bodyBlock = node.arguments[0].BlockNode
      if bodyBlock.parameters.len >= 1:
        let elemName = bodyBlock.parameters[0]
        # Create a new context with the loop variable as a local
        var selectCtx = GenContext(
          cls: ctx.cls,
          inBlock: ctx.inBlock,
          mixed: ctx.mixed,
          locals: ctx.locals & @[elemName],
          parameters: ctx.parameters,
          globals: ctx.globals,
          blockRegistry: ctx.blockRegistry
        )
        var code = "(block:\n"
        code.add("    var hardingSelectResult: seq[NodeValue] = @[]\n")
        code.add("    for hardingSelectIdx, " & elemName & " in " & receiverCode & ".arrayVal:\n")
        # Generate the block body to get the condition value
        var bodyCode = ""
        for stmt in bodyBlock.body:
          let stmtCode = genStatement(selectCtx, stmt)
          if stmtCode.len > 0:
            bodyCode.add(stmtCode)
            bodyCode.add("\n")
        if bodyCode.len > 0:
          code.add("      if isTruthy(")
          # For simple expressions, use the last statement's expression
          # For now, assume the last statement is the condition
          let lastStmt = bodyBlock.body[^1]
          let condCode = genExpression(selectCtx, lastStmt)
          code.add(condCode)
          code.add("):\n")
          code.add("        hardingSelectResult.add(" & elemName & ")\n")
        code.add("    NodeValue(kind: vkArray, arrayVal: hardingSelectResult))")
        return code

  of "timesRepeat:":
    # Inline timesRepeat when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock:
      let bodyBlock = node.arguments[0].BlockNode
      var code = "(block:\n"
      code.add("    let count = toInt(" & receiverCode & ")\n")
      code.add("    for timesRepeatI in 0..<count:\n")
      for stmt in bodyBlock.body:
        let stmtCode = genStatement(ctx, stmt)
        code.add(indentBlock(stmtCode, 6))
      code.add("    nilValue())")
      return code

  of "to:by:do:":
    # Inline to:by:do: when body is a literal block (expression context - needs value)
    if node.arguments.len >= 3 and node.arguments[2].kind == nkBlock:
      let endVal = genExpression(ctx, node.arguments[0])
      let stepVal = genExpression(ctx, node.arguments[1])
      let bodyBlock = node.arguments[2].BlockNode
      var code = "(block:\n"
      code.add("    var current = toInt(" & receiverCode & ")\n")
      code.add("    let endNum = toInt(" & endVal & ")\n")
      code.add("    let step = toInt(" & stepVal & ")\n")
      code.add("    if step > 0:\n")
      code.add("      while current <= endNum:\n")
      for stmt in bodyBlock.body:
        let stmtCode = genStatement(ctx, stmt)
        code.add(indentBlock(stmtCode, 8))
      code.add("        current += step\n")
      code.add("    else:\n")
      code.add("      while current >= endNum:\n")
      for stmt in bodyBlock.body:
        let stmtCode = genStatement(ctx, stmt)
        code.add(indentBlock(stmtCode, 8))
      code.add("        current += step\n")
      code.add("    nilValue())")
      return code

  case node.selector
  of "+", "-", "*", "/":
    # Binary operators - these are generated as function calls
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("{mangleSelector(node.selector)}({receiverCode}, {argCode})")
    return receiverCode

  of "<", "<=", ">", ">=", "=", "==", "~=":
    # Comparison operators
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("{mangleSelector(node.selector)}({receiverCode}, {argCode})")
    return receiverCode

  of "//", "\\", "%":
    # Integer division and modulo
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("{mangleSelector(node.selector)}({receiverCode}, {argCode})")
    return receiverCode

  of "at:":
    # Slot access or collection access
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("{mangleSelector(node.selector)}({receiverCode}, {argCode})")
    return receiverCode

  of "at:put:":
    # Slot/collection assignment
    if node.arguments.len >= 2:
      let keyCode = genExpression(ctx, node.arguments[0])
      let valCode = genExpression(ctx, node.arguments[1])
      return fmt("{mangleSelector(node.selector)}({receiverCode}, {keyCode}, {valCode})")
    return receiverCode

  of "println", "writeLine:":
    # Print with newline - generates a statement, not an expression
    # This is a limitation - we need statement context for echo
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("nt_println({argCode})")
    else:
      return fmt("nt_println({receiverCode})")

  of "print", "write:":
    # Print without newline
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("nt_print({argCode})")
    else:
      return fmt("nt_print({receiverCode})")

  of "asString":
    # Convert to string
    return fmt("nt_asString({receiverCode})")

  of ",":
    # String concatenation
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("nt_comma({receiverCode}, {argCode})")
    return receiverCode

  of "size":
    # Array/Table size
    return fmt("nt_size({receiverCode})")

  of "last":
    # Array last element
    return fmt("nt_last({receiverCode})")

  of "keys":
    # Table keys
    return fmt("nt_table_keys({receiverCode})")

  of "abs":
    # Absolute value
    return fmt("nt_abs({receiverCode})")

  of "even":
    # Is even
    return fmt("nt_even({receiverCode})")

  of "odd":
    # Is odd
    return fmt("nt_odd({receiverCode})")

  of "negated":
    # Negated value
    return fmt("nt_negated({receiverCode})")

  of "new":
    # Constructor call - check if we can use native constructor
    var className = ""
    if node.receiver != nil and node.receiver.kind == nkIdent:
      className = node.receiver.IdentNode.name
    elif node.receiver != nil and node.receiver.kind == nkLiteral:
      let lit = node.receiver.LiteralNode
      if lit.value.kind == vkSymbol:
        className = lit.value.symVal
    # Use native constructor if we found a class name
    if className.len > 0:
      let mangleClass = "Class_" & className
      return fmt("new{mangleClass}()")
    # Fall back to sendMessage
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    if ctx.mixed:
      return fmt("sendMessageHybrid({receiverCode}, \"{node.selector}\", @[{args}])")
    else:
      return fmt("sendMessage(currentRuntime[], {receiverCode}, \"{node.selector}\", @[{args}])")

  of "derive:", "derive", "selector:put:", "classSelector:put:":
    # Class-related messages - need runtime dispatch
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    if ctx.mixed:
      return fmt("sendMessageHybrid({receiverCode}, \"{node.selector}\", @[{args}])")
    else:
      return fmt("sendMessage(currentRuntime[], {receiverCode}, \"{node.selector}\", @[{args}])")

  else:
    # Check for native slot access optimization (when we have variable type info)
    var isSlotAccess = false
    if node.receiver != nil and node.receiver.kind == nkIdent:
      let varName = node.receiver.IdentNode.name
      if varName in ctx.variableTypes:
        let className = ctx.variableTypes[varName]
        if ctx.classRegistry != nil and className in ctx.classRegistry:
          let cls = ctx.classRegistry[className]
          let slotName = node.selector
          let isSetter = slotName.endsWith(":")
          let accessorName = if isSetter: slotName[0..^2] else: slotName
          if cls.getSlotIndex(accessorName) >= 0:
            isSlotAccess = true
            let mangleSlot = accessorName.toLowerAscii()
            if isSetter:
              if node.arguments.len >= 1:
                let argCode = genExpression(ctx, node.arguments[0])
                return fmt("(set{mangleSlot}({receiverCode}, {argCode}); NodeValue(kind: vkNil))")
            else:
              return fmt("get{mangleSlot}({receiverCode})")

    # For non-slot methods, use sendMessage
    var effectiveReceiver = receiverCode

    # For non-slot methods on typed variables, convert using toValue()
    if not isSlotAccess and node.receiver != nil and node.receiver.kind == nkIdent:
      let varName = node.receiver.IdentNode.name
      if varName in ctx.variableTypes:
        # Convert native type to NodeValue using toValue()
        effectiveReceiver = fmt("{receiverCode}.toValue()")

    # Generic message dispatch via sendMessage
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    if ctx.mixed:
      return fmt("sendMessageHybrid({effectiveReceiver}, \"{node.selector}\", @[{args}])")
    else:
      return fmt("sendMessage(currentRuntime[], {effectiveReceiver}, \"{node.selector}\", @[{args}])")

proc genExpression*(ctx: GenContext, node: Node): string =
  ## Dispatch to appropriate expression generator

  if node == nil:
    return "NodeValue(kind: vkNil)"

  case node.kind
  of nkLiteral:
    return genLiteral(node.LiteralNode)

  of nkIdent:
    return genSymbolAccess(ctx, node.IdentNode.name)

  of nkMessage:
    return genMessage(ctx, node.MessageNode)

  of nkAssign:
    let assign = node.AssignNode
    let varName = assign.variable
    let exprCode = genExpression(ctx, assign.expression)

    # Track variable type for native optimization
    # Pattern 1: varName := ClassName new (nkMessage with Ident or Symbol receiver)
    if assign.expression != nil and assign.expression.kind == nkMessage:
      let msg = assign.expression.MessageNode
      if msg.selector == "new" and msg.receiver != nil:
        if msg.receiver.kind == nkIdent:
          let className = msg.receiver.IdentNode.name
          echo "DEBUG TRACK: Pattern1 Ident: var=\"", varName, "\" class=\"", className, "\""
          ctx.variableTypes[varName] = className
        elif msg.receiver.kind == nkLiteral:
          let lit = msg.receiver.LiteralNode
          if lit.value.kind == vkSymbol:
            let className = lit.value.symVal
            echo "DEBUG TRACK: Pattern1 Literal: var=\"", varName, "\" class=\"", className, "\""
            ctx.variableTypes[varName] = className
    # Pattern 2: Native constructor (exprCode starts with newClass_)
    if exprCode.startsWith("newClass_"):
      let className = exprCode[7..<exprCode.find("(")]
      echo "DEBUG TRACK: Pattern2: var=\"", varName, "\" class=\"", className, "\""
      ctx.variableTypes[varName] = className

    # Check if variable is a slot
    if ctx.isSlot(varName):
      let idx = ctx.getSlotIndex(varName)
      return fmt("(proc(): NodeValue = self.slots[{idx}] = {exprCode}; return {exprCode})()")

    # Check if it's a local variable (reassignment)
    if ctx.isLocal(varName):
      return fmt"{varName} = {exprCode}"

    # New local variable assignment
    ctx.locals.add(varName)
    return fmt"var {varName} = {exprCode}"

  of nkReturn:
    let ret = node.ReturnNode
    if ret.expression != nil:
      return "return " & genExpression(ctx, ret.expression)
    return "return self.toValue()"

  of nkArray:
    let arr = node.ArrayNode
    let elems = arr.elements.mapIt(genExpression(ctx, it)).join(", ")
    return fmt("NodeValue(kind: vkArray, arrayVal: @[{elems}])")

  of nkTable:
    let tbl = node.TableNode
    var entries: seq[string] = @[]
    for (key, val) in tbl.entries:
      let keyCode = genExpression(ctx, key)
      let valCode = genExpression(ctx, val)
      entries.add(fmt("{keyCode}: {valCode}"))
    return fmt("NodeValue(kind: vkTable, tableVal: {{{entries.join(\", \")}}})")

  of nkIf:
    ## Inline ifTrue:/ifFalse: control flow as expression
    ## Note: This should ideally not be called - nkIf should be handled in statement context
    ## But if it is, generate an expression that returns nil in both branches
    let ifNode = node.IfNode
    let condCode = genExpression(ctx, ifNode.condition)
    var code = "(if isTruthy(" & condCode & "):\n"
    # Generate then branch returning nil
    code.add("  NodeValue(kind: vkNil)\n")
    # Generate else branch if present
    if ifNode.elseBranch != nil:
      code.add("else:\n")
      code.add("  NodeValue(kind: vkNil))")
    else:
      code.add("else:\n")
      code.add("  NodeValue(kind: vkNil))")
    return code

  of nkBlock:
    ## Look up or register the block for compilation and return creation code
    let blockNode = node.BlockNode
    let existingIdx = ctx.blockRegistry.findBlock(blockNode)
    let blockInfo = if existingIdx >= 0:
                      ctx.blockRegistry.blocks[existingIdx]
                    else:
                      registerBlock(ctx.blockRegistry, blockNode, ctx.globals)

    # Determine which createBlock template to use based on captures and param count
    let hasEnv = blockInfo.captures.len > 0
    let paramCount = blockInfo.paramCount
    
    # Build template name: createBlock or createBlockEnv + param count
    var createBlockCall: string
    if hasEnv:
      createBlockCall = fmt("createBlockEnv{paramCount}({blockInfo.nimName}, {paramCount}, cast[pointer](addr {blockInfo.envStructName}_inst))")
    else:
      createBlockCall = fmt("createBlock{paramCount}({blockInfo.nimName}, {paramCount})")
    
    if hasEnv:
      # Create environment struct with captured values and pass to createBlock
      var initFields: seq[string] = @[]
      for capture in blockInfo.captures:
        initFields.add(fmt("{capture}: {genSymbolAccess(ctx, capture)}"))
      let envInit = fmt("var {blockInfo.envStructName}_inst = {blockInfo.envStructName}({initFields.join(\", \")})")
      # Wrap in a statement list expression to declare the env var and create the block
      return fmt("({envInit}; {createBlockCall})")
    else:
      return createBlockCall

  of nkPseudoVar:
    return genSymbolAccess(ctx, node.PseudoVarNode.name)

  of nkPrimitive:
    # Primitives are handled separately
    return "NodeValue(kind: vkNil)"

  of nkPrimitiveCall:
    # Primitive calls need runtime support
    let primCall = node.PrimitiveCallNode
    let args = primCall.arguments.mapIt(genExpression(ctx, it)).join(", ")
    return fmt("callPrimitive(\"{primCall.selector}\", @[{args}])")

  of nkSlotAccess:
    let slotNode = node.SlotAccessNode
    if slotNode.isAssignment and slotNode.valueExpr != nil:
      let valCode = genExpression(ctx, slotNode.valueExpr)
      return fmt("(proc(): NodeValue = self.slots[{slotNode.slotIndex}] = {valCode}; return {valCode})()")
    else:
      return fmt("self.slots[{slotNode.slotIndex}]")

  else:
    return "NodeValue(kind: vkNil)"

proc genStatement*(ctx: GenContext, node: Node): string =
  ## Generate code for a statement (not an expression - no result assignment)
  ## This is used for statements inside blocks/methods

  if node == nil:
    return ""

  case node.kind
  of nkAssign:
    let assign = node.AssignNode
    let varName = assign.variable
    let exprCode = genExpression(ctx, assign.expression)

    # Check if variable is a slot
    if ctx.isSlot(varName):
      let idx = ctx.getSlotIndex(varName)
      return fmt"self.slots[{idx}] = {exprCode}"

    # Check if it's a local variable (reassignment)
    if ctx.isLocal(varName):
      return fmt"{varName} = {exprCode}"

    # New local variable assignment
    ctx.locals.add(varName)
    return fmt"var {varName} = {exprCode}"

  of nkReturn:
    let ret = node.ReturnNode
    if ret.expression != nil:
      return "return " & genExpression(ctx, ret.expression)
    return "return self.toValue()"

  of nkMessage:
    let msg = node.MessageNode
    # Inline control flow in statement context (no value needed)
    case msg.selector
    of "whileTrue:":
      if msg.arguments.len >= 1 and msg.arguments[0].kind == nkBlock:
        let bodyBlock = msg.arguments[0].BlockNode
        var condCode: string
        if msg.receiver != nil and msg.receiver.kind == nkBlock:
          let condBlock = msg.receiver.BlockNode
          if condBlock.body.len > 0:
            condCode = genExpression(ctx, condBlock.body[condBlock.body.len - 1])
          else:
            condCode = "NodeValue(kind: vkBool, boolVal: true)"
        else:
          condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                     else: "NodeValue(kind: vkBool, boolVal: true)"
        var code = "while isTruthy(" & condCode & "):\n"
        for stmt in bodyBlock.body:
          let stmtCode = genStatement(ctx, stmt)
          if stmtCode.len > 0:
            code.add(indentBlock(stmtCode))
        return code

    of "whileFalse:":
      if msg.arguments.len >= 1 and msg.arguments[0].kind == nkBlock:
        let bodyBlock = msg.arguments[0].BlockNode
        var condCode: string
        if msg.receiver != nil and msg.receiver.kind == nkBlock:
          let condBlock = msg.receiver.BlockNode
          if condBlock.body.len > 0:
            condCode = genExpression(ctx, condBlock.body[condBlock.body.len - 1])
          else:
            condCode = "NodeValue(kind: vkBool, boolVal: false)"
        else:
          condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                     else: "NodeValue(kind: vkBool, boolVal: false)"
        var code = "while not isTruthy(" & condCode & "):\n"
        for stmt in bodyBlock.body:
          let stmtCode = genStatement(ctx, stmt)
          if stmtCode.len > 0:
            code.add(indentBlock(stmtCode))
        return code

    of "ifTrue:":
      if msg.arguments.len >= 1 and msg.arguments[0].kind == nkBlock:
        let thenBlock = msg.arguments[0].BlockNode
        let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                       else: "NodeValue(kind: vkBool, boolVal: true)"
        var code = "if isTruthy(" & condCode & "):\n"
        if thenBlock.body.len == 0:
          code.add("  discard\n")
        else:
          for stmt in thenBlock.body:
            let stmtCode = genStatement(ctx, stmt)
            if stmtCode.len > 0:
              code.add(indentBlock(stmtCode))
        return code

    of "ifFalse:":
      if msg.arguments.len >= 1 and msg.arguments[0].kind == nkBlock:
        let thenBlock = msg.arguments[0].BlockNode
        let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                       else: "NodeValue(kind: vkBool, boolVal: false)"
        var code = "if not isTruthy(" & condCode & "):\n"
        if thenBlock.body.len == 0:
          code.add("  discard\n")
        else:
          for stmt in thenBlock.body:
            let stmtCode = genStatement(ctx, stmt)
            if stmtCode.len > 0:
              code.add(indentBlock(stmtCode))
        return code

    of "ifTrue:ifFalse:":
      if msg.arguments.len >= 2 and
         msg.arguments[0].kind == nkBlock and
         msg.arguments[1].kind == nkBlock:
        let thenBlock = msg.arguments[0].BlockNode
        let elseBlock = msg.arguments[1].BlockNode
        let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                       else: "NodeValue(kind: vkBool, boolVal: true)"
        var code = "if isTruthy(" & condCode & "):\n"
        if thenBlock.body.len == 0:
          code.add("  discard\n")
        else:
          for stmt in thenBlock.body:
            let stmtCode = genStatement(ctx, stmt)
            if stmtCode.len > 0:
              code.add(indentBlock(stmtCode))
        code.add("else:\n")
        if elseBlock.body.len == 0:
          code.add("  discard\n")
        else:
          for stmt in elseBlock.body:
            let stmtCode = genStatement(ctx, stmt)
            if stmtCode.len > 0:
              code.add(indentBlock(stmtCode))
        return code

    of "timesRepeat:":
      if msg.arguments.len >= 1 and msg.arguments[0].kind == nkBlock:
        let bodyBlock = msg.arguments[0].BlockNode
        let countCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                        else: "NodeValue(kind: vkInt, intVal: 0)"
        var code = "for timesRepeatI in 0..<toInt(" & countCode & "):\n"
        if bodyBlock.body.len == 0:
          code.add("  discard\n")
        else:
          for stmt in bodyBlock.body:
            let stmtCode = genStatement(ctx, stmt)
            if stmtCode.len > 0:
              code.add(indentBlock(stmtCode))
        return code

    else:
      discard  # Fall through to default message handling

    # Default: message send as statement
    let msgCode = genMessage(ctx, node.MessageNode)
    return "discard " & msgCode

  of nkPrimitiveCall:
    # Primitive call as statement
    let primCall = node.PrimitiveCallNode
    let args = primCall.arguments.mapIt(genExpression(ctx, it)).join(", ")
    return "discard callPrimitive(\"" & primCall.selector & "\", @[" & args & "])"

  of nkIf:
    ## Inline ifTrue:/ifFalse: control flow in statement context
    let ifNode = node.IfNode
    let condCode = genExpression(ctx, ifNode.condition)
    var code = "if isTruthy(" & condCode & "):\n"
    # Generate then branch with proper indentation
    if ifNode.thenBranch != nil:
      # If thenBranch is a block, inline its body (don't create the block)
      var thenStmts: seq[Node] = @[]
      var thenHasNonLocalReturn = false
      if ifNode.thenBranch.kind == nkBlock:
        let blk = ifNode.thenBranch.BlockNode
        thenStmts = blk.body
        # Check if block has non-local returns
        for stmt in blk.body:
          if stmt.kind == nkReturn:
            thenHasNonLocalReturn = true
            break
      else:
        thenStmts = @[ifNode.thenBranch]
      for stmt in thenStmts:
        var stmtCode: string
        if stmt.kind == nkReturn and thenHasNonLocalReturn:
          # Non-local return from inlined block: raise exception
          let ret = stmt.ReturnNode
          let exprCode = if ret.expression != nil:
                           genExpression(ctx, ret.expression)
                         else:
                           "NodeValue(kind: vkNil)"
          stmtCode = fmt("raise (ref NonLocalReturnException)(value: {exprCode}, targetId: 0)")
        else:
          stmtCode = genStatement(ctx, stmt)
        if stmtCode.len > 0:
          # Indent each line
          for line in stmtCode.splitLines():
            if line.len > 0:
              code.add("  " & line & "\n")
        else:
          code.add("  discard\n")
    else:
      code.add("  discard\n")
    # Generate else branch if present
    if ifNode.elseBranch != nil:
      code.add("else:\n")
      # If elseBranch is a block, inline its body
      var elseStmts: seq[Node] = @[]
      var elseHasNonLocalReturn = false
      if ifNode.elseBranch.kind == nkBlock:
        let blk = ifNode.elseBranch.BlockNode
        elseStmts = blk.body
        # Check if block has non-local returns
        for stmt in blk.body:
          if stmt.kind == nkReturn:
            elseHasNonLocalReturn = true
            break
      else:
        elseStmts = @[ifNode.elseBranch]
      for stmt in elseStmts:
        var stmtCode: string
        if stmt.kind == nkReturn and elseHasNonLocalReturn:
          # Non-local return from inlined block: raise exception
          let ret = stmt.ReturnNode
          let exprCode = if ret.expression != nil:
                           genExpression(ctx, ret.expression)
                         else:
                           "NodeValue(kind: vkNil)"
          stmtCode = fmt("raise (ref NonLocalReturnException)(value: {exprCode}, targetId: 0)")
        else:
          stmtCode = genStatement(ctx, stmt)
        if stmtCode.len > 0:
          # Indent each line
          for line in stmtCode.splitLines():
            if line.len > 0:
              code.add("  " & line & "\n")
        else:
          code.add("  discard\n")
    return code

  else:
    # For other nodes, just generate the expression
    let exprCode = genExpression(ctx, node)
    if exprCode.len > 0:
      return "discard " & exprCode
    return ""

proc genBlockBody*(ctx: GenContext, blkNode: BlockNode, captures: seq[string] = @[],
                   hasNonLocalReturn: bool = false, envStructName: string = ""): string =
  ## Generate code for block body (sequence of statements)
  ## captures: list of captured variable names (from BlockProcInfo)
  ## hasNonLocalReturn: if true, ^ generates NonLocalReturnException
  ## envStructName: name of environment struct for typed access
  var output = ""

  # Create new context for block body with its parameters
  # Share the blockRegistry so nested blocks can be found
  var bodyCtx = GenContext(
    cls: ctx.cls,
    inBlock: true,
    locals: @[],
    parameters: @[],
    globals: ctx.globals,
    blockRegistry: ctx.blockRegistry
  )
  for param in blkNode.parameters:
    bodyCtx.parameters.add(param)

  # Determine which captured variables are assigned in the block body
  var assignedCaptures = initHashSet[string]()
  for stmt in blkNode.body:
    collectAssignedVars(stmt, assignedCaptures)

  # Extract captured variables from environment struct
  # Variables that are assigned need special handling (write-back to env)
  var mutableCaptures: seq[string] = @[]
  if captures.len > 0 and envStructName.len > 0:
    # Cast env pointer to typed struct pointer
    output.add(fmt("  let envPtr = cast[ptr {envStructName}](env)\n"))
    for capture in captures:
      if capture in assignedCaptures:
        # Mutable capture: extract as var and track for write-back
        output.add(fmt("  var {capture} = envPtr.{capture}\n"))
        mutableCaptures.add(capture)
      else:
        # Immutable capture: extract as let
        output.add(fmt("  let {capture} = envPtr.{capture}\n"))
      bodyCtx.locals.add(capture)

  # Handle empty block body
  if blkNode.body.len == 0:
    output.add("  return NodeValue(kind: vkNil)\n")
    return output

  for i, stmt in blkNode.body:
    if stmt.kind == nkReturn and hasNonLocalReturn:
      # Non-local return from block: raise exception to return from enclosing method
      let ret = stmt.ReturnNode
      let exprCode = if ret.expression != nil:
                       genExpression(bodyCtx, ret.expression)
                     else:
                       "NodeValue(kind: vkNil)"
      output.add(fmt("  raise (ref NonLocalReturnException)(value: {exprCode}, targetId: 0)\n"))
    elif i == blkNode.body.len - 1 and stmt.kind notin {nkReturn, nkAssign, nkIf}:
      # Last statement is the return value (but not if it's nkIf which needs special handling)
      let exprCode = genExpression(bodyCtx, stmt)
      output.add("  return " & exprCode & "\n")
    else:
      let stmtCode = genStatement(bodyCtx, stmt)
      if stmtCode.len > 0:
        # Indent each line of the statement
        for line in stmtCode.splitLines():
          if line.len > 0:
            output.add("  " & line & "\n")

  # Write back mutable captures to environment before returning
  if captures.len > 0 and envStructName.len > 0:
    for capture in mutableCaptures:
      output.add(fmt("  envPtr.{capture} = {capture}\n"))

  # If no explicit return statement, return nil
  if blkNode.body.len == 0 or blkNode.body[^1].kind notin {nkReturn}:
    output.add("  return NodeValue(kind: vkNil)\n")

  return output

proc genTemporaries*(tmp: seq[string]): string =
  ## Generate temporary variable declarations
  if tmp.len == 0:
    return ""

  var output = "  # Temporaries\n"
  for t in tmp:
    output.add(fmt("  var {t} = NodeValue(kind: vkNil)\n"))
  output.add("\n")
  return output

proc genParameters*(params: seq[string]): string =
  ## Generate parameter declarations for method signature
  if params.len == 0:
    return ""

  var parts: seq[string] = @[]
  for p in params:
    parts.add(fmt("{p}: NodeValue"))
  return ", " & parts.join(", ")

proc genTopLevelStatement*(ctx: GenContext, node: Node): string =
  ## Generate code for a top-level statement (for main proc)
  ## Returns code that can be executed in a main() procedure

  if node == nil:
    return ""

  case node.kind
  of nkAssign:
    let assign = node.AssignNode
    let varName = assign.variable
    let exprCode = genExpression(ctx, assign.expression)

    # Track variable type for native optimization
    # Pattern 1: varName := ClassName new (nkMessage with Ident or Symbol receiver)
    # Only set if not already set by a previous pattern
    if not (varName in ctx.variableTypes):
      if assign.expression != nil and assign.expression.kind == nkMessage:
        let msg = assign.expression.MessageNode
        if msg.selector == "new" and msg.receiver != nil:
          if msg.receiver.kind == nkIdent:
            let className = msg.receiver.IdentNode.name
            ctx.variableTypes[varName] = className
          elif msg.receiver.kind == nkLiteral:
            let lit = msg.receiver.LiteralNode
            if lit.value.kind == vkSymbol:
              let className = lit.value.symVal
              ctx.variableTypes[varName] = className
      # Pattern 2: Native constructor (exprCode starts with newClass_) - only if Pattern1 didn't match
      if not (varName in ctx.variableTypes) and exprCode.startsWith("newClass_"):
        let className = exprCode[7..<exprCode.find("(")]
        ctx.variableTypes[varName] = className

    # Check if it's a reassignment of an existing variable
    if varName in ctx.locals or varName in ctx.globals:
      return fmt"{varName} = {exprCode}"

    # New top-level variable (local to main, also tracked as global for blocks)
    ctx.locals.add(varName)
    ctx.globals.add(varName)
    return fmt"var {varName} = {exprCode}"

  of nkMessage:
    # Top-level message send - delegate to genStatement for inline control flow
    return genStatement(ctx, node)

  of nkReturn:
    # Return at top level becomes exit code
    let ret = node.ReturnNode
    if ret.expression != nil:
      return "return " & genExpression(ctx, ret.expression) & ".intVal"
    return "return 0"

  else:
    # Other expressions
    let exprCode = genExpression(ctx, node)
    if exprCode.len > 0:
      return "discard " & exprCode
    return ""
