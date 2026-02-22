import std/[tables, sequtils, strformat, sets, strutils]
import ../core/types

# ============================================================================
# Block Registry for Code Generation
# Tracks blocks that need to be compiled to Nim procedures
# ============================================================================

type
  # Block procedure types for compiled code
  # These are used both in code generation and at runtime
  BlockProc0* = proc(): NodeValue {.cdecl.}
  BlockProc1* = proc(a: NodeValue): NodeValue {.cdecl.}
  BlockProc2* = proc(a, b: NodeValue): NodeValue {.cdecl.}
  BlockProc3* = proc(a, b, c: NodeValue): NodeValue {.cdecl.}
  # Block procs with environment pointer
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
  result = fmt("block_{reg.blockCounter}")
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
    if slotNode.isAssignment and slotNode.valueExpr != nil:
      collectIdentRefs(slotNode.valueExpr, refs)

  of nkSuperSend:
    let ss = node.SuperSendNode
    for arg in ss.arguments:
      collectIdentRefs(arg, refs)

  of nkPrimitiveCall:
    let primCall = node.PrimitiveCallNode
    for arg in primCall.arguments:
      collectIdentRefs(arg, refs)

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
  else:
    discard

proc analyzeCaptures*(blockNode: BlockNode, knownGlobals: seq[string] = @[]): seq[string] =
  ## Analyze a block to find free variables that need capture
  ## Returns list of variable names that need to be captured from enclosing scope
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
    if name notin allRefs:
      locals.incl(name)

  # Subtract locals, pseudo-variables, and known globals
  var captures: seq[string] = @[]
  for name in allRefs:
    if name in locals:
      continue
    if name in pseudoVars:
      continue
    if name in knownGlobals:
      continue
    captures.add(name)

  return captures

proc registerBlock*(reg: BlockRegistry, blockNode: BlockNode, knownGlobals: seq[string] = @[]): BlockProcInfo =
  ## Register a block for compilation and return its metadata
  let nimName = reg.generateBlockName()
  let envName = reg.generateEnvStructName()

  # Analyze captures
  let captures = analyzeCaptures(blockNode, knownGlobals)

  # Check for non-local returns (^)
  var hasNonLocalReturn = false
  for stmt in blockNode.body:
    if stmt of ReturnNode:
      hasNonLocalReturn = true
      break

  result = BlockProcInfo(
    nimName: nimName,
    blockNode: blockNode,
    captures: captures,
    captureTypes: captures.mapIt("NodeValue"),  # All captures are NodeValue
    hasNonLocalReturn: hasNonLocalReturn,
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
  if info.captures.len == 0:
    return ""  # No environment needed

  var output = fmt("type {info.envStructName}* = object")
  for i, capture in info.captures:
    let typ = info.captureTypes[i]
    output.add(fmt("\n  {capture}: {typ}"))
  return output

proc generateBlockProcSignature*(info: BlockProcInfo): string =
  ## Generate the procedure signature for a block
  var params: seq[string] = @[]

  # Add environment pointer if there are captures
  if info.captures.len > 0:
    params.add(fmt("env: ptr {info.envStructName}"))

  # Add block parameters using actual names from the BlockNode
  for i in 0..<info.paramCount:
    let paramName = if i < info.blockNode.parameters.len:
                      info.blockNode.parameters[i]
                    else:
                      fmt("param{i}")
    params.add(fmt("{paramName}: NodeValue"))

  let paramsStr = params.join(", ")
  result = fmt("proc {info.nimName}*({paramsStr}): NodeValue {{.cdecl.}}")

proc generateBlockProcBody*(info: BlockProcInfo): string =
  ## Generate the procedure body for a block
  ## This is a placeholder - full implementation in expression.nim
  ##
  ## The full implementation should:
  ## - Extract captures from environment
  ## - Generate body statements using genStatement
  ## - Handle implicit returns for last expression
  var output = ""

  # If we have captures, extract them from environment
  if info.captures.len > 0:
    for capture in info.captures:
      output.add(fmt("  let {capture} = env.{capture}\n"))

  # For now, use runtime dispatch for block body
  # Full compilation would generate Nim code here
  output.add("  # Block body - uses runtime dispatch for now\n")
  output.add("  # TODO: Compile block body to Nim code\n")
  output.add("  return nilValue()\n")

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
  "timesRepeat:", "to:by:do:"
]

