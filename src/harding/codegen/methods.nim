import std/strutils
import ../core/types
import ../compiler/context
import ../compiler/symbols
import ./expression

# ============================================================================
# Method Body Code Generation
# Generates type-specialized methods with dynamic fallback
# ============================================================================

proc genMethodSignature*(cls: ClassInfo, meth: BlockNode,
                          selector: string): string =
  ## Generate method signature with properly mangled name
  let nimName = mangleSelector(selector)
  let clsPrefix = if cls != nil: mangleClass(cls.name) & "_" else: ""

  var output = "proc " & clsPrefix & nimName & "*(self: Instance"

  # Add parameters
  for param in meth.parameters:
    output.add(", " & param & ": NodeValue")

  output.add("): NodeValue {.cdecl.}\n")
  return output

proc genMethodHeader*(cls: ClassInfo, meth: BlockNode,
                      selector: string, className: string = ""): string =
  ## Generate method header with documentation
  let sig = genMethodSignature(cls, meth, selector)
  var output = sig & " =\n"
  output.add("  ## Compiled method: " & selector & "\n")
  output.add("  ## Class: " & className & "\n")
  output.add("  ##\n")
  return output

proc genSlotFastAccess*(cls: ClassInfo, slotName: string): string =
  ## Generate fast path for slot access
  let idx = cls.getSlotIndex(slotName)

  if idx < 0:
    return "  # Dynamic fallback: slot '" & slotName & "' not found in class\n" &
           "  return sendMessage(currentRuntime[], self, \"at:\", @[NodeValue(kind: vkSymbol, symVal: \"" &
           slotName & "\")])\n"

  var output = "\n  var slotValue = NodeValue(kind: vkNil)\n"
  output.add("  if self.slots.len > " & $idx & ":\n")
  output.add("    slotValue = self.slots[" & $idx & "]\n")
  output.add("  return slotValue\n")
  return output

proc genBinaryOpFastPath*(op: string): string =
  ## Generate inline binary operation for numeric types
  var nimOp = ""
  var useDiv = false
  var isMod = false
  case op
  of "+": nimOp = "+"
  of "-": nimOp = "-"
  of "*": nimOp = "*"
  of "/", "//":
    nimOp = "/"
    useDiv = true
  of "\\":
    nimOp = "mod"
    isMod = true
  of "%":
    nimOp = "mod"
    isMod = true
  else: nimOp = op

  var output = "\n  # Fast path: both operands are integers\n"
  output.add("  if a.kind == vkInt and b.kind == vkInt:\n")
  if useDiv:
    output.add("    return NodeValue(kind: vkInt, intVal: a.intVal div b.intVal)\n")
  else:
    output.add("    return NodeValue(kind: vkInt, intVal: a.intVal " & nimOp & " b.intVal)\n")

  # Modulo only works on integers in Nim, skip float paths for mod
  if not isMod:
    output.add("  # Fast path: both operands are floats\n")
    output.add("  if a.kind == vkFloat and b.kind == vkFloat:\n")
    output.add("    return NodeValue(kind: vkFloat, floatVal: a.floatVal " & nimOp & " b.floatVal)\n")
    output.add("  # Mixed int/float - promote to float\n")
    output.add("  if a.kind == vkInt and b.kind == vkFloat:\n")
    output.add("    return NodeValue(kind: vkFloat, floatVal: float(a.intVal) " & nimOp & " b.floatVal)\n")
    output.add("  if a.kind == vkFloat and b.kind == vkInt:\n")
    output.add("    return NodeValue(kind: vkFloat, floatVal: a.floatVal " & nimOp & " float(b.intVal))\n")
  return output

proc genComparisonFastPath*(op: string): string =
  ## Generate inline comparison operation
  var nimOp = ""
  case op
  of "<": nimOp = "<"
  of "<=": nimOp = "<="
  of ">": nimOp = ">"
  of ">=": nimOp = ">="
  of "=", "==": nimOp = "=="
  of "~=": nimOp = "!="
  else: nimOp = "=="

  var output = "\n  # Fast path: integer comparison\n"
  output.add("  if a.kind == vkInt and b.kind == vkInt:\n")
  output.add("    return NodeValue(kind: vkBool, boolVal: a.intVal " & nimOp & " b.intVal)\n")
  output.add("  # Fast path: float comparison\n")
  output.add("  if a.kind == vkFloat and b.kind == vkFloat:\n")
  output.add("    return NodeValue(kind: vkBool, boolVal: a.floatVal " & nimOp & " b.floatVal)\n")
  output.add("  # Fast path: string comparison\n")
  output.add("  if a.kind == vkString and b.kind == vkString:\n")
  output.add("    return NodeValue(kind: vkBool, boolVal: a.strVal " & nimOp & " b.strVal)\n")
  output.add("  # Fast path: bool comparison\n")
  output.add("  if a.kind == vkBool and b.kind == vkBool:\n")
  output.add("    return NodeValue(kind: vkBool, boolVal: a.boolVal " & nimOp & " b.boolVal)\n")
  return output

