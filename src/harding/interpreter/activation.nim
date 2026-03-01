import std/[tables, strutils]
import ../core/types
import ../parser/[lexer, parser]
import ../interpreter/activation_pool

# ============================================================================
# Activation Records (Call Stack Frames)
# Spaghetti stack for non-local returns
# ============================================================================

proc newActivation*(blk: BlockNode,
                   receiver: Instance,
                   sender: Activation,
                   definingClass: Class = nil,
                   isClassMethod: bool = false): Activation =
  ## Create a new activation record using the pool for efficiency.
  ## isClassMethod: true if this activation is for a class method
  result = acquireActivation()
  result.sender = sender
  result.receiver = receiver
  result.currentMethod = blk
  result.definingObject = definingClass
  result.pc = 0
  # Tables are already cleared by releaseActivation/clearActivation; skip double-clear
  result.returnValue = nilValue()
  result.hasReturned = false
  result.isClassMethod = isClassMethod
  # wasCaptured already false from pool

  # Initialize indexed locals if the block has been resolved
  let selfVal = if isClassMethod and receiver != nil and receiver.class != nil:
                  receiver.class.toValue()
                else:
                  receiver.toValue()

  if blk != nil and blk.localCount > 0:
    # Use indexed locals for fast access
    result.indexedLocals.setLen(blk.localCount)
    result.indexedLocals[0] = selfVal  # self at index 0
    # Params and temps initialized to nil; caller will bind params
    for i in 1..<blk.localCount:
      result.indexedLocals[i] = nilValue()
  else:
    result.indexedLocals.setLen(0)

  # Also keep self in locals table for backward compat
  result.locals["self"] = selfVal

  # Initialize 'super' in locals for super sends (as Class)
  if definingClass != nil and definingClass.superclasses.len > 0:
    result.locals["super"] = definingClass.superclasses[0].toValue()
  elif receiver != nil and receiver.class != nil and receiver.class.superclasses.len > 0:
    # Super starts from receiver's class's first superclass if no defining object
    result.locals["super"] = receiver.class.superclasses[0].toValue()

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

# Note: Context switching and interpreter integration procs are in vm.nim
