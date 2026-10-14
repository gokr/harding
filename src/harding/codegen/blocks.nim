import std/[tables, sequtils, strformat, sets, strutils]
import ../core/types
import ../compiler/symbols

# Note: We cannot import expression.nim here due to circular dependency
# (expression.nim imports blocks.nim)
# Block body generation is handled separately in module.nim during code generation

proc escapeNimStringLocal(s: string): string =
  ## Escape a string for use in Nim code
  result = s
  result = result.replace("\\", "\\\\")
  result = result.replace("\"", "\\\"")
  result = result.replace("\n", "\\n")
  result = result.replace("\r", "\\r")
  result = result.replace("\t", "\\t")

type
  GenContext* = ref object
    locals*: seq[string]
    parameters*: seq[string]

proc genBlockExpr*(ctx: GenContext, node: Node): string =
  if node == nil:
    return "NodeValue(kind: vkNil)"
  
  case node.kind
  of nkLiteral:
    let lit = node.LiteralNode
    case lit.value.kind
    of vkInt:
      return fmt("NodeValue(kind: vkInt, intVal: {lit.value.intVal})")
    of vkFloat:
      return fmt("NodeValue(kind: vkFloat, floatVal: {lit.value.floatVal})")
    of vkString:
      return fmt("NodeValue(kind: vkString, strVal: \"{escapeNimStringLocal(lit.value.strVal)}\")")
    of vkNil:
      return "NodeValue(kind: vkNil)"
    of vkBool:
      return fmt("NodeValue(kind: vkBool, boolVal: {lit.value.boolVal})")
    of vkSymbol:
      return fmt("NodeValue(kind: vkSymbol, symVal: \"{lit.value.symVal}\")")
    of vkArray:
      return "NodeValue(kind: vkArray, arrayVal: @[])"
    of vkTable:
      return "NodeValue(kind: vkTable, tableVal: initTable[string, NodeValue]())"
    else:
      return "NodeValue(kind: vkNil)"
  
  of nkIdent:
    let ident = node.IdentNode
    # Check if it's a local or parameter
    if ident.name in ctx.parameters:
      return mangleIdentifier(ident.name)
    if ident.name in ctx.locals:
      return mangleIdentifier(ident.name)
    # Otherwise it's a slot or global - use runtime
    return fmt("getSlotValue(self, \"{ident.name}\")")
  
  of nkMessage:
    let msg = node.MessageNode
    let recv = genBlockExpr(ctx, msg.receiver)
    var args: seq[string] = @[]
    for arg in msg.arguments:
      args.add(genBlockExpr(ctx, arg))
    return fmt("sendMessageBlock({recv}, \"{msg.selector}\", @[{args.join(\", \")}])")
  
  of nkAssign:
    let assign = node.AssignNode
    let expr = genBlockExpr(ctx, assign.expression)
    let identifier = mangleIdentifier(assign.variable)
    return fmt("({identifier} = {expr}; {identifier})")
  
  else:
    return "NodeValue(kind: vkNil)"

# ============================================================================
# Block Registry for Code Generation
# Tracks blocks that need to be compiled to Nim procedures
# ============================================================================

type
  # Block procedure types for compiled code
  BlockProc0* = proc(): NodeValue {.cdecl.}
  BlockProc1* = proc(a: NodeValue): NodeValue {.cdecl.}
  BlockProc2* = proc(a, b: NodeValue): NodeValue {.cdecl.}
  BlockProc3* = proc(a, b, c: NodeValue): NodeValue {.cdecl.}
  BlockEnvProc0* = proc(env: pointer): NodeValue {.cdecl.}
  BlockEnvProc1* = proc(env: pointer, a: NodeValue): NodeValue {.cdecl.}
  BlockEnvProc2* = proc(env: pointer, a, b: NodeValue): NodeValue {.cdecl.}
  BlockEnvProc3* = proc(env: pointer, a, b, c: NodeValue): NodeValue {.cdecl.}

  BlockProcInfo* = object
    ## Metadata for a compiled block procedure
    nimName*: string                    # Unique Nim procedure name
    blockNode*: BlockNode               # Original AST node
    captures*: seq[string]              # Captured variable names
    captureTypes*: seq[string]          # Types for captured variables (NodeValue)
    hasNonLocalReturn*: bool            # Does block contain ^ (return)?
    homeInMethod*: bool                 # Whether the block home is a method body
    ownerMethodId*: int                 # Id of the compiled method this block is lexically inside (0 = top-level)
    paramCount*: int                    # Number of block parameters
    envStructName*: string              # Name of environment struct

  BlockRegistry* = ref object
    ## Registry of blocks to be compiled
    blocks*: seq[BlockProcInfo]         # All registered blocks
    blockCounter*: int                  # For generating unique names
    captureCache*: Table[string, seq[string]]  # Cache capture analysis results