proc hasBlocksWithNonLocalReturn(node: Node): bool =
  ## Check if an AST node contains blocks with ^ (non-local return)
  if node == nil:
    return false
  case node.kind
  of nkBlock:
    let blk = node.BlockNode
    for stmt in blk.body:
      if stmt of ReturnNode:
        return true
    # Also check nested blocks
    for stmt in blk.body:
      if hasBlocksWithNonLocalReturn(stmt):
        return true
  of nkMessage:
    let msg = node.MessageNode
    if msg.receiver != nil and hasBlocksWithNonLocalReturn(msg.receiver):
      return true
    for arg in msg.arguments:
      if hasBlocksWithNonLocalReturn(arg):
        return true
  of nkAssign:
    return hasBlocksWithNonLocalReturn(node.AssignNode.expression)
  of nkReturn:
    if node.ReturnNode.expression != nil:
      return hasBlocksWithNonLocalReturn(node.ReturnNode.expression)
  else:
    discard
  return false

proc genMethodBodyFromAST*(cls: ClassInfo, meth: BlockNode, selector: string): string =
  ## Generate method body by compiling AST nodes to Nim code
  ## This is the main method body compilation that translates Harding AST to Nim

  # Create generation context with class info and parameters
  var ctx = newGenContext(cls)
  for param in meth.parameters:
    ctx.parameters.add(param)

  # Check if method contains blocks with non-local returns
  var needsNLRWrapper = false
  for stmt in meth.body:
    if hasBlocksWithNonLocalReturn(stmt):
      needsNLRWrapper = true
      break

  var output = "\n"
  let indent = if needsNLRWrapper: "    " else: "  "

  if needsNLRWrapper:
    output.add("  try:\n")

  # Generate temporaries
  if meth.temporaries.len > 0:
    output.add(indent & "# Temporaries\n")
    for temp in meth.temporaries:
      output.add(indent & "var " & temp & " = NodeValue(kind: vkNil)\n")
      ctx.locals.add(temp)
    output.add("\n")

  # Generate body statements
  if meth.body.len == 0:
    # Empty body - return self
    output.add(indent & "return self.toValue()\n")
    if needsNLRWrapper:
      output.add("  except NonLocalReturnException as nlr:\n")
      output.add("    return nlr.value\n")
    return output

  # Process each statement
  for i, stmt in meth.body:
    let isLast = (i == meth.body.len - 1)

    case stmt.kind
    of nkReturn:
      let ret = stmt.ReturnNode
      if ret.expression != nil:
        let exprCode = genExpression(ctx, ret.expression)
        output.add(indent & "return " & exprCode & "\n")
      else:
        output.add(indent & "return self.toValue()\n")

    of nkAssign:
      let assign = stmt.AssignNode
      let varName = assign.variable
      let exprCode = genExpression(ctx, assign.expression)

      # Check if variable is a slot
      if ctx.isSlot(varName):
        let idx = ctx.getSlotIndex(varName)
        output.add(indent & "self.slots[" & $idx & "] = " & exprCode & "\n")
        if isLast:
          output.add(indent & "return " & exprCode & "\n")
      elif ctx.isLocal(varName):
        # Local variable reassignment
        output.add(indent & varName & " = " & exprCode & "\n")
        if isLast:
          output.add(indent & "return " & exprCode & "\n")
      else:
        # New local variable
        output.add(indent & "var " & varName & " = " & exprCode & "\n")
        ctx.locals.add(varName)
        if isLast:
          output.add(indent & "return " & varName & "\n")

    else:
      # Expression statement
      let exprCode = genExpression(ctx, stmt)
      if isLast:
        # Last statement - return its value
        output.add(indent & "return " & exprCode & "\n")
      else:
        # Not last - discard result
        output.add(indent & "discard " & exprCode & "\n")

  if needsNLRWrapper:
    output.add("  except NonLocalReturnException as nlr:\n")
    output.add("    return nlr.value\n")

  return output

