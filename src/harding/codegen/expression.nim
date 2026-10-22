import std/[strutils, sequtils, strformat, tables]
import ../core/types
import ../compiler/context
import ../compiler/symbols
import ./blocks
import ./numeric

# ============================================================================
# Expression Code Generation
# Generates Nim code from AST expressions
# ============================================================================

type
  VarTypeInfo* = object
    ## Type information for a variable
    name*: string          ## Variable name
    className*: string     ## Class name (e.g., "Person", "Array", etc.)
    isNativeClass*: bool   ## Whether this is a native compiled class

  GenContext* = ref object
    cls*: ClassInfo
    inBlock*: bool
    returnTarget*: string         ## Expression identifying a block's home activation
    inMethod*: bool              ## Whether we're generating code inside a method body
    cellNames*: seq[string]       ## Lexical bindings shared with compiled blocks
    locals*: seq[string]          ## Local variable names (temporaries)
    parameters*: seq[string]      ## Parameter names
    globals*: seq[string]         ## Known global variable names
    blockRegistry*: BlockRegistry ## Registry for blocks to compile
    varTypes*: Table[string, VarTypeInfo]  ## Variable name -> type info
    compiledClasses*: seq[string] ## Names of classes being compiled (for native instantiation)
    classInfo*: Table[string, ClassInfo]   ## Class name -> ClassInfo with slot info
    mixed*: bool                  ## Whether mixed mode is enabled (fallback to interpreter)
    numericBindings*: NumericBindings ## Proven lexical native representations

# Forward declaration
proc genExpression*(ctx: GenContext, node: Node): string
proc genStatement*(ctx: GenContext, node: Node): string
proc asBlockNode(node: Node): BlockNode
proc isBlockWithCaptures*(ctx: GenContext, node: Node): tuple[isBlock: bool, blockInfo: BlockProcInfo]