proc newBlockRegistry*(): BlockRegistry =
  ## Create a new empty block registry
  result = BlockRegistry()
  result.blocks = @[]
  result.blockCounter = 0
  result.captureCache = initTable[string, seq[string]]()

proc generateBlockName*(reg: BlockRegistry): string =
  ## Generate a unique Nim procedure name for a block
  ## Use "harding_block_" prefix to avoid conflicts with user variables
  result = fmt("harding_block_{reg.blockCounter}")
  reg.blockCounter += 1

proc generateEnvStructName*(reg: BlockRegistry): string =
  ## Generate a unique environment struct name
  result = fmt("BlockEnv_{reg.blockCounter}")

proc collectIdentRefs(node: Node, refs: var HashSet[string]) =
  ## Recursively collect all identifier references from an AST node
  if node == nil:
    return

  case node.kind
  of nkIdent:
    refs.incl(node.IdentNode.name)

  of nkMessage:
    let msg = node.MessageNode
    if msg.receiver != nil:
      collectIdentRefs(msg.receiver, refs)
    for arg in msg.arguments:
      collectIdentRefs(arg, refs)

  of nkAssign:
    let assign = node.AssignNode
    # Only process the expression side - the assigned variable is a new binding
    # not a reference to an outer variable (it may shadow, but that's handled elsewhere)
    collectIdentRefs(assign.expression, refs)

  of nkReturn:
    let ret = node.ReturnNode
    if ret.expression != nil:
      collectIdentRefs(ret.expression, refs)

  of nkArray:
    let arr = node.ArrayNode
    for elem in arr.elements:
      collectIdentRefs(elem, refs)

  of nkTable:
    let tbl = node.TableNode
    for (key, val) in tbl.entries:
      collectIdentRefs(key, refs)
      collectIdentRefs(val, refs)

  of nkBlock:
    # Nested block: collect its free variables (subtract its own params/temps)
    let blk = node.BlockNode
    var nestedRefs = initHashSet[string]()
    for stmt in blk.body:
      collectIdentRefs(stmt, nestedRefs)
    # Subtract nested block's own parameters and temporaries
    for param in blk.parameters:
      nestedRefs.excl(param)
    for temp in blk.temporaries:
      nestedRefs.excl(temp)
    # What remains are free variables of the nested block,
    # which are also references in our scope
    for name in nestedRefs:
      refs.incl(name)

  of nkCascade:
    let cascade = node.CascadeNode
    if cascade.receiver != nil:
      collectIdentRefs(cascade.receiver, refs)
    for msg in cascade.messages:
      collectIdentRefs(msg, refs)

  of nkPseudoVar:
    refs.incl(node.PseudoVarNode.name)

  of nkSlotAccess:
    let slotNode = node.SlotAccessNode
    # Slot reads and writes both compile to getSlotValue/setSlotValue on the
    # receiver, so a block touching a slot needs `self` in its environment.
    refs.incl("self")
    if slotNode.isAssignment and slotNode.valueExpr != nil:
      collectIdentRefs(slotNode.valueExpr, refs)

  of nkSuperSend:
    refs.incl("self")
    let ss = node.SuperSendNode
    for arg in ss.arguments:
      collectIdentRefs(arg, refs)

  of nkPrimitiveCall:
    let primCall = node.PrimitiveCallNode
    for arg in primCall.arguments:
      collectIdentRefs(arg, refs)

  of nkIf:
    let conditional = node.IfNode
    collectIdentRefs(conditional.condition, refs)
    collectIdentRefs(conditional.thenBranch, refs)
    collectIdentRefs(conditional.elseBranch, refs)

  of nkWhile:
    let loop = node.WhileNode
    collectIdentRefs(loop.condition, refs)
    collectIdentRefs(loop.body, refs)

  of nkNamedAccess:
    let access = node.NamedAccessNode
    collectIdentRefs(access.receiver, refs)
    collectIdentRefs(access.valueExpr, refs)

  else:
    discard

