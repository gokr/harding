import std/strformat
import ../core/types
import ../compiler/symbols

# ============================================================================
# Control Flow Code Generation
# Generates efficient loops and control structures
# ============================================================================

proc genWhileTrueMethod*(): string =
  ## Generate whileTrue: control loop
  let nimName = mangleSelector("whileTrue:")

  return fmt("""
proc {nimName}*(self: NodeValue, condition: BlockNode, body: BlockNode = nil): NodeValue {{.cdecl, exportc.}} =
  ## whileTrue: control structure
  ## Repeatedly evaluate condition and body while condition is true
  ##
  while true:
    let condResult = currentRuntime[].evalBlock(condition)
    if condResult.kind != vkBool or not condResult.boolVal:
      break

    if body != nil:
      discard currentRuntime[].evalBlock(body)

  return self

""")

proc genWhileFalseMethod*(): string =
  ## Generate whileFalse: control loop
  let nimName = mangleSelector("whileFalse:")

  return fmt("""
proc {nimName}*(self: NodeValue, condition: BlockNode, body: BlockNode = nil): NodeValue {{.cdecl, exportc.}} =
  ## whileFalse: control structure
  ## Repeatedly evaluate condition and body while condition is false
  ##
  while true:
    let condResult = currentRuntime[].evalBlock(condition)
    if condResult.kind == vkBool and condResult.boolVal:
      break

    if body != nil:
      discard currentRuntime[].evalBlock(body)

  return self

""")

proc genIfTrueIfFalseMethod*(): string =
  ## Generate ifTrue:ifFalse: conditional
  let nimName = mangleSelector("ifTrue:ifFalse:")

  return fmt("""
proc {nimName}*(self: NodeValue, trueBlock: BlockNode, falseBlock: BlockNode): NodeValue {{.cdecl, exportc.}} =
  ## ifTrue:ifFalse: conditional
  ## Evaluates appropriate block based on boolean value
  ##
  if self.kind == vkBool:
    if self.boolVal:
      return currentRuntime[].evalBlock(trueBlock)
    else:
      return currentRuntime[].evalBlock(falseBlock)

  # Not a boolean - raise error
  return NodeValue(kind: vkNil)

""")

proc genRepeatMethod*(): string =
  ## Generate repeat control loop
  let nimName = mangleSelector("repeat")

  return fmt("""
proc {nimName}*(self: NodeValue, count: int, body: BlockNode): NodeValue {{.cdecl, exportc.}} =
  ## repeat: control structure
  ## Evaluates block exactly count times
  ##
  for _ in 0..<count:
    discard currentRuntime[].evalBlock(body)

  return self

""")

proc genTimesRepeatMethod*(): string =
  ## generate timesRepeat: control loop
  let nimName = mangleSelector("timesRepeat:")

  return fmt("""
proc {nimName}*(self: NodeValue, body: BlockNode): NodeValue {{.cdecl, exportc.}} =
  ## timesRepeat: control structure
  ## Evaluates block self times (if self is an integer)
  ##
  if self.kind != vkInt:
    return self

  let count = self.intVal
  for _ in 0..<count:
    discard currentRuntime[].evalBlock(body)

  return self

""")

proc genToByDoMethod*(): string =
  ## Generate to:by:do: iteration loop
  let nimName = mangleSelector("to:by:do:")

  return fmt("""
proc {nimName}*(self: NodeValue, endVal: NodeValue, stepVal: NodeValue, body: BlockNode): NodeValue {{.cdecl, exportc.}} =
  ## to:by:do: iteration loop
  ## Iterates from self to endVal by stepVal, evaluating body with current value
  ##
  if self.kind != vkInt or endVal.kind != vkInt or stepVal.kind != vkInt:
    return self

  var current = self.intVal
  let endNum = endVal.intVal
  let step = stepVal.intVal

  if step > 0:
    while current <= endNum:
      discard currentRuntime[].evalBlock(body, @[NodeValue(kind: vkInt, intVal: current)])
      current += step
  else:
    while current >= endNum:
      discard currentRuntime[].evalBlock(body, @[NodeValue(kind: vkInt, intVal: current)])
      current += step

  return self

""")

proc genGenControlMethods*(): string =
  ## Generate all control flow methods
  var output = ""

  output.add("# Control Flow Methods\n")
  output.add("######################\n\n")

  output.add(genWhileTrueMethod())
  output.add(genWhileFalseMethod())
  output.add(genIfTrueIfFalseMethod())
  output.add(genRepeatMethod())
  output.add(genTimesRepeatMethod())
  output.add(genToByDoMethod())

  return output

proc evalBlock*(blk: BlockNode, args: seq[NodeValue] = @[]): NodeValue =
  ## Placeholder for block evaluation - needs runtime support
  discard
  return NodeValue(kind: vkNil)
