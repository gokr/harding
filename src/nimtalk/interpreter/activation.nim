import std/[tables, strutils]
import ../core/types
import ../interpreter/objects
import ../parser/[lexer, parser]

# ============================================================================
# Activation Records (Call Stack Frames)
# Spaghetti stack for non-local returns
# ============================================================================

proc newActivation*(blk: BlockNode,
                   receiver: Instance,
                   sender: Activation,
                   definingClass: Class = nil): Activation =
  ## Create a new activation record
  result = Activation(
    sender: sender,
    receiver: receiver,
    currentMethod: blk,
    definingObject: definingClass,  # Store as Class now
    pc: 0,
    locals: initTable[string, NodeValue](),
    capturedVars: initTable[string, MutableCell](),
    returnValue: nilValue(),
    hasReturned: false
  )

  # Initialize 'self' for all activations (blocks invoked as methods need self)
  result.locals["self"] = receiver.toValue()

  # Initialize 'super' in locals for super sends (as Class)
  if definingClass != nil and definingClass.parents.len > 0:
    result.locals["super"] = definingClass.parents[0].toValue()
  elif receiver != nil and receiver.class != nil and receiver.class.parents.len > 0:
    # Super starts from receiver's class's first parent if no defining object
    result.locals["super"] = receiver.class.parents[0].toValue()

  # Initialize parameters (bound by caller)
  # parameters will be bound when method is invoked

# Create activation from code string (for testing)
proc parseAndActivate*(source: string, receiver: Instance = nil): Activation =
  ## Parse source code and create an activation for it

  let tokens = lex(source)
  var parser = initParser(tokens)
  let parsed = parseBlock(parser)

  if parsed == nil or parser.hasError:
    raise newException(ValueError,
      "Failed to parse: " & parser.errorMsg)

  # Note: For now we need to handle the transition from RuntimeObject to Instance
  # This will be completed after the full migration
  let recv = if receiver != nil: receiver else: nil
  return newActivation(parsed, recv, nil)

# Display activation for debugging
proc printActivation*(activation: Activation, indent: int = 0): string =
  ## Pretty print activation record
  let spaces = repeat(' ', indent * 2)
  var output = spaces & "Activation\n"
  output.add(spaces & "  method: " & activation.currentMethod.parameters.join(", ") & "\n")
  output.add(spaces & "  locals:\n")
  for key, val in activation.locals:
    output.add(spaces & "    " & key & " = " & val.toString() & "\n")
  if activation.sender != nil:
    output.add(spaces & "  sender: <activation>\n")
  return output

# Note: Context switching and interpreter integration procs have been moved to evaluator.nim