proc genMethodBody*(cls: ClassInfo, meth: BlockNode,
                     selector: string): string =
  ## Generate method body with type specialization and fallback

  # Check for known patterns that need special handling
  case selector
  of "+", "-", "*", "/":
    # Binary arithmetic operators have special handling at top level
    return "\n  # Arithmetic operator compiled from AST\n" &
           genMethodBodyFromAST(cls, meth, selector)

  of "<", "<=", ">", ">=", "=":
    # Comparison operators have special handling at top level
    return "\n  # Comparison operator compiled from AST\n" &
           genMethodBodyFromAST(cls, meth, selector)

  of "at:":
    if meth.parameters.len > 0:
      if cls != nil and meth.parameters[0].len > 0:
        # Use AST compilation for slot access methods
        return genMethodBodyFromAST(cls, meth, selector)
    return "\n  return sendMessage(currentRuntime[], self, \"at:\", @[param])\n"

  of "at:put:":
    # Use AST compilation for slot assignment methods
    return genMethodBodyFromAST(cls, meth, selector)

  else:
    # Generic method - compile from AST
    return genMethodBodyFromAST(cls, meth, selector)

proc genMethod*(cls: ClassInfo, meth: BlockNode,
                selector: string, className: string = ""): string =
  ## Generate complete method procedure
  var output = genMethodHeader(cls, meth, selector, className)
  output.add(genMethodBody(cls, meth, selector))
  output.add("\n\n")
  return output

proc escapeSelectorForNim(selector: string): string =
  ## Escape a selector string for use in generated Nim code
  ## Handles backslashes and quotes properly
  result = selector
  # Escape backslashes first (before we add any new ones)
  result = result.replace("\\", "\\\\")
  # Escape double quotes
  result = result.replace("\"", "\\\"")

proc genBinaryOpMethod*(selector: string): string =
  ## Generate a binary operator method (top-level, not class-scoped)
  let nimName = mangleSelector(selector)
  let escapedSelector = escapeSelectorForNim(selector)

  var output = "\nproc " & nimName & "*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =\n"
  output.add("  ## Binary operator: " & selector & "\n")
  output.add("  ## Provides fast-path type specialization with dynamic fallback\n")
  output.add("  ##\n")
  output.add(genBinaryOpFastPath(selector))
  output.add("\n  # Slow path: dynamic dispatch\n")
  output.add("  return sendMessage(currentRuntime[], a, \"" & escapedSelector & "\", @[b])\n\n")
  return output

proc genComparisonMethod*(selector: string): string =
  ## Generate a comparison operator method
  let nimName = mangleSelector(selector)
  let escapedSelector = escapeSelectorForNim(selector)

  var output = "\nproc " & nimName & "*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =\n"
  output.add("  ## Comparison operator: " & selector & "\n")
  output.add("  ## Provides fast-path type specialization with dynamic fallback\n")
  output.add("  ##\n")
  output.add(genComparisonFastPath(selector))
  output.add("\n  # Slow path: dynamic dispatch\n")
  output.add("  return sendMessage(currentRuntime[], a, \"" & escapedSelector & "\", @[b])\n\n")
  return output