const pseudoVars = ["self", "nil", "true", "false", "super", "thisContext"]

proc collectAssignedVars*(node: Node, assigned: var HashSet[string]) =
  ## Recursively collect all variables that are assigned to in the AST
  if node == nil:
    return
  
  case node.kind
  of nkAssign:
    let assign = node.AssignNode
    assigned.incl(assign.variable)
    collectAssignedVars(assign.expression, assigned)
  of nkBlock:
    for stmt in node.BlockNode.body:
      collectAssignedVars(stmt, assigned)
  of nkMessage:
    let msg = node.MessageNode
    if msg.receiver != nil:
      collectAssignedVars(msg.receiver, assigned)
    for arg in msg.arguments:
      collectAssignedVars(arg, assigned)
  of nkReturn:
    if node.ReturnNode.expression != nil:
      collectAssignedVars(node.ReturnNode.expression, assigned)
  of nkArray:
    for elem in node.ArrayNode.elements:
      collectAssignedVars(elem, assigned)
  of nkTable:
    for (key, val) in node.TableNode.entries:
      collectAssignedVars(key, assigned)
      collectAssignedVars(val, assigned)
  of nkCascade:
    let cascade = node.CascadeNode
    if cascade.receiver != nil:
      collectAssignedVars(cascade.receiver, assigned)
    for msg in cascade.messages:
      collectAssignedVars(msg, assigned)
  of nkIf:
    let conditional = node.IfNode
    collectAssignedVars(conditional.condition, assigned)
    collectAssignedVars(conditional.thenBranch, assigned)
    collectAssignedVars(conditional.elseBranch, assigned)
  of nkWhile:
    let loop = node.WhileNode
    collectAssignedVars(loop.condition, assigned)
    collectAssignedVars(loop.body, assigned)
  of nkNamedAccess:
    let access = node.NamedAccessNode
    collectAssignedVars(access.receiver, assigned)
    collectAssignedVars(access.valueExpr, assigned)
  else:
    discard

proc analyzeCaptures*(blockNode: BlockNode, knownGlobals: seq[string] = @[],
                      ownerSlotNames: seq[string] = @[],
                      ownerLocalNames: seq[string] = @[]): seq[string] =
  ## Analyze a block to find free variables that need capture
  ## Returns list of variable names that need to be captured from enclosing scope
  ##
  ## ownerSlotNames: slots of the class owning the enclosing method. A slot read
  ## compiles to `getSlotValue(self, ...)`, so a block that names a slot needs
  ## `self` captured even though it never spells `self` itself.
  ##
  ## ownerLocalNames: parameters and temporaries of the enclosing method. These
  ## shadow same-named slots, so they must still be captured as ordinary
  ## enclosing locals rather than treated as slot accesses.
  var allRefs = initHashSet[string]()

  # Collect all identifier references from block body
  for stmt in blockNode.body:
    collectIdentRefs(stmt, allRefs)

  # Build set of names that are local to this block
  var locals = initHashSet[string]()
  for param in blockNode.parameters:
    locals.incl(param)
  for temp in blockNode.temporaries:
    locals.incl(temp)
  
  # Collect variables assigned in the block body
  var assigned = initHashSet[string]()
  for stmt in blockNode.body:
    collectAssignedVars(stmt, assigned)
  
  # Variables that are assigned but NOT referenced are local (not captures)
  # Variables that are referenced (even if also assigned) need capture
  for name in assigned:
    if name in ownerLocalNames and name notin locals:
      allRefs.incl(name)
    elif name notin allRefs:
      locals.incl(name)

  # Subtract locals, pseudo-variables, and known globals
  var captures: seq[string] = @[]
  var needsSelf = false
  for name in allRefs:
    if name in locals:
      continue
    if name in ownerLocalNames:
      # A locally declared name in the enclosing method shadows the slot, so it
      # is an ordinary captured variable, not a receiver access.
      captures.add(name)
      continue
    if name in ownerSlotNames:
      # A slot read or write goes through the receiver, so the block needs it.
      needsSelf = true
      continue
    if name in pseudoVars and name != "self":
      continue
    if name in knownGlobals:
      continue
    captures.add(name)

  if needsSelf and "self" notin captures:
    captures.add("self")

  return captures