proc collectBlocks*(registry: BlockRegistry, node: Node, knownGlobals: seq[string] = @[]) =
  ## Recursively collect all blocks from an AST node
  ## This populates the block registry before code generation
  ## Blocks that will be inlined by control flow are NOT registered
  if node == nil:
    return

  case node.kind
  of nkBlock:
    # Standalone blocks (not part of control flow) get registered
    discard registerBlock(registry, node.BlockNode, knownGlobals)
    # Recursively collect blocks in the body
    for stmt in node.BlockNode.body:
      collectBlocks(registry, stmt, knownGlobals)

  of nkMessage:
    let msg = node.MessageNode
    let isInlineControl = msg.selector in inlineControlSelectors

    if isInlineControl:
      # For inline control flow, skip registration of literal block arguments
      # and the receiver block (for whileTrue:/whileFalse:)
      # But still recurse into the block bodies to find nested non-inline blocks
      if msg.receiver != nil:
        if msg.receiver.kind == nkBlock:
          # Receiver block will be inlined (e.g., condition in whileTrue:)
          for stmt in msg.receiver.BlockNode.body:
            collectBlocks(registry, stmt, knownGlobals)
        else:
          collectBlocks(registry, msg.receiver, knownGlobals)
      for arg in msg.arguments:
        if arg.kind == nkBlock:
          # Argument block will be inlined (e.g., body in ifTrue:)
          for stmt in arg.BlockNode.body:
            collectBlocks(registry, stmt, knownGlobals)
        else:
          collectBlocks(registry, arg, knownGlobals)
    else:
      # Not inline control flow - process normally
      if msg.receiver != nil:
        collectBlocks(registry, msg.receiver, knownGlobals)
      for arg in msg.arguments:
        collectBlocks(registry, arg, knownGlobals)

  of nkAssign:
    let assign = node.AssignNode
    collectBlocks(registry, assign.expression, knownGlobals)

  of nkReturn:
    let ret = node.ReturnNode
    if ret.expression != nil:
      collectBlocks(registry, ret.expression, knownGlobals)

  of nkArray:
    let arr = node.ArrayNode
    for elem in arr.elements:
      collectBlocks(registry, elem, knownGlobals)

  of nkTable:
    let tbl = node.TableNode
    for (key, val) in tbl.entries:
      collectBlocks(registry, key, knownGlobals)
      collectBlocks(registry, val, knownGlobals)

  of nkIf:
    let ifNode = node.IfNode
    if ifNode.condition != nil:
      collectBlocks(registry, ifNode.condition, knownGlobals)
    if ifNode.thenBranch != nil:
      collectBlocks(registry, ifNode.thenBranch, knownGlobals)
    if ifNode.elseBranch != nil:
      collectBlocks(registry, ifNode.elseBranch, knownGlobals)

  of nkWhile:
    let whileNode = node.WhileNode
    if whileNode.condition != nil:
      collectBlocks(registry, whileNode.condition, knownGlobals)
    if whileNode.body != nil:
      collectBlocks(registry, whileNode.body, knownGlobals)

  else:
    # Other node types don't contain blocks
    discard

proc genBlockRuntimeHelpers*(): string =
  ## Generate runtime helper functions for block support
  result = """
# Block Runtime Support
# =====================

# Note: Block procedure types (BlockProc0-3, BlockEnvProc0-3) are defined at module level
# NonLocalReturnException* = object of CatchableError
#   value*: NodeValue
#   targetId*: int

# Wrapper to hold environment pointer alongside the block
type
  BlockEnvHolder* = object
    env*: pointer

var blockEnvs*: seq[BlockEnvHolder] = @[]

proc createBlock*(procPtr: pointer, paramCount: int, envPtr: pointer = nil): NodeValue =
  ## Create a block value wrapping a compiled procedure pointer
  var blk = BlockNode()
  blk.nativeImpl = procPtr
  blk.parameters = newSeq[string](paramCount)
  # Store env pointer in capturedEnv as a hack using a known key
  if envPtr != nil:
    blk.capturedEnv = initTable[string, MutableCell]()
    blk.capturedEnv["__env_ptr__"] = MutableCell(value: NodeValue(kind: vkInt, intVal: cast[int](envPtr)))
    blk.capturedEnvInitialized = true
  return NodeValue(kind: vkBlock, blockVal: blk)

proc getBlockEnvPtr*(blk: BlockNode): pointer =
  ## Retrieve the environment pointer from a block
  if blk.capturedEnvInitialized and "__env_ptr__" in blk.capturedEnv:
    return cast[pointer](blk.capturedEnv["__env_ptr__"].value.intVal)
  return nil

"""
