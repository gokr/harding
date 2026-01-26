import std/[tables, strutils, times]
import ../core/types
import ../interpreter/objects
import ../parser/[lexer, parser]

# ============================================================================
# Activation Records (Call Stack Frames)
# Spaghetti stack for non-local returns
# ============================================================================

proc newActivation*(blk: BlockNode,
                   receiver: ProtoObject,
                   sender: Activation): Activation =
  ## Create a new activation record
  result = Activation(
    sender: sender,
    receiver: receiver,
    currentMethod: blk,
    pc: 0,
    locals: initTable[string, NodeValue](),
    returnValue: nilValue(),
    hasReturned: false
  )

  # Initialize 'self' if this is a method (not a block)
  if blk.isMethod:
    result.locals["self"] = receiver.toValue()

  # Initialize parameters (bound by caller)
  # parameters will be bound when method is invoked

# Create activation from code string (for testing)
proc parseAndActivate*(source: string, receiver: ProtoObject = nil): Activation =
  ## Parse source code and create an activation for it

  let tokens = lex(source)
  var parser = initParser(tokens)
  let parsed = parseBlock(parser)

  if parsed == nil or parser.hasError:
    raise newException(ValueError,
      "Failed to parse: " & parser.errorMsg)

  let recv = if receiver != nil: receiver else: initRootObject()
  return newActivation(parsed, recv, nil)

# Display activation for debugging
proc printActivation*(activation: Activation, indent: int = 0): string =
  ## Pretty print activation record
  let spaces = repeat(' ', indent * 2)
  var result = spaces & "Activation\n"
  result.add(spaces & "  method: " & activation.currentMethod.parameters.join(", ") & "\n")
  result.add(spaces & "  locals:\n")
  for key, val in activation.locals:
    result.add(spaces & "    " & key & " = " & val.toString() & "\n")
  if activation.sender != nil:
    result.add(spaces & "  sender: <activation>\n")
  return result

# Note: Context switching and interpreter integration procs have been moved to evaluator.nim