proc genRuntimeHelperMethods*(): string =
  ## Generate runtime helper methods
  result = """
# Runtime helpers for primitives

proc toInt*(val: NodeValue): int =
  ## Convert NodeValue to integer for loop counters
  case val.kind
  of vkInt: return val.intVal
  of vkFloat: return int(val.floatVal)
  else: return 0

proc getArg*(args: seq[NodeValue], index: int, default: NodeValue = NodeValue(kind: vkNil)): NodeValue =
  ## Get argument at index with default fallback
  if index >= 0 and index < args.len:
    return args[index]
  return default

proc requireArg*(args: seq[NodeValue], index: int, kind: ValueKind): NodeValue =
  ## Get argument and require specific type
  if index < 0 or index >= args.len:
    raise newException(ValueError, "Missing argument at index " & $index)
  let arg = args[index]
  if arg.kind != kind:
    raise newException(ValueError, "Expected " & $kind & ", got " & $arg.kind)
  return arg

proc intArg*(args: seq[NodeValue], index: int): int =
  ## Get integer argument
  return requireArg(args, index, vkInt).intVal

proc floatArg*(args: seq[NodeValue], index: int): float64 =
  ## Get float argument (converts from int if needed)
  let arg = args[index]
  if arg.kind == vkInt:
    return float(arg.intVal)
  if arg.kind == vkFloat:
    return arg.floatVal
  raise newException(ValueError, "Expected numeric argument at index " & $index)

proc stringArg*(args: seq[NodeValue], index: int): string =
  ## Get string argument
  return requireArg(args, index, vkString).strVal

# I/O helper functions

proc nt_println*(value: NodeValue): NodeValue =
  ## Print value with newline
  echo value.toString()
  return value

proc nt_print*(value: NodeValue): NodeValue =
  ## Print value without newline
  stdout.write(value.toString())
  return value

proc nt_asString*(value: NodeValue): NodeValue =
  ## Convert value to string
  return NodeValue(kind: vkString, strVal: value.toString())

proc nt_comma*(a: NodeValue, b: NodeValue): NodeValue =
  ## String concatenation
  let aStr = a.toString()
  let bStr = b.toString()
  return NodeValue(kind: vkString, strVal: aStr & bStr)

# Collection access primitives

proc nt_at_k*(receiver: NodeValue, key: NodeValue): NodeValue =
  ## Collection access: receiver at: key
  ## Works for both Arrays (1-based indexing) and Tables
  if receiver.kind == vkArray and key.kind == vkInt:
    let idx = key.intVal - 1  # Convert to 0-based
    if idx >= 0 and idx < receiver.arrayVal.len:
      return receiver.arrayVal[idx]
  elif receiver.kind == vkTable:
    if receiver.tableVal.hasKey(key):
      return receiver.tableVal[key]
  return NodeValue(kind: vkNil)

proc nt_at_kput_k*(receiver: NodeValue, key: NodeValue, value: NodeValue): NodeValue =
  ## Collection assignment: receiver at: key put: value
  ## Works for both Arrays (1-based indexing) and Tables
  if receiver.kind == vkArray and key.kind == vkInt:
    let idx = key.intVal - 1  # Convert to 0-based
    if idx >= 0 and idx < receiver.arrayVal.len:
      var newArr = receiver
      newArr.arrayVal[idx] = value
      return newArr
  elif receiver.kind == vkTable:
    var newTbl = receiver
    newTbl.tableVal[key] = value
    return newTbl
  return receiver

# Array primitives

proc nt_size*(arr: NodeValue): NodeValue =
  ## Array size
  if arr.kind == vkArray:
    return NodeValue(kind: vkInt, intVal: arr.arrayVal.len)
  return NodeValue(kind: vkNil)

proc nt_last*(arr: NodeValue): NodeValue =
  ## Array last element
  if arr.kind == vkArray and arr.arrayVal.len > 0:
    return arr.arrayVal[^1]
  return NodeValue(kind: vkNil)

# Table primitives

proc nt_table_at*(tbl: NodeValue, key: NodeValue): NodeValue =
  ## Table access: table at: key
  if tbl.kind == vkTable:
    if tbl.tableVal.hasKey(key):
      return tbl.tableVal[key]
  return NodeValue(kind: vkNil)

proc nt_table_atput*(tbl: NodeValue, key: NodeValue, value: NodeValue): NodeValue =
  ## Table assignment: table at: key put: value
  if tbl.kind == vkTable:
    var newTbl = tbl
    newTbl.tableVal[key] = value
    return newTbl
  return tbl

proc nt_table_keys*(tbl: NodeValue): NodeValue =
  ## Table keys
  if tbl.kind == vkTable:
    var keys: seq[NodeValue] = @[]
    for key in tbl.tableVal.keys:
      keys.add(key)
    return NodeValue(kind: vkArray, arrayVal: keys)
  return NodeValue(kind: vkNil)

proc nt_table_size*(tbl: NodeValue): NodeValue =
  ## Table size
  if tbl.kind == vkTable:
    return NodeValue(kind: vkInt, intVal: tbl.tableVal.len)
  return NodeValue(kind: vkNil)

# Number primitives

proc nt_abs*(n: NodeValue): NodeValue =
  ## Absolute value
  if n.kind == vkInt:
    return NodeValue(kind: vkInt, intVal: abs(n.intVal))
  if n.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: abs(n.floatVal))
  return NodeValue(kind: vkNil)

proc nt_even*(n: NodeValue): NodeValue =
  ## Is even
  if n.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: n.intVal mod 2 == 0)
  return NodeValue(kind: vkNil)

proc nt_odd*(n: NodeValue): NodeValue =
  ## Is odd
  if n.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: n.intVal mod 2 != 0)
  return NodeValue(kind: vkNil)

proc nt_negated*(n: NodeValue): NodeValue =
  ## Negated value
  if n.kind == vkInt:
    return NodeValue(kind: vkInt, intVal: -n.intVal)
  if n.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: -n.floatVal)
  return NodeValue(kind: vkNil)

# Global variable support

var globals*: Table[string, NodeValue]

proc getGlobal*(name: string): NodeValue =
  ## Get global variable value
  if globals.hasKey(name):
    return globals[name]
  return NodeValue(kind: vkNil)

proc setGlobal*(name: string, value: NodeValue): NodeValue =
  ## Set global variable value
  globals[name] = value
  return value

"""