proc hasReturnNode*(node: Node): bool =
  ## Recursively check if node contains a return statement
  if node == nil:
    return false
  if node of ReturnNode:
    return true
  
  # Check different node types recursively
  if node of BlockNode:
    for stmt in node.BlockNode.body:
      if hasReturnNode(stmt):
        return true
  elif node of MessageNode:
    let msg = node.MessageNode
    if hasReturnNode(msg.receiver):
      return true
    for arg in msg.arguments:
      if hasReturnNode(arg):
        return true
  elif node of AssignNode:
    return hasReturnNode(node.AssignNode.expression)
  elif node of ArrayNode:
    for elem in node.ArrayNode.elements:
      if hasReturnNode(elem):
        return true
  elif node of TableNode:
    for (key, val) in node.TableNode.entries:
      if hasReturnNode(key) or hasReturnNode(val):
        return true
  elif node of CascadeNode:
    let cas = node.CascadeNode
    if hasReturnNode(cas.receiver):
      return true
    for msg in cas.messages:
      if hasReturnNode(msg):
        return true
  elif node of IfNode:
    let ifNode = node.IfNode
    return hasReturnNode(ifNode.condition) or
           hasReturnNode(ifNode.thenBranch) or
           hasReturnNode(ifNode.elseBranch)
  elif node of WhileNode:
    let whileNode = node.WhileNode
    return hasReturnNode(whileNode.condition) or
           hasReturnNode(whileNode.body)
  elif node of SlotAccessNode:
    return hasReturnNode(node.SlotAccessNode.valueExpr)
  elif node of NamedAccessNode:
    return hasReturnNode(node.NamedAccessNode.receiver) or
           hasReturnNode(node.NamedAccessNode.valueExpr)
  elif node of SuperSendNode:
    for arg in node.SuperSendNode.arguments:
      if hasReturnNode(arg):
        return true
  elif node of PrimitiveCallNode:
    for arg in node.PrimitiveCallNode.arguments:
      if hasReturnNode(arg):
        return true

  return false

proc registerBlock*(reg: BlockRegistry, blockNode: BlockNode, knownGlobals: seq[string] = @[],
                    homeInMethod: bool = false,
                    ownerSlotNames: seq[string] = @[],
                    ownerLocalNames: seq[string] = @[]): BlockProcInfo =
  ## Register a block for compilation and return its metadata
  let nimName = reg.generateBlockName()
  let envName = reg.generateEnvStructName()

  # Analyze captures
  let captures = analyzeCaptures(blockNode, knownGlobals, ownerSlotNames, ownerLocalNames)

  # Check for non-local returns (^) recursively in block body
  var hasNonLocalReturn = false
  for stmt in blockNode.body:
    if hasReturnNode(stmt):
      hasNonLocalReturn = true
      break

  result = BlockProcInfo(
    nimName: nimName,
    blockNode: blockNode,
    captures: captures,
    captureTypes: captures.mapIt("MutableCell"),
    hasNonLocalReturn: hasNonLocalReturn,
    homeInMethod: homeInMethod,
    ownerMethodId: 0,
    paramCount: blockNode.parameters.len,
    envStructName: envName
  )

  reg.blocks.add(result)

proc getAllBlocks*(reg: BlockRegistry): seq[BlockProcInfo] =
  ## Get all registered blocks
  return reg.blocks

proc findBlock*(reg: BlockRegistry, blockNode: BlockNode): int =
  ## Find a block by AST node identity, returns index or -1
  for i, info in reg.blocks:
    if info.blockNode == blockNode:
      return i
  return -1

proc dumpBlockRegistry*(reg: BlockRegistry) =
  ## Debug: dump all blocks in registry
  discard