proc newGenContext*(cls: ClassInfo = nil, compiledClasses: seq[string] = @[],
                    classInfo: Table[string, ClassInfo] = initTable[string, ClassInfo](),
                    mixed: bool = false): GenContext =
  ## Create new generation context
  result = GenContext(
    cls: cls,
    inBlock: false,
    inMethod: false,
    locals: @[],
    parameters: @[],
    globals: @[],
    blockRegistry: newBlockRegistry(),
    varTypes: initTable[string, VarTypeInfo](),
    numericBindings: initTable[string, NumericRepresentation](),
    compiledClasses: compiledClasses,
    classInfo: classInfo,
    mixed: mixed
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

proc setVariableType*(ctx: GenContext, varName: string, className: string, isNative = true) =
  ## Set the type of a variable to a specific class
  ctx.varTypes[varName] = VarTypeInfo(
    name: varName,
    className: className,
    isNativeClass: isNative
  )

proc getVariableType*(ctx: GenContext, varName: string): VarTypeInfo =
  ## Get the type info for a variable
  if varName in ctx.varTypes:
    return ctx.varTypes[varName]
  return VarTypeInfo(name: varName, className: "", isNativeClass: false)

proc inferTypeFromExpression*(ctx: GenContext, node: Node): VarTypeInfo =
  ## Infer the type of an expression
  ## Returns VarTypeInfo with isNativeClass=true only for native constructors
  if node == nil:
    return VarTypeInfo(name: "", className: "", isNativeClass: false)
  
  case node.kind
  of nkMessage:
    let msg = node.MessageNode
    # Check for "Class new" pattern where Class is a compiled class
    # In this case we generate a native constructor call
    if msg.selector == "new" and msg.receiver != nil and msg.receiver.kind == nkIdent:
      let className = msg.receiver.IdentNode.name
      # Check if this class is being compiled (will use native constructor)
      let isNative = className in ctx.compiledClasses
      return VarTypeInfo(name: "", className: className, isNativeClass: isNative)
    
    # Check for other patterns that might indicate type
    elif msg.receiver != nil:
      let receiverType = ctx.inferTypeFromExpression(msg.receiver)
      if receiverType.className.len > 0:
        # Inherit native status from receiver for cascade patterns
        return receiverType
  of nkIdent:
    let varName = node.IdentNode.name
    if varName in ctx.varTypes:
      return ctx.varTypes[varName]
  else:
    discard
  
  return VarTypeInfo(name: "", className: "", isNativeClass: false)

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

proc genNodeValueLiteral*(val: NodeValue): string =
  ## Generate Nim code for a pre-computed NodeValue.
  ## Used for constant array/table literals.
  case val.kind
  of vkInt:
    return fmt("NodeValue(kind: vkInt, intVal: {val.intVal})")
  of vkFloat:
    return fmt("NodeValue(kind: vkFloat, floatVal: {val.floatVal})")
  of vkString:
    let escaped = escapeNimString(val.strVal)
    return fmt("NodeValue(kind: vkString, strVal: \"{escaped}\")")
  of vkSymbol:
    let escaped = escapeNimString(val.symVal)
    return fmt("NodeValue(kind: vkSymbol, symVal: \"{escaped}\")")
  of vkBool:
    return fmt("NodeValue(kind: vkBool, boolVal: {val.boolVal})")
  of vkNil:
    return "NodeValue(kind: vkNil)"
  of vkArray:
    var elems: seq[string] = @[]
    for elem in val.arrayVal:
      elems.add(genNodeValueLiteral(elem))
    return fmt("compiledArray(@[{elems.join(\", \")}])")
  of vkTable:
    var entries: seq[string] = @[]
    for key, v in val.tableVal.pairs:
      entries.add(fmt("({genNodeValueLiteral(key)}, {genNodeValueLiteral(v)})"))
    return fmt("nt_tableFrom([{entries.join(\", \")}])")
  else:
    return "NodeValue(kind: vkNil)"

proc captureCellNames*(registry: BlockRegistry): seq[string] =
  ## Names requiring cells in scopes that bind them.
  if registry != nil:
    for info in registry.blocks:
      for name in info.captures:
        if name != "self" and name notin result:
          result.add(name)

proc scopeCaptureCellNames*(body: seq[Node], ownerLocalNames: seq[string] = @[]): seq[string] =
  ## Analyze only blocks lexically contained in this body.
  let registry = newBlockRegistry()
  let locals = scopeLocalNames(body, ownerLocalNames)
  for node in body:
    collectBlocks(registry, node, ownerLocalNames = locals)
  return captureCellNames(registry)

proc bindingTarget(ctx: GenContext, name: string): string =
  if name in ctx.cellNames:
    return mangleIdentifier(name) & ".value"
  return mangleIdentifier(name)

proc bindingAssignmentValue(ctx: GenContext, name, value: string): string =
  case ctx.numericBindings.getOrDefault(name, nrDynamic)
  of nrInt: "(" & value & ").intVal"
  of nrFloat: "(" & value & ").floatVal"
  else: value

proc bindingDeclaration(ctx: GenContext, name, value: string): string =
  let identifier = mangleIdentifier(name)
  if name in ctx.numericBindings:
    return fmt("var {identifier} = {bindingAssignmentValue(ctx, name, value)}")
  if name in ctx.cellNames:
    return fmt("var {identifier} = MutableCell(value: {value})")
  return fmt("var {identifier} = {value}")

proc genLocalDeclarations*(ctx: GenContext, names: seq[string]): string =
  ## Declare lexical temporaries before evaluating a scope's body.
  for name in names:
    if not ctx.isLocal(name):
      ctx.locals.add(name)
      case ctx.numericBindings.getOrDefault(name, nrDynamic)
      of nrInt:
        result.add(fmt("var {mangleIdentifier(name)} = 0\n"))
      of nrFloat:
        result.add(fmt("var {mangleIdentifier(name)} = 0.0\n"))
      else:
        result.add(bindingDeclaration(ctx, name, "NodeValue(kind: vkNil)") & "\n")

proc inlineBlockContext(ctx: GenContext, blk: BlockNode): GenContext =
  result = newGenContext(ctx.cls, ctx.compiledClasses, ctx.classInfo, ctx.mixed)
  result.inMethod = ctx.inMethod
  result.inBlock = ctx.inBlock
  result.returnTarget = ctx.returnTarget
  result.blockRegistry = ctx.blockRegistry
  result.varTypes = ctx.varTypes
  result.numericBindings = ctx.numericBindings
  result.globals = ctx.globals
  result.cellNames = ctx.cellNames
  for name in ctx.locals:
    if name notin blk.temporaries and name notin blk.parameters:
      result.locals.add(name)
  for name in ctx.parameters:
    if name notin blk.temporaries and name notin blk.parameters:
      result.parameters.add(name)
  for name in scopeCaptureCellNames(blk.body):
    if name notin result.cellNames:
      result.cellNames.add(name)

proc inlineBlockStatements(ctx: GenContext, blk: BlockNode): string =
  let bodyCtx = inlineBlockContext(ctx, blk)
  result = "block:\n"
  result.add(indentBlock(genLocalDeclarations(bodyCtx, blk.temporaries)))
  for statement in blk.body:
    result.add(indentBlock(genStatement(bodyCtx, statement)))
  if blk.body.len == 0 and blk.temporaries.len == 0:
    result.add("  discard\n")

proc inlineBlockExpression(ctx: GenContext, blk: BlockNode): string =
  let bodyCtx = inlineBlockContext(ctx, blk)
  result = "(block:\n"
  result.add(indentBlock(genLocalDeclarations(bodyCtx, blk.temporaries), 4))
  for i, statement in blk.body:
    if i == blk.body.high:
      result.add(indentBlock(genExpression(bodyCtx, statement), 4))
    else:
      result.add(indentBlock(genStatement(bodyCtx, statement), 4))
  if blk.body.len == 0:
    result.add("    nilValue()\n")
  result.add(")")

proc genSymbolAccess*(ctx: GenContext, name: string): string =
  ## Generate code for symbol/variable access
  ## Priority: parameters > locals > slots > globals

  if name == "self":
    if name in ctx.cellNames:
      return "self.value"
    if ctx.inMethod:
      return "self"
    else:
      return "self.toValue()"

  if name == "nil":
    return "NodeValue(kind: vkNil)"

  if name == "true":
    return "NodeValue(kind: vkBool, boolVal: true)"

  if name == "false":
    return "NodeValue(kind: vkBool, boolVal: false)"

  # Check if it's a parameter
  if name in ctx.parameters:
    return bindingTarget(ctx, name)

  # Check if it's a local variable
  if name in ctx.locals:
    case ctx.numericBindings.getOrDefault(name, nrDynamic)
    of nrInt: return fmt("NodeValue(kind: vkInt, intVal: {mangleIdentifier(name)})")
    of nrFloat: return fmt("NodeValue(kind: vkFloat, floatVal: {mangleIdentifier(name)})")
    else: return bindingTarget(ctx, name)

  # Check if it's a slot
  if ctx.cls != nil:
    let slotIdx = ctx.cls.getSlotIndex(name)
    if slotIdx >= 0:
      if ctx.inMethod:
        return fmt("getSlotValue(self, \"{name}\")")
      return fmt("self.slots[{slotIdx}]")

  if not ctx.mixed and name in ["Exception", "Error", "Notification", "DivisionByZero", "MessageNotUnderstood", "SubscriptOutOfBounds"]:
    return fmt("compiledExceptionClassValue(\"{name}\")")

  if name in ctx.compiledClasses and not ctx.mixed:
    return fmt("compiledClassValue(\"{name}\")")

  if name in ["Root", "Object", "Mixin"] and not ctx.mixed:
    return fmt("compiledBaseClassValue(\"{name}\")")

  if name == "System" and not ctx.mixed:
    return "compiledSystemClassValue()"

  if name == "Log" and not ctx.mixed:
    return "compiledLogClassValue()"

  if name == "Json" and not ctx.mixed:
    return "compiledJsonClassValue()"

  # Check if it's a known global (class or global variable)
  if name in ctx.globals:
    # Globals are stored in a globals table
    return fmt("getGlobal(\"{name}\")")

  # Fallback: treat as symbol
  return fmt("NodeValue(kind: vkSymbol, symVal: \"{name}\")")

proc tryGenerateNamedAccess*(ctx: GenContext, node: NamedAccessNode, receiverCode: string): string =
  ## Try to generate direct access for named access on known compiled classes.
  let receiverType = ctx.inferTypeFromExpression(node.receiver)
  if receiverType.className.len == 0:
    return ""
  if ctx.mixed:
    return ""
  if not receiverType.isNativeClass:
    return ""
  if receiverType.className notin ctx.classInfo:
    return ""

  let classDef = ctx.classInfo[receiverType.className]
  var slotFound = false
  for slot in classDef.getAllSlots():
    if slot.name == node.memberName:
      slotFound = true
      break

  if not slotFound:
    return ""

  let nativeReceiver = fmt("cast[{mangleClass(receiverType.className)}]({receiverCode}.instVal.nimValue)")
  let mangledSlot = mangleSlot(node.memberName)
  if node.isAssignment and node.valueExpr != nil:
    let valueCode = genExpression(ctx, node.valueExpr)
    return fmt("set{mangledSlot}({nativeReceiver}, {valueCode})")
  return fmt("get{mangledSlot}({nativeReceiver})")

proc genCapturedBlockExpression(blockInfo: BlockProcInfo, ctx: GenContext): string =
  ## Generate expression-safe block creation for captured blocks.
  var initFields: seq[string] = @[]
  if blockInfo.ownerMethodId != 0:
    initFields.add("home: hardingHome")
  for capture in blockInfo.captures:
    let cell = if ctx.isLocal(capture) and capture in ctx.cellNames:
                 mangleIdentifier(capture)
               else:
                 fmt("MutableCell(value: {genSymbolAccess(ctx, capture)})")
    initFields.add(fmt("{mangleIdentifier(capture)}: {cell}"))

  let fieldsStr = initFields.join(", ")
  return fmt("(block:\n    createBlockWithEnv({blockInfo.nimName}, {blockInfo.paramCount}, {blockInfo.envStructName}({fieldsStr})))")

proc genMessage*(ctx: GenContext, node: MessageNode): string =
  ## Generate code for message send

  # Generate receiver
  var receiverCode: string
  if node.receiver != nil:
    receiverCode = genExpression(ctx, node.receiver)
  else:
    # Implicit self - in method context use self directly, otherwise convert to value
    if ctx.inMethod:
      receiverCode = "self"
    else:
      receiverCode = "self.toValue()"

  # Check for native class instantiation: "ClassName new" where ClassName is compiled
  if node.selector == "new" and node.receiver != nil and node.receiver.kind == nkIdent:
    let className = node.receiver.IdentNode.name
    if className in ctx.compiledClasses and not ctx.isLocal(className):
      # In mixed mode, use interpreter to create instances (ensures interpreter can call methods)
      if ctx.mixed:
        return fmt("sendMessageHybrid(hybridInterpreter.globals[\"{className}\"], \"new\", @[])")
      else:
        return fmt("guardedNew_{mangleClass(className)}()")

  # Check for inline control flow with literal blocks
  case node.selector
  of "ifTrue:ifFalse:":
    # Inline if/else when both blocks are literals
    if node.arguments.len >= 2 and
       node.arguments[0].kind == nkBlock and
       node.arguments[1].kind == nkBlock and
       not hasReturnNode(node.arguments[0]) and
       not hasReturnNode(node.arguments[1]):
      let thenBlock = node.arguments[0].BlockNode
      let elseBlock = node.arguments[1].BlockNode
      var code = "(if isTruthy(" & receiverCode & "):\n"
      code.add(indentBlock(inlineBlockExpression(ctx, thenBlock), 6))
      code.add("    else:\n")
      code.add(indentBlock(inlineBlockExpression(ctx, elseBlock), 6))
      code.add("  )")
      return code

  of "ifTrue:":
    # Inline if when block is literal
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]):
      let thenBlock = node.arguments[0].BlockNode
      var code = "(if isTruthy(" & receiverCode & "):\n"
      code.add(indentBlock(inlineBlockExpression(ctx, thenBlock), 6))
      code.add("    else:\n")
      code.add("      nilValue()\n")
      code.add("  )")
      return code

  of "ifFalse:":
    # Inline ifFalse when block is literal
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]):
      let thenBlock = node.arguments[0].BlockNode
      var code = "(if not isTruthy(" & receiverCode & "):\n"
      code.add(indentBlock(inlineBlockExpression(ctx, thenBlock), 6))
      code.add("    else:\n")
      code.add("      nilValue()\n")
      code.add("  )")
      return code

  of "whileTrue:":
    # Inline whileTrue when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]) and
       (node.receiver == nil or not hasReturnNode(node.receiver)):
      let bodyBlock = node.arguments[0].BlockNode
      var condCode = receiverCode
      if node.receiver != nil and node.receiver.kind == nkBlock:
        let condBlock = node.receiver.BlockNode
        if condBlock.body.len > 0:
          condCode = inlineBlockExpression(ctx, condBlock)
      var code = "(block:\n"
      code.add("    while isTruthy(" & condCode & "):\n")
      code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock), 6))
      code.add("    nilValue())")
      return code

  of "whileFalse:":
    # Inline whileFalse when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]) and
       (node.receiver == nil or not hasReturnNode(node.receiver)):
      let bodyBlock = node.arguments[0].BlockNode
      var condCode = receiverCode
      if node.receiver != nil and node.receiver.kind == nkBlock:
        let condBlock = node.receiver.BlockNode
        if condBlock.body.len > 0:
          condCode = inlineBlockExpression(ctx, condBlock)
      var code = "(block:\n"
      code.add("    while not isTruthy(" & condCode & "):\n")
      code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock), 6))
      code.add("    nilValue())")
      return code

  of "do:":
    # Inline do: only for a literal Array receiver; other receivers keep
    # ordinary dispatch so Table/Set species and callback arity stay correct.
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       node.receiver != nil and node.receiver.kind == nkArray and
       not hasReturnNode(node.arguments[0]):
      let bodyBlock = node.arguments[0].BlockNode
      if bodyBlock.parameters.len == 1:
        let elemName = bodyBlock.parameters[0]
        # Create a new context with the loop variable as a local
        let doCtx = inlineBlockContext(ctx, bodyBlock)
        doCtx.locals.add(elemName)
        var code = "(block:\n"
        code.add("    let hardingDoReceiver = " & receiverCode & "\n")
        code.add("    for hardingDoIdx, hardingElem in compiledArrayElements(hardingDoReceiver):\n")
        code.add("      " & bindingDeclaration(doCtx, elemName, "hardingElem") & "\n")
        code.add(indentBlock(genLocalDeclarations(doCtx, bodyBlock.temporaries), 6))
        for stmt in bodyBlock.body:
          let stmtCode = genStatement(doCtx, stmt)
          code.add(indentBlock(stmtCode, 6))
        code.add("    hardingDoReceiver)")
        return code

  of "collect:":
    # Inline collect: only for a literal Array receiver; other receivers keep
    # ordinary dispatch so result species stays correct.
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       node.receiver != nil and node.receiver.kind == nkArray and
       not hasReturnNode(node.arguments[0]):
      let bodyBlock = node.arguments[0].BlockNode
      if bodyBlock.parameters.len == 1:
        let elemName = bodyBlock.parameters[0]
        # Create a new context with the loop variable as a local
        let collectCtx = inlineBlockContext(ctx, bodyBlock)
        collectCtx.locals.add(elemName)
        var code = "(block:\n"
        code.add("    var hardingCollectResult: seq[NodeValue] = @[]\n")
        code.add("    for hardingCollectIdx, hardingElem in " & "compiledArrayElements(" & receiverCode & "):\n")
        code.add("      " & bindingDeclaration(collectCtx, elemName, "hardingElem") & "\n")
        code.add(indentBlock(genLocalDeclarations(collectCtx, bodyBlock.temporaries), 6))
        # Generate all statements except the last one
        for i in 0..<bodyBlock.body.len-1:
          let stmtCode = genStatement(collectCtx, bodyBlock.body[i])
          code.add(indentBlock(stmtCode, 6))
        # The last statement's value is what we collect
        if bodyBlock.body.len > 0:
          let lastStmt = bodyBlock.body[^1]
          let valueCode = genExpression(collectCtx, lastStmt)
          code.add("      hardingCollectResult.add(" & valueCode & ")\n")
        code.add("    compiledArray(hardingCollectResult))")
        return code

  of "select:":
    # Inline select: only for a literal Array receiver; other receivers keep
    # ordinary dispatch so result species stays correct.
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       node.receiver != nil and node.receiver.kind == nkArray and
       not hasReturnNode(node.arguments[0]):
      let bodyBlock = node.arguments[0].BlockNode
      if bodyBlock.parameters.len == 1:
        let elemName = bodyBlock.parameters[0]
        # Create a new context with the loop variable as a local
        let selectCtx = inlineBlockContext(ctx, bodyBlock)
        selectCtx.locals.add(elemName)
        var code = "(block:\n"
        code.add("    var hardingSelectResult: seq[NodeValue] = @[]\n")
        code.add("    for hardingSelectIdx, hardingElem in " & "compiledArrayElements(" & receiverCode & "):\n")
        code.add("      " & bindingDeclaration(selectCtx, elemName, "hardingElem") & "\n")
        code.add(indentBlock(genLocalDeclarations(selectCtx, bodyBlock.temporaries), 6))
        for i in 0..<max(0, bodyBlock.body.len - 1):
          code.add(indentBlock(genStatement(selectCtx, bodyBlock.body[i]), 6))
        let condCode = if bodyBlock.body.len > 0:
                         genExpression(selectCtx, bodyBlock.body[^1])
                       else:
                         "nilValue()"
        code.add("      if isTruthy(" & condCode & "):\n")
        code.add("        hardingSelectResult.add(hardingElem)\n")
        code.add("    compiledArray(hardingSelectResult))")
        return code

  of "timesRepeat:":
    # Inline timesRepeat when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]):
      let bodyBlock = node.arguments[0].BlockNode
      var code = "(block:\n"
      code.add("    let count = compiledLoopInt(" & receiverCode & ")\n")
      code.add("    for timesRepeatI in 0..<count:\n")
      code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock), 6))
      code.add("    nilValue())")
      return code

  of "to:by:do:":
    # Inline to:by:do: when body is a literal block (expression context - needs value)
    if node.arguments.len >= 3 and node.arguments[2].kind == nkBlock and
       not hasReturnNode(node.arguments[2]):
      let endVal = genExpression(ctx, node.arguments[0])
      let stepVal = genExpression(ctx, node.arguments[1])
      let bodyBlock = node.arguments[2].BlockNode
      var loopCtx = newGenContext(ctx.cls, ctx.compiledClasses, ctx.classInfo, ctx.mixed)
      loopCtx.inMethod = ctx.inMethod
      loopCtx.inBlock = ctx.inBlock
      loopCtx.returnTarget = ctx.returnTarget
      loopCtx.locals = ctx.locals
      loopCtx.parameters = ctx.parameters
      loopCtx.globals = ctx.globals
      loopCtx.cellNames = ctx.cellNames
      loopCtx.blockRegistry = ctx.blockRegistry
      loopCtx.varTypes = ctx.varTypes
      loopCtx.numericBindings = ctx.numericBindings
      for parameter in bodyBlock.parameters:
        loopCtx.locals.add(parameter)
      var iterationSetup = ""
      if bodyBlock.parameters.len > 0:
        iterationSetup.add(bindingDeclaration(loopCtx, bodyBlock.parameters[0],
          "NodeValue(kind: vkInt, intVal: current)") & "\n")
      iterationSetup.add(genLocalDeclarations(loopCtx, bodyBlock.temporaries))
      var code = "(block:\n"
      code.add("    var current = compiledLoopInt(" & receiverCode & ")\n")
      code.add("    let endNum = compiledLoopInt(" & endVal & ")\n")
      code.add("    let step = compiledLoopInt(" & stepVal & ")\n")
      code.add("    if step > 0:\n")
      code.add("      while current <= endNum:\n")
      code.add(indentBlock(iterationSetup, 8))
      for stmt in bodyBlock.body:
        let stmtCode = genStatement(loopCtx, stmt)
        code.add(indentBlock(stmtCode, 8))
      code.add("        current += step\n")
      code.add("    else:\n")
      code.add("      while current >= endNum:\n")
      code.add(indentBlock(iterationSetup, 8))
      for stmt in bodyBlock.body:
        let stmtCode = genStatement(loopCtx, stmt)
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

  of "<", "<=", ">", ">=", "=", "==", "~=", "<>":
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

  of "println", "writeLine:", "writeline:":
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

  of "&":
    # Generic concatenation via string conversion
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

  of "derive:", "derive", "new", "selector:put:", "classSelector:put:":
    # Class-related messages - need runtime dispatch
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    let msgProc = if ctx.mixed: "sendMessageHybrid" else: "sendMessage"
    if ctx.mixed:
      return fmt("{msgProc}({receiverCode}, \"{node.selector}\", @[{args}])")
    else:
      return fmt("{msgProc}(currentRuntime[], {receiverCode}, \"{node.selector}\", @[{args}])")

  else:
    # Mixed-mode dispatch retains its fallback; pure sends use a per-site cache.
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    if ctx.mixed:
      return fmt("sendMessageHybrid({receiverCode}, \"{node.selector}\", @[{args}])")
    return fmt("cachedSend(currentRuntime[], {receiverCode}, \"{node.selector}\", @[{args}])")

