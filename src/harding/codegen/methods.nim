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
  case op
  of "+": nimOp = "+"
  of "-": nimOp = "-"
  of "*": nimOp = "*"
  of "/", "//":
    nimOp = "/"
    useDiv = true
  of "\\": nimOp = "mod"
  of "%": nimOp = "mod"
  else: nimOp = op

  var output = "\n  # Fast path: both operands are integers\n"
  output.add("  if a.kind == vkInt and b.kind == vkInt:\n")
  if useDiv:
    output.add("    return NodeValue(kind: vkInt, intVal: a.intVal div b.intVal)\n")
  else:
    output.add("    return NodeValue(kind: vkInt, intVal: a.intVal " & nimOp & " b.intVal)\n")
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
  of "=": nimOp = "=="
  of "~=": nimOp = "!="
  else: nimOp = "!="

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

proc genMethodBodyFromAST*(cls: ClassInfo, meth: BlockNode, selector: string): string =
  ## Generate method body by compiling AST nodes to Nim code
  ## This is the main method body compilation that translates Harding AST to Nim

  # Create generation context with class info and parameters
  var ctx = newGenContext(cls)
  for param in meth.parameters:
    ctx.parameters.add(param)

  var output = "\n"

  # Generate temporaries
  if meth.temporaries.len > 0:
    output.add("  # Temporaries\n")
    for temp in meth.temporaries:
      output.add("  var " & temp & " = NodeValue(kind: vkNil)\n")
      ctx.locals.add(temp)
    output.add("\n")

  # Generate body statements
  if meth.body.len == 0:
    # Empty body - return self
    output.add("  return self.toValue()\n")
    return output

  # Process each statement
  for i, stmt in meth.body:
    let isLast = (i == meth.body.len - 1)

    case stmt.kind
    of nkReturn:
      let ret = stmt.ReturnNode
      if ret.expression != nil:
        let exprCode = genExpression(ctx, ret.expression)
        output.add("  return " & exprCode & "\n")
      else:
        output.add("  return self.toValue()\n")

    of nkAssign:
      let assign = stmt.AssignNode
      let varName = assign.variable
      let exprCode = genExpression(ctx, assign.expression)

      # Check if variable is a slot
      if ctx.isSlot(varName):
        let idx = ctx.getSlotIndex(varName)
        output.add("  self.slots[" & $idx & "] = " & exprCode & "\n")
        if isLast:
          output.add("  return " & exprCode & "\n")
      elif ctx.isLocal(varName):
        # Local variable reassignment
        output.add("  " & varName & " = " & exprCode & "\n")
        if isLast:
          output.add("  return " & exprCode & "\n")
      else:
        # New local variable
        output.add("  var " & varName & " = " & exprCode & "\n")
        ctx.locals.add(varName)
        if isLast:
          output.add("  return " & varName & "\n")

    else:
      # Expression statement
      let exprCode = genExpression(ctx, stmt)
      if isLast:
        # Last statement - return its value
        output.add("  return " & exprCode & "\n")
      else:
        # Not last - discard result
        output.add("  discard " & exprCode & "\n")

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

proc genBinaryOpMethod*(selector: string): string =
  ## Generate a binary operator method (top-level, not class-scoped)
  let nimName = mangleSelector(selector)

  var output = "\nproc " & nimName & "*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =\n"
  output.add("  ## Binary operator: " & selector & "\n")
  output.add("  ## Provides fast-path type specialization with dynamic fallback\n")
  output.add("  ##\n")
  output.add(genBinaryOpFastPath(selector))
  output.add("\n  # Slow path: dynamic dispatch\n")
  output.add("  return sendMessage(currentRuntime[], a, \"" & selector & "\", @[b])\n\n")
  return output

proc genComparisonMethod*(selector: string): string =
  ## Generate a comparison operator method
  let nimName = mangleSelector(selector)

  var output = "\nproc " & nimName & "*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =\n"
  output.add("  ## Comparison operator: " & selector & "\n")
  output.add("  ## Provides fast-path type specialization with dynamic fallback\n")
  output.add("  ##\n")
  output.add(genComparisonFastPath(selector))
  output.add("\n  # Slow path: dynamic dispatch\n")
  output.add("  return sendMessage(currentRuntime[], a, \"" & selector & "\", @[b])\n\n")
  return output

proc genRuntimeHelperMethods*(): string =
  ## Generate runtime helper methods
  result = """
# Runtime helpers for primitives

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