proc generateEnvStructDef*(info: BlockProcInfo): string =
  ## Generate the environment struct definition for a block
  if info.captures.len == 0 and info.ownerMethodId == 0:
    return ""

  var output = fmt("type {info.envStructName}* = ref object of RootObj")
  if info.ownerMethodId != 0:
    output.add("\n  home: CompiledReturnTarget")
  for i, capture in info.captures:
    let typ = info.captureTypes[i]
    output.add(fmt("\n  {mangleIdentifier(capture)}: {typ}"))
  return output

proc generateBlockProcSignature*(info: BlockProcInfo): string =
  ## Generate the procedure signature for a block
  ## Uses 'pointer' for env to match template expectations
  var params: seq[string] = @[]

  # Add environment pointer if there are captures
  if info.captures.len > 0 or info.ownerMethodId != 0:
    params.add("env: pointer")

  # Add block parameters using actual names from the BlockNode
  for i in 0..<info.paramCount:
    let paramName = if i < info.blockNode.parameters.len:
                      info.blockNode.parameters[i]
                    else:
                      fmt("param{i}")
    params.add(fmt("hardingArg_{mangleIdentifier(paramName)}: NodeValue"))

  let paramsStr = params.join(", ")
  result = fmt("proc {info.nimName}*({paramsStr}): NodeValue {{.cdecl.}}")

proc generateBlockProcBody*(info: BlockProcInfo): string =
  ## Generate the procedure body for a block
  ## - Extract captures from environment
  ## - Generate basic body code
  ## - Handle implicit returns for last expression
  var output = ""
  let ctx = GenContext(locals: @[], parameters: @[])

  # If we have captures, cast env pointer and extract values
  if info.captures.len > 0:
    output.add(fmt("  let envTyped = cast[{info.envStructName}](env)\n"))
    for capture in info.captures:
      let identifier = mangleIdentifier(capture)
      output.add(fmt("  let {identifier} = envTyped.{identifier}.value\n"))

  for parameter in info.blockNode.parameters:
    let identifier = mangleIdentifier(parameter)
    output.add(fmt("  var {identifier} = hardingArg_{identifier}\n"))

  # Generate temporaries
  if info.blockNode.temporaries.len > 0:
    output.add("  # Temporaries\n")
    for temp in info.blockNode.temporaries:
      output.add(fmt("  var {mangleIdentifier(temp)} = NodeValue(kind: vkNil)\n"))
    output.add("\n")

  # Get body statements
  let body = info.blockNode.body
  if body.len == 0:
    output.add("  return NodeValue(kind: vkNil)\n")
    return output

  # Generate body statements with basic literal handling
  var hasReturn = false
  for i, stmt in body:
    let isLast = (i == body.len - 1)
    
    case stmt.kind
    of nkReturn:
      let ret = stmt.ReturnNode
      if ret.expression != nil and ret.expression.kind == nkLiteral:
        let lit = ret.expression.LiteralNode
        case lit.value.kind
        of vkInt:
          output.add(fmt("  return NodeValue(kind: vkInt, intVal: {lit.value.intVal})\n"))
        of vkFloat:
          output.add(fmt("  return NodeValue(kind: vkFloat, floatVal: {lit.value.floatVal})\n"))
        of vkString:
          output.add(fmt("  return NodeValue(kind: vkString, strVal: \"{escapeNimStringLocal(lit.value.strVal)}\")\n"))
        of vkNil:
          output.add("  return NodeValue(kind: vkNil)\n")
        else:
          output.add("  return NodeValue(kind: vkNil)\n")
      else:
        output.add("  return NodeValue(kind: vkNil)  # return via runtime\n")
      hasReturn = true
      
    of nkAssign:
      let assign = stmt.AssignNode
      if assign.expression.kind == nkLiteral:
        let lit = assign.expression.LiteralNode
        case lit.value.kind
        of vkInt:
          output.add(fmt("  var {mangleIdentifier(assign.variable)} = NodeValue(kind: vkInt, intVal: {lit.value.intVal})\n"))
        of vkFloat:
          output.add(fmt("  var {mangleIdentifier(assign.variable)} = NodeValue(kind: vkFloat, floatVal: {lit.value.floatVal})\n"))
        of vkString:
          output.add(fmt("  var {mangleIdentifier(assign.variable)} = NodeValue(kind: vkString, strVal: \"{escapeNimStringLocal(lit.value.strVal)}\")\n"))
        of vkNil:
          output.add(fmt("  var {mangleIdentifier(assign.variable)} = NodeValue(kind: vkNil)\n"))
        else:
          output.add(fmt("  var {mangleIdentifier(assign.variable)} = NodeValue(kind: vkNil)\n"))
      else:
        output.add(fmt("  var {mangleIdentifier(assign.variable)} = NodeValue(kind: vkNil)  # assigned via runtime\n"))
        
    of nkMessage:
      # Generate message send code
      let msg = stmt.MessageNode
      let recvCode = genBlockExpr(ctx, msg.receiver)
      var code = recvCode
      
      # Handle different message types
      case msg.selector
      of "+", "-", "*", "/", "//", "%":
        # Binary arithmetic
        if msg.arguments.len > 0:
          let argCode = genBlockExpr(ctx, msg.arguments[0])
          code = fmt("binaryOp_{msg.selector}({recvCode}, {argCode})")
      of "at:":
        if msg.arguments.len > 0:
          let argCode = genBlockExpr(ctx, msg.arguments[0])
          code = fmt("collectionAt({recvCode}, {argCode})")
      of "at:put:":
        if msg.arguments.len > 1:
          let keyCode = genBlockExpr(ctx, msg.arguments[0])
          let valCode = genBlockExpr(ctx, msg.arguments[1])
          code = fmt("collectionAtPut({recvCode}, {keyCode}, {valCode})")
      else:
        # Generic message - use runtime
        var args = "@["
        for j, arg in msg.arguments:
          if j > 0: args.add(", ")
          args.add(genBlockExpr(ctx, arg))
        args.add("]")
        code = fmt("sendMessageBlock({recvCode}, \"{msg.selector}\", {args})")
      
      if isLast:
        output.add("  return " & code & "\n")
      else:
        output.add("  discard " & code & "\n")
      hasReturn = isLast
        
    of nkLiteral:
      if isLast:
        let lit = stmt.LiteralNode
        case lit.value.kind
        of vkInt:
          output.add(fmt("  return NodeValue(kind: vkInt, intVal: {lit.value.intVal})\n"))
        of vkFloat:
          output.add(fmt("  return NodeValue(kind: vkFloat, floatVal: {lit.value.floatVal})\n"))
        of vkString:
          output.add(fmt("  return NodeValue(kind: vkString, strVal: \"{escapeNimStringLocal(lit.value.strVal)}\")\n"))
        of vkNil:
          output.add("  return NodeValue(kind: vkNil)\n")
        else:
          output.add("  return NodeValue(kind: vkNil)\n")
        hasReturn = true
      
    else:
      if isLast:
        output.add("  return NodeValue(kind: vkNil)\n")
        hasReturn = true

  if not hasReturn:
    output.add("  return NodeValue(kind: vkNil)\n")

  return output