proc blockOwnerLocals*(ctx: GenContext): seq[string] =
  ## Parameters and locals declared in the enclosing method. These shadow
  ## same-named slots for nested blocks, so they must be captured as ordinary
  ## enclosing variables rather than resolved as slot accesses.
  for name in ctx.parameters:
    result.add(name)
  for name in ctx.locals:
    if name notin result:
      result.add(name)

proc blockOwnerSlots*(ctx: GenContext): seq[string] =
  ## Slot names of the class owning the enclosing method. Blocks lexically inside
  ## a method may read or write these, which requires capturing `self`.
  if ctx.cls != nil and ctx.inMethod:
    for slot in ctx.cls.getAllSlots():
      result.add(slot.name)

proc blockCaptureGlobals*(ctx: GenContext): seq[string] =
  ## Known globals to pass when registering a nested block. `self` is a
  ## pseudo-variable that block procedures receive through their captured
  ## environment, not a global, so it is deliberately excluded here: including it
  ## in knownGlobals suppresses the capture and leaves the generated block with
  ## no receiver.
  for name in ctx.globals:
    if name != "self":
      result.add(name)

proc nativeNumericExpression(ctx: GenContext, node: Node): string =
  case node.kind
  of nkLiteral:
    let value = node.LiteralNode.value
    if value.kind == vkInt:
      return $value.intVal
    return $value.floatVal
  of nkIdent:
    return mangleIdentifier(node.IdentNode.name)
  of nkMessage:
    let message = node.MessageNode
    let left = nativeNumericExpression(ctx, message.receiver)
    let right = nativeNumericExpression(ctx, message.arguments[0])
    let op = case message.selector
             of "=", "==": "=="
             of "~=": "!="
             else: message.selector
    return fmt("({left} {op} {right})")
  else:
    return ""

