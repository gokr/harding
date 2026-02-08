import std/[strutils, sequtils, strformat, tables]
import ../core/types
import ../compiler/context
import ../compiler/symbols

# ============================================================================
# Expression Code Generation
# Generates Nim code from AST expressions
# ============================================================================

type
  GenContext* = ref object
    cls*: ClassInfo
    inBlock*: bool
    locals*: seq[string]          ## Local variable names (temporaries)
    parameters*: seq[string]      ## Parameter names
    globals*: seq[string]         ## Known global variable names

# Forward declaration
proc genExpression*(ctx: GenContext, node: Node): string
proc genStatement*(ctx: GenContext, node: Node): string

proc newGenContext*(cls: ClassInfo = nil): GenContext =
  ## Create new generation context
  result = GenContext(
    cls: cls,
    inBlock: false,
    locals: @[],
    parameters: @[],
    globals: @[]
  )

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

proc genLiteral*(node: LiteralNode): string =
  ## Generate code for literal node
  let value = node.value
  case value.kind
  of vkInt:
    return fmt("NodeValue(kind: vkInt, intVal: {value.intVal})")
  of vkFloat:
    return fmt("NodeValue(kind: vkFloat, floatVal: {value.floatVal})")
  of vkString:
    return fmt("NodeValue(kind: vkString, strVal: \"{value.strVal}\")")
  of vkSymbol:
    # Symbols need runtime lookup
    return fmt("NodeValue(kind: vkSymbol, symVal: \"{value.symVal}\")")
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
  var output = ""

  # Generate receiver
  var receiverCode: string
  if node.receiver != nil:
    receiverCode = genExpression(ctx, node.receiver)
  else:
    receiverCode = "self.toValue()"

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

  of "println":
    # Print with newline
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return fmt("nt_println({argCode})")
    else:
      return fmt("nt_println({receiverCode})")

  of "print":
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

  of "derive:", "derive", "new", "selector:put:", "classSelector:put:":
    # Class-related messages - need runtime dispatch
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    return fmt("sendMessage(currentRuntime[], {receiverCode}, \"{node.selector}\", @[{args}])")

  else:
    # Generic message - try to call compiled method or fall back to runtime
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    let mangledName = mangleSelector(node.selector)
    # For now, use runtime dispatch - compiled methods will be registered
    return fmt("sendMessage(currentRuntime[], {receiverCode}, \"{node.selector}\", @[{args}])")

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

  of nkBlock:
    let blk = node.BlockNode
    # Create new context for block with its parameters as locals
    var blockCtx = GenContext(
      cls: ctx.cls,
      inBlock: true,
      locals: ctx.locals,
      parameters: ctx.parameters,
      globals: ctx.globals
    )
    for param in blk.parameters:
      blockCtx.parameters.add(param)

    if blk.parameters.len > 0:
      # Block with parameters
      let params = blk.parameters.mapIt(fmt("{it}: NodeValue")).join(", ")
      var bodyStmts: seq[string] = @[]
      for i, stmt in blk.body:
        if i == blk.body.len - 1:
          # Last statement is the return value
          bodyStmts.add("result = " & genExpression(blockCtx, stmt))
        else:
          bodyStmts.add(genStatement(blockCtx, stmt))
      return fmt("(proc({params}): NodeValue =\n    {bodyStmts.join(\"\n    \")}\n  )")
    else:
      # Simple block
      var bodyStmts: seq[string] = @[]
      for i, stmt in blk.body:
        if i == blk.body.len - 1:
          bodyStmts.add("result = " & genExpression(blockCtx, stmt))
        else:
          bodyStmts.add(genStatement(blockCtx, stmt))
      return "(proc(): NodeValue =\n    " & bodyStmts.join("\n    ") & "\n  )"

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
    # Statement is a message send (e.g., "hello" println)
    let msgCode = genMessage(ctx, node.MessageNode)
    return "discard " & msgCode

  of nkPrimitiveCall:
    # Primitive call as statement
    let primCall = node.PrimitiveCallNode
    let args = primCall.arguments.mapIt(genExpression(ctx, it)).join(", ")
    return fmt"discard callPrimitive(\"{primCall.selector}\", @[{args}])"

  else:
    # For other nodes, just generate the expression
    let exprCode = genExpression(ctx, node)
    if exprCode.len > 0:
      return "discard " & exprCode
    return ""

proc genBlockBody*(ctx: GenContext, blkNode: BlockNode): string =
  ## Generate code for block body (sequence of statements)
  var output = ""

  # Create new context for block body with its parameters
  var bodyCtx = GenContext(
    cls: ctx.cls,
    inBlock: true,
    locals: ctx.locals,
    parameters: ctx.parameters,
    globals: ctx.globals
  )
  for param in blkNode.parameters:
    bodyCtx.parameters.add(param)

  for i, stmt in blkNode.body:
    if i == blkNode.body.len - 1 and stmt.kind notin {nkReturn, nkAssign}:
      # Last statement is the return value
      let exprCode = genExpression(bodyCtx, stmt)
      output.add("  result = " & exprCode & "\n")
    else:
      let stmtCode = genStatement(bodyCtx, stmt)
      if stmtCode.len > 0:
        output.add("  " & stmtCode & "\n")

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

    # Top-level variable (global in main)
    ctx.globals.add(varName)
    return fmt"var {varName} = {exprCode}"

  of nkMessage:
    # Top-level message send
    let msgCode = genMessage(ctx, node.MessageNode)
    return "discard " & msgCode

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