# Forward declaration - implemented in expression.nim
# Note: GenContext is defined in expression.nim, we use it as a parameter here

proc isLiteralBlock*(node: Node): bool =
  ## Check if a node is a literal block (for inline compilation)
  return node of BlockNode

proc getBlockParameters*(node: Node): seq[string] =
  ## Get parameter names from a block node
  if node of BlockNode:
    return node.BlockNode.parameters
  return @[]

proc getBlockBody*(node: Node): seq[Node] =
  ## Get body statements from a block node
  if node of BlockNode:
    return node.BlockNode.body
  return @[]

const inlineControlSelectors = [
  "ifTrue:", "ifFalse:", "ifTrue:ifFalse:",
  "whileTrue:", "whileFalse:",
  "timesRepeat:", "to:by:do:",
  "do:", "collect:", "select:"
]

proc collectBlocks*(registry: BlockRegistry, node: Node, knownGlobals: seq[string] = @[],
                    ownerSlotNames: seq[string] = @[],
                    ownerLocalNames: seq[string] = @[]) =
  ## Recursively collect all blocks from an AST node
  ## This populates the block registry before code generation
  ## Blocks that will be inlined by control flow are NOT registered
  if node == nil:
    return

  case node.kind
  of nkBlock:
    # Standalone blocks (not part of control flow) get registered
    discard registerBlock(registry, node.BlockNode, knownGlobals, false, ownerSlotNames,
                   ownerLocalNames)
    # Recursively collect blocks in the body
    for stmt in node.BlockNode.body:
      collectBlocks(registry, stmt, knownGlobals, ownerSlotNames, ownerLocalNames)

  of nkMessage:
    let msg = node.MessageNode
    let isInlineControl = msg.selector in inlineControlSelectors

    if isInlineControl:
      # For inline control flow, skip registration of literal block arguments
      # and the receiver block (for whileTrue:/whileFalse:) — but only when
      # the block will actually be inlined (no returns). Blocks containing ^
      # cannot be inlined and must be registered so their procedures get
      # generated and referenced consistently.
      if msg.receiver != nil:
        if msg.receiver.kind == nkBlock and hasReturnNode(msg.receiver):
          discard registerBlock(registry, msg.receiver.BlockNode, knownGlobals, false,
                         ownerSlotNames, ownerLocalNames)
          for stmt in msg.receiver.BlockNode.body:
            collectBlocks(registry, stmt, knownGlobals, ownerSlotNames, ownerLocalNames)
        elif msg.receiver.kind == nkBlock:
          for stmt in msg.receiver.BlockNode.body:
            collectBlocks(registry, stmt, knownGlobals, ownerSlotNames, ownerLocalNames)
        else:
          collectBlocks(registry, msg.receiver, knownGlobals, ownerSlotNames, ownerLocalNames)
      for arg in msg.arguments:
        if arg.kind == nkBlock and hasReturnNode(arg):
          discard registerBlock(registry, arg.BlockNode, knownGlobals, false,
                         ownerSlotNames, ownerLocalNames)
          for stmt in arg.BlockNode.body:
            collectBlocks(registry, stmt, knownGlobals, ownerSlotNames, ownerLocalNames)
        elif arg.kind == nkBlock:
          for stmt in arg.BlockNode.body:
            collectBlocks(registry, stmt, knownGlobals, ownerSlotNames, ownerLocalNames)
        else:
          collectBlocks(registry, arg, knownGlobals, ownerSlotNames, ownerLocalNames)
    else:
      # Not inline control flow - process normally
      if msg.receiver != nil:
        collectBlocks(registry, msg.receiver, knownGlobals, ownerSlotNames, ownerLocalNames)
      for arg in msg.arguments:
        collectBlocks(registry, arg, knownGlobals, ownerSlotNames, ownerLocalNames)

  of nkAssign:
    let assign = node.AssignNode
    collectBlocks(registry, assign.expression, knownGlobals, ownerSlotNames, ownerLocalNames)

  of nkReturn:
    let ret = node.ReturnNode
    if ret.expression != nil:
      collectBlocks(registry, ret.expression, knownGlobals, ownerSlotNames, ownerLocalNames)

  of nkArray:
    let arr = node.ArrayNode
    for elem in arr.elements:
      collectBlocks(registry, elem, knownGlobals, ownerSlotNames, ownerLocalNames)

  of nkTable:
    let tbl = node.TableNode
    for (key, val) in tbl.entries:
      collectBlocks(registry, key, knownGlobals, ownerSlotNames, ownerLocalNames)
      collectBlocks(registry, val, knownGlobals, ownerSlotNames, ownerLocalNames)

  of nkIf:
    let conditional = node.IfNode
    collectBlocks(registry, conditional.condition, knownGlobals, ownerSlotNames, ownerLocalNames)
    for branch in [conditional.thenBranch, conditional.elseBranch]:
      if branch != nil and branch.kind == nkBlock and not hasReturnNode(branch):
        for statement in branch.BlockNode.body:
          collectBlocks(registry, statement, knownGlobals, ownerSlotNames, ownerLocalNames)
      else:
        collectBlocks(registry, branch, knownGlobals, ownerSlotNames, ownerLocalNames)

  of nkWhile:
    let loop = node.WhileNode
    for part in [loop.condition, loop.body]:
      if part != nil and part.kind == nkBlock and not hasReturnNode(part):
        for statement in part.BlockNode.body:
          collectBlocks(registry, statement, knownGlobals, ownerSlotNames, ownerLocalNames)
      else:
        collectBlocks(registry, part, knownGlobals, ownerSlotNames, ownerLocalNames)

  else:
    # Other node types don't contain blocks
    discard