proc genExpression*(ctx: GenContext, node: Node): string =
  ## Dispatch to appropriate expression generator

  if node == nil:
    return "NodeValue(kind: vkNil)"

  let representation = numericKind(node, ctx.numericBindings)
  if representation != nrDynamic:
    let native = nativeNumericExpression(ctx, node)
    case representation
    of nrInt: return fmt("NodeValue(kind: vkInt, intVal: {native})")
    of nrFloat: return fmt("NodeValue(kind: vkFloat, floatVal: {native})")
    of nrBool: return fmt("NodeValue(kind: vkBool, boolVal: {native})")
    else: discard

  case node.kind
  of nkLiteral:
    return genLiteral(node.LiteralNode)

  of nkIdent:
    return genSymbolAccess(ctx, node.IdentNode.name)

  of nkMessage:
    return genMessage(ctx, node.MessageNode)

  of nkIf:
    let conditional = node.IfNode
    let condition = genExpression(ctx, conditional.condition)
    let yes = asBlockNode(conditional.thenBranch)
    let no = asBlockNode(conditional.elseBranch)
    let yesCode = if yes != nil: inlineBlockExpression(ctx, yes) else: "nilValue()"
    let noCode = if no != nil: inlineBlockExpression(ctx, no) else: "nilValue()"
    return "(if isTruthy(" & condition & "):\n" & indentBlock(yesCode, 4) &
           " else:\n" & indentBlock(noCode, 4) & ")"

  of nkAssign:
    let assign = node.AssignNode
    let varName = assign.variable
    
    # Infer type from the expression being assigned
    let exprType = ctx.inferTypeFromExpression(assign.expression)
    if exprType.className.len > 0:
      ctx.setVariableType(varName, exprType.className, exprType.isNativeClass)
    
    let exprCode = genExpression(ctx, assign.expression)

    # Check if variable is a slot
    if ctx.isSlot(varName) and not ctx.isLocal(varName):
      if ctx.inMethod and ctx.cls != nil:
        return fmt("setSlotValue(self, \"{varName}\", {exprCode})")
      let idx = ctx.getSlotIndex(varName)
      return fmt("(proc(): NodeValue = self.slots[{idx}] = {exprCode}; return {exprCode})()")
    # Check if it's a local variable (reassignment)
    if ctx.isLocal(varName):
      return fmt("{bindingTarget(ctx, varName)} = {bindingAssignmentValue(ctx, varName, exprCode)}")

    # A Harding global (typically a top-level uppercase variable) assigns the
    # shared binding so main, methods and blocks all observe the same value.
    # Declaring a fresh local here would silently shadow it.
    if varName in ctx.globals:
      return fmt("setGlobal(\"{varName}\", {exprCode})")

    # New local variable assignment
    ctx.locals.add(varName)
    return bindingDeclaration(ctx, varName, exprCode)

  of nkReturn:
    let ret = node.ReturnNode
    let valueCode = if ret.expression != nil: genExpression(ctx, ret.expression) else: "nilValue()"
    if ctx.inBlock and ctx.returnTarget.len > 0:
      return fmt("return raiseNonLocalReturn({ctx.returnTarget}, {valueCode})")
    return "return " & valueCode

  of nkArray:
    let arr = node.ArrayNode
    # Use pre-computed constant value if available
    if arr.isConstant and arr.elements.len > 0:
      return genNodeValueLiteral(arr.cachedValue)
    # Standard code generation
    let elems = arr.elements.mapIt(genExpression(ctx, it)).join(", ")
    return fmt("compiledArray(@[{elems}])")

  of nkTable:
    let tbl = node.TableNode
    # Use pre-computed constant value if available
    if tbl.isConstant and tbl.entries.len > 0:
      return genNodeValueLiteral(tbl.cachedValue)
    # Standard code generation
    var entries: seq[string] = @[]
    for (key, val) in tbl.entries:
      let keyCode = genExpression(ctx, key)
      let valCode = genExpression(ctx, val)
      entries.add(fmt("({keyCode}, {valCode})"))
    return fmt("nt_tableFrom([{entries.join(\", \")}])")

  of nkBlock:
    ## Look up or register the block for compilation and return creation code
    let blockNode = node.BlockNode
    let existingIdx = ctx.blockRegistry.findBlock(blockNode)
    let blockInfo = if existingIdx >= 0:
                      ctx.blockRegistry.blocks[existingIdx]
                    else:
                      registerBlock(ctx.blockRegistry, blockNode, blockCaptureGlobals(ctx), ctx.inMethod,
                                    blockOwnerSlots(ctx), blockOwnerLocals(ctx))

    if blockInfo.captures.len > 0 or blockInfo.ownerMethodId != 0:
      return genCapturedBlockExpression(blockInfo, ctx)
    else:
      return fmt("createBlock(cast[pointer]({blockInfo.nimName}), {blockInfo.paramCount})")

  of nkPseudoVar:
    return genSymbolAccess(ctx, node.PseudoVarNode.name)

  of nkSuperSend:
    let ss = node.SuperSendNode
    let args = ss.arguments.mapIt(genExpression(ctx, it)).join(", ")
    let definingClass = if ctx.cls != nil: ctx.cls.name else: ""
    if definingClass.len > 0:
      if ss.explicitParent.len > 0:
        return fmt("sendSuperMessage(self, \"{definingClass}\", \"{ss.selector}\", @[{args}], \"{ss.explicitParent}\")")
      else:
        return fmt("sendSuperMessage(self, \"{definingClass}\", \"{ss.selector}\", @[{args}])")
    else:
      # Fallback if class context is unavailable
      return fmt("sendMessageHybrid(self, \"{ss.selector}\", @[{args}])")

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
    if ctx.inMethod and ctx.cls != nil:
      var origSlotName = if slotNode.slotName.len > 0: slotNode.slotName else: ""
      for slot in ctx.cls.getAllSlots():
        if slot.index == slotNode.slotIndex:
          origSlotName = slot.name
          break
      if origSlotName.len > 0:
        if slotNode.isAssignment and slotNode.valueExpr != nil:
          let valCode = genExpression(ctx, slotNode.valueExpr)
          return fmt("setSlotValue(self, \"{origSlotName}\", {valCode})")
        else:
          return fmt("getSlotValue(self, \"{origSlotName}\")")

    if slotNode.isAssignment and slotNode.valueExpr != nil:
      let valCode = genExpression(ctx, slotNode.valueExpr)
      return fmt("(proc(): NodeValue = self.slots[{slotNode.slotIndex}] = {valCode}; return {valCode})()")
    else:
      return fmt("self.slots[{slotNode.slotIndex}]")

  of nkNamedAccess:
    let namedNode = node.NamedAccessNode
    let recvCode = genExpression(ctx, namedNode.receiver)
    let directAccess = tryGenerateNamedAccess(ctx, namedNode, recvCode)
    if directAccess.len > 0:
      return directAccess
    if namedNode.isAssignment and namedNode.valueExpr != nil:
      let valCode = genExpression(ctx, namedNode.valueExpr)
      return fmt("sendMessageHybrid({recvCode}, \"at:put:\", @[NodeValue(kind: vkSymbol, symVal: \"{namedNode.memberName}\"), {valCode}])")
    else:
      return fmt("sendMessageHybrid({recvCode}, \"at:\", @[NodeValue(kind: vkSymbol, symVal: \"{namedNode.memberName}\")])")

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
    
    
    # Infer type from the expression being assigned
    let exprType = ctx.inferTypeFromExpression(assign.expression)
    if exprType.className.len > 0:
      ctx.setVariableType(varName, exprType.className, exprType.isNativeClass)
    
    let exprCode = genExpression(ctx, assign.expression)

    # Check if variable is a slot
    if ctx.isSlot(varName) and not ctx.isLocal(varName):
      if ctx.inMethod and ctx.cls != nil:
        return fmt("discard setSlotValue(self, \"{varName}\", {exprCode})")
      let idx = ctx.getSlotIndex(varName)
      return fmt"self.slots[{idx}] = {exprCode}"

    # Check if it's a local variable (reassignment)
    if ctx.isLocal(varName):
      return fmt("{bindingTarget(ctx, varName)} = {bindingAssignmentValue(ctx, varName, exprCode)}")

    # A Harding global assigns the shared binding; in statement position the
    # returned value is discarded.
    if varName in ctx.globals:
      return fmt("discard setGlobal(\"{varName}\", {exprCode})")

    # New local variable assignment
    ctx.locals.add(varName)
    return bindingDeclaration(ctx, varName, exprCode)

  of nkReturn:
    let ret = node.ReturnNode
    let valueCode = if ret.expression != nil: genExpression(ctx, ret.expression) else: "nilValue()"
    if ctx.inBlock and ctx.returnTarget.len > 0:
      return fmt("return raiseNonLocalReturn({ctx.returnTarget}, {valueCode})")
    return "return " & valueCode

  of nkWhile:
    let whileNode = node.WhileNode
    var condCode: string

    let condBlock = asBlockNode(whileNode.condition)
    if condBlock != nil:
      if condBlock.body.len > 0:
        condCode = inlineBlockExpression(ctx, condBlock)
      else:
        condCode = if whileNode.isWhileTrue:
                     "NodeValue(kind: vkBool, boolVal: true)"
                   else:
                     "NodeValue(kind: vkBool, boolVal: false)"
    else:
      condCode = if whileNode.condition != nil:
                   genExpression(ctx, whileNode.condition)
                 else:
                   (if whileNode.isWhileTrue:
                      "NodeValue(kind: vkBool, boolVal: true)"
                    else:
                      "NodeValue(kind: vkBool, boolVal: false)")

    var code = if whileNode.isWhileTrue:
                 "while isTruthy(" & condCode & "):\n"
               else:
                 "while not isTruthy(" & condCode & "):\n"

    let bodyBlock = asBlockNode(whileNode.body)
    if bodyBlock != nil:
      if bodyBlock.body.len == 0:
        code.add("  discard\n")
      else:
        code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
    elif whileNode.body != nil:
      let stmtCode = genStatement(ctx, whileNode.body)
      if stmtCode.len > 0:
        code.add(indentBlock(stmtCode))
    else:
      code.add("  discard\n")
    return code

  of nkIf:
    let ifNode = node.IfNode
    let condCode = if ifNode.condition != nil:
                     genExpression(ctx, ifNode.condition)
                   else:
                     "NodeValue(kind: vkBool, boolVal: false)"

    if ctx.inBlock and
       (hasReturnNode(ifNode.thenBranch) or hasReturnNode(ifNode.elseBranch)):
      # The if branch contains a block whose ^ performs a non-local return.
      # The block cannot be inlined; send it as a real block invocation so
      # its compiled procedure (which raises NonLocalReturnException) runs.
      var runtimeCode = "if isTruthy(" & condCode & "):\n"
      if ifNode.thenBranch != nil:
        runtimeCode.add("  discard sendMessage(currentRuntime[], " & genExpression(ctx, ifNode.thenBranch) & ", \"value\", @[])\n")
      else:
        runtimeCode.add("  discard\n")
      if ifNode.elseBranch != nil:
        runtimeCode.add("else:\n")
        runtimeCode.add("  discard sendMessage(currentRuntime[], " & genExpression(ctx, ifNode.elseBranch) & ", \"value\", @[])\n")
      return runtimeCode

    var code = "if isTruthy(" & condCode & "):\n"

    let thenBlock = asBlockNode(ifNode.thenBranch)
    if thenBlock != nil:
      if thenBlock.body.len == 0:
        code.add("  discard\n")
      else:
        code.add(indentBlock(inlineBlockStatements(ctx, thenBlock)))
    elif ifNode.thenBranch != nil:
      let stmtCode = genStatement(ctx, ifNode.thenBranch)
      if stmtCode.len > 0:
        code.add(indentBlock(stmtCode))
    else:
      code.add("  discard\n")

    if ifNode.elseBranch != nil:
      code.add("else:\n")
      let elseBlock = asBlockNode(ifNode.elseBranch)
      if elseBlock != nil:
        if elseBlock.body.len == 0:
          code.add("  discard\n")
        else:
          code.add(indentBlock(inlineBlockStatements(ctx, elseBlock)))
      else:
        let stmtCode = genStatement(ctx, ifNode.elseBranch)
        if stmtCode.len > 0:
          code.add(indentBlock(stmtCode))
        else:
          code.add("  discard\n")

    return code

  of nkMessage:
    let msg = node.MessageNode
    # Inline control flow in statement context (no value needed)
    case msg.selector
    of "whileTrue:":
      if msg.arguments.len >= 1 and
         not hasReturnNode(msg.arguments[0]) and
         (msg.receiver == nil or not hasReturnNode(msg.receiver)):
        let bodyBlock = asBlockNode(msg.arguments[0])
        if bodyBlock != nil:
          var condCode: string
          let condBlock = asBlockNode(msg.receiver)
          if condBlock != nil:
            if condBlock.body.len > 0:
              condCode = inlineBlockExpression(ctx, condBlock)
            else:
              condCode = "NodeValue(kind: vkBool, boolVal: true)"
          else:
            condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                       else: "NodeValue(kind: vkBool, boolVal: true)"
          var code = "while isTruthy(" & condCode & "):\n"
          code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
          return code

    of "whileFalse:":
      if msg.arguments.len >= 1 and
         not hasReturnNode(msg.arguments[0]) and
         (msg.receiver == nil or not hasReturnNode(msg.receiver)):
        let bodyBlock = asBlockNode(msg.arguments[0])
        if bodyBlock != nil:
          var condCode: string
          let condBlock = asBlockNode(msg.receiver)
          if condBlock != nil:
            if condBlock.body.len > 0:
              condCode = inlineBlockExpression(ctx, condBlock)
            else:
              condCode = "NodeValue(kind: vkBool, boolVal: false)"
          else:
            condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                       else: "NodeValue(kind: vkBool, boolVal: false)"
          var code = "while not isTruthy(" & condCode & "):\n"
          code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
          return code

    of "ifTrue:":
      if msg.arguments.len >= 1 and not hasReturnNode(msg.arguments[0]):
        let thenBlock = asBlockNode(msg.arguments[0])
        if thenBlock != nil:
          let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                         else: "NodeValue(kind: vkBool, boolVal: true)"
          var code = "if isTruthy(" & condCode & "):\n"
          if thenBlock.body.len == 0:
            code.add("  discard\n")
          else:
            code.add(indentBlock(inlineBlockStatements(ctx, thenBlock)))
          return code

    of "ifFalse:":
      if msg.arguments.len >= 1 and not hasReturnNode(msg.arguments[0]):
        let thenBlock = asBlockNode(msg.arguments[0])
        if thenBlock != nil:
          let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                         else: "NodeValue(kind: vkBool, boolVal: false)"
          var code = "if not isTruthy(" & condCode & "):\n"
          if thenBlock.body.len == 0:
            code.add("  discard\n")
          else:
            code.add(indentBlock(inlineBlockStatements(ctx, thenBlock)))
          return code

    of "ifTrue:ifFalse:":
      if msg.arguments.len >= 2 and
         not hasReturnNode(msg.arguments[0]) and
         not hasReturnNode(msg.arguments[1]):
        let thenBlock = asBlockNode(msg.arguments[0])
        let elseBlock = asBlockNode(msg.arguments[1])
        if thenBlock != nil and elseBlock != nil:
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
      if msg.arguments.len >= 1 and not hasReturnNode(msg.arguments[0]):
        let bodyBlock = asBlockNode(msg.arguments[0])
        if bodyBlock != nil:
          let countCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                          else: "NodeValue(kind: vkInt, intVal: 0)"
          var code = "for timesRepeatI in 0..<compiledLoopInt(" & countCode & "):\n"
          if bodyBlock.body.len == 0:
            code.add("  discard\n")
          else:
            code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
          return code

    else:
      discard

    # Messages that mutate collection variables should write the updated value back
    # to the receiver variable when used as a statement.
    if msg.receiver != nil and msg.receiver.kind == nkIdent and msg.selector == "add:":
      let receiverName = msg.receiver.IdentNode.name
      let msgCode = genMessage(ctx, msg)
      if ctx.isSlot(receiverName):
        if ctx.inMethod and ctx.cls != nil:
          return fmt("discard setSlotValue(self, \"{receiverName}\", {msgCode})")
        let slotIdx = ctx.getSlotIndex(receiverName)
        if slotIdx >= 0:
          return fmt("self.slots[{slotIdx}] = {msgCode}")
      elif ctx.isLocal(receiverName):
        return fmt("{bindingTarget(ctx, receiverName)} = {msgCode}")
      elif receiverName in ctx.globals:
        return fmt("discard setGlobal(\"{receiverName}\", {msgCode})")

    # Default: message send as statement
    let msgCode = genMessage(ctx, node.MessageNode)
    return "discard " & msgCode

  of nkPrimitiveCall:
    # Primitive call as statement
    let primCall = node.PrimitiveCallNode
    let args = primCall.arguments.mapIt(genExpression(ctx, it)).join(", ")
    return "discard callPrimitive(\"" & primCall.selector & "\", @[" & args & "])"

  else:
    # For other nodes, just generate the expression
    let exprCode = genExpression(ctx, node)
    if exprCode.len > 0:
      return "discard " & exprCode
    return ""

