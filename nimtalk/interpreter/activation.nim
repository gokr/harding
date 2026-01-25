import std/[tables, strutils, times]
import ../core/types
import ../interpreter/objects

# ============================================================================
# Activation Records (Call Stack Frames)
# Spaghetti stack for non-local returns
# ============================================================================

proc newActivation*(method: BlockNode,
                   receiver: ProtoObject,
                   sender: Activation): Activation =
  ## Create a new activation record
  result = Activation(
    sender: sender,
    receiver: receiver,
    currentMethod: method,
    pc: 0,
    locals: initTable[string, NodeValue](),
    returnValue: nilValue(),
    hasReturned: false
  )

  # Initialize 'self' if this is a method (not a block)
  if method.isMethod:
    result.locals["self"] = receiver.toValue()

  # Initialize parameters (bound by caller)
  # parameters will be bound when method is invoked

# Create activation from code string (for testing)
proc parseAndActivate*(source: string, receiver: ProtoObject = nil): Activation =
  ## Parse source code and create an activation for it
  import ../parser/[lexer, parser]

  let tokens = lex(source)
  var parser = initParser(tokens)
  let block = parser.parseBlock()

  if block == nil or parser.hasError:
    raise newException(ValueError,
      "Failed to parse: " & parser.errorMsg)

  let recv = if receiver != nil: receiver else: initRootObject()
  return newActivation(block, recv, nil)

# Display activation for debugging
proc printActivation*(activation: Activation, indent: int = 0): string =
  ## Pretty print activation record
  let spaces = repeat(' ', indent * 2)
  var result = spaces & "Activation\n"
  result.add(spaces & "  method: " & activation.method.parameters.join(", ") & "\n"
  result.add(spaces & "  locals:\n")
  for key, val in activation.locals:
    result.add(spaces & "    " & key & " = " & val.toString() & "\n")
  if activation.sender != nil:
    result.add(spaces & "  sender: <activation>\n")
  return result

# Context switching
proc pushActivation*(interp: var Interpreter, activation: Activation) =
  ## Push activation onto stack and make it current
  interp.activationStack.add(activation)
  interp.currentActivation = activation
  interp.currentReceiver = activation.receiver

proc popActivation*(interp: var Interpreter): Activation =
  ## Pop current activation and restore previous context
  if interp.activationStack.len == 0:
    raise newException(ValueError, "Cannot pop empty activation stack")

  let current = interp.activationStack.pop()
  if interp.activationStack.len > 0:
    interp.currentActivation = interp.activationStack[^1]
    interp.currentReceiver = interp.currentActivation.receiver
  else:
    interp.currentActivation = nil
    interp.currentReceiver = nil

  return current

# Non-local return support
proc findActivatingMethod*(start: Activation, method: BlockNode): Activation =
  ## Find the activation for the given method in the call stack
  var current = start
  while current != nil:
    if current.method == method:
      return current
    current = current.sender
  return nil

proc performNonLocalReturn*(interp: var Interpreter, value: NodeValue,
                           targetMethod: BlockNode) =
  ## Perform non-local return to target method
  var current = interp.currentActivation
  while current != nil:
    if current.method == targetMethod:
      # Found target - set return value
      current.returnValue = value
      current.hasReturned = true
      break
    current = current.sender

# Activation chain iteration
type
  ActivationIter* = iterator(): Activation {.closure.}

proc walkActivations*(start: Activation): ActivationIter =
  ## Create iterator over activation chain
  var current = start
  iterator iter(): Activation {.closure.} =
    while current != nil:
      yield current
      current = current.sender
  return iter

# Display full call stack
proc printCallStack*(interp: Interpreter): string =
  ## Print the current call stack
  if interp.activationStack.len == 0:
    return "  (empty)"

  result = ""
  var level = interp.activationStack.len - 1
  for activation in interp.activationStack:
    let method = activation.method
    let receiver = activation.receiver
    let params = if method.parameters.len > 0:
                  "(" & method.parameters.join(", ") & ")"
                else:
                  ""
    result.add(&"  [{level}] {getMethodName(receiver, method)}{params}\n")
    dec level

proc getMethodName*(receiver: ProtoObject, method: BlockNode): string =
  ## Get a display name for a method
  # Find method name by looking up in receiver
  for selector, meth in receiver.methods:
    if meth == method:
      return selector
  return "<method>"