proc genBlockBody*(ctx: GenContext, blkNode: BlockNode, captures: seq[string] = @[],
                   hasNonLocalReturn: bool = false, envStructName: string = "",
                   targetMethodId: int = 0): string =
  ## Generate code for block body (sequence of statements)
  ## captures: list of captured variable names (from BlockProcInfo)
  ## hasNonLocalReturn: if true, ^ generates NonLocalReturnException
  ## targetMethodId: lexical owner metadata; nonzero environments carry the invocation target
  var output = ""

  # Create new context for block body with its parameters
  # Share the blockRegistry so nested blocks can be looked up
  var bodyCtx = GenContext(
    cls: ctx.cls,
    inBlock: true,
    returnTarget: (if not hasNonLocalReturn: ""
                   elif targetMethodId != 0: "hardingHome" else: "nil"),
    inMethod: ctx.inMethod,
    mixed: ctx.mixed,
    locals: @[],
    parameters: @[],
    globals: ctx.globals,
    blockRegistry: ctx.blockRegistry,
    varTypes: ctx.varTypes,
    compiledClasses: ctx.compiledClasses,
    classInfo: ctx.classInfo,
    cellNames: scopeCaptureCellNames(blkNode.body, blkNode.parameters & blkNode.temporaries)
  )
  for param in blkNode.parameters:
    bodyCtx.parameters.add(param)
    output.add("  " & bindingDeclaration(bodyCtx, param, "hardingArg_" & mangleIdentifier(param)) & "\n")

  # Extract captured variables from environment struct
  if captures.len > 0 or targetMethodId != 0:
    if envStructName.len > 0:
      output.add(fmt("  let envTyped = cast[{envStructName}](env)\n"))
      if targetMethodId != 0:
        output.add("  let hardingHome = envTyped.home\n")
    for capture in captures:
      if envStructName.len > 0:
        if capture == "self":
          output.add("  let self = envTyped[].self.value\n")
        else:
          let identifier = mangleIdentifier(capture)
          output.add(fmt("  let {identifier} = envTyped[].{identifier}\n"))
          if capture notin bodyCtx.cellNames:
            bodyCtx.cellNames.add(capture)
      else:
        output.add("  " & bindingDeclaration(bodyCtx, capture, "NodeValue(kind: vkNil)") & "\n")
      bodyCtx.locals.add(capture)

  output.add(indentBlock(genLocalDeclarations(bodyCtx, blkNode.temporaries)))

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
      let target = if targetMethodId != 0: "hardingHome" else: "nil"
      output.add(fmt("  return raiseNonLocalReturn({target}, {exprCode})\n"))
    elif i == blkNode.body.len - 1 and stmt.kind in {nkIf, nkWhile}:
      let stmtCode = genStatement(bodyCtx, stmt)
      if stmtCode.len > 0:
        output.add(indentBlock(stmtCode))
      output.add("  return NodeValue(kind: vkNil)\n")
    elif i == blkNode.body.len - 1 and stmt.kind notin {nkReturn, nkAssign}:
      # Last statement is the return value
      let exprCode = genExpression(bodyCtx, stmt)
      output.add("  return " & exprCode & "\n")
    else:
      let stmtCode = genStatement(bodyCtx, stmt)
      if stmtCode.len > 0:
        output.add(indentBlock(stmtCode))


  return output

proc genTemporaries*(tmp: seq[string]): string =
  ## Generate temporary variable declarations
  if tmp.len == 0:
    return ""

  var output = "  # Temporaries\n"
  for t in tmp:
    output.add(fmt("  var {mangleIdentifier(t)} = NodeValue(kind: vkNil)\n"))
  output.add("\n")
  return output

proc asBlockNode(node: Node): BlockNode =
  ## Get BlockNode from either nkBlock or nkLiteral(vkBlock)
  if node == nil:
    return nil
  case node.kind
  of nkBlock:
    return node.BlockNode
  of nkLiteral:
    let lit = node.LiteralNode.value
    if lit.kind == vkBlock:
      return lit.blockVal
    return nil
  else:
    return nil

proc isBlockWithCaptures*(ctx: GenContext, node: Node): tuple[isBlock: bool, blockInfo: BlockProcInfo] =
  ## Check if a node is a block literal that requires captures
  ## Returns (true, blockInfo) if it's a block with captures, (false, default) otherwise
  let blockNode = asBlockNode(node)
  if blockNode == nil:
    return (false, default(BlockProcInfo))
  
  # Look up or register the block
  let existingIdx = ctx.blockRegistry.findBlock(blockNode)
  let blockInfo = if existingIdx >= 0:
                    ctx.blockRegistry.blocks[existingIdx]
                  else:
                    registerBlock(ctx.blockRegistry, blockNode, blockCaptureGlobals(ctx), ctx.inMethod,
                                  blockOwnerSlots(ctx), blockOwnerLocals(ctx))
  
  if blockInfo.captures.len > 0:
    return (true, blockInfo)
  else:
    return (false, default(BlockProcInfo))

proc genParameters*(params: seq[string]): string =
  ## Generate parameter declarations for method signature
  if params.len == 0:
    return ""

  var parts: seq[string] = @[]
  for p in params:
    parts.add(fmt("{mangleIdentifier(p)}: NodeValue"))
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
    
    
    # Infer type from the expression being assigned
    let exprType = ctx.inferTypeFromExpression(assign.expression)
    if exprType.className.len > 0:
      ctx.setVariableType(varName, exprType.className, exprType.isNativeClass)
    
    let exprCode = genExpression(ctx, assign.expression)

    # A top-level uppercase name is a Harding global: assign the shared binding
    # instead of declaring a local, so methods and blocks observe it too.
    if varName in ctx.globals:
      return fmt("discard setGlobal(\"{varName}\", {exprCode})")

    # Reassignment of an existing script-local variable
    if varName in ctx.locals:
      return fmt("{bindingTarget(ctx, varName)} = {bindingAssignmentValue(ctx, varName, exprCode)}")

    # New top-level variable: a local of main, visible to blocks nested in main.
    ctx.locals.add(varName)
    return bindingDeclaration(ctx, varName, exprCode)

  of nkMessage:
    # Top-level message send - delegate to genStatement for inline control flow
    return genStatement(ctx, node)

  of nkWhile, nkIf:
    # Top-level specialized control-flow nodes
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
