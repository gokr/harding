import std/[tables, strutils, sequtils, times, math, strformat]
import ../core/types
import ../parser/lexer
import ../parser/parser
import ../interpreter/objects
import ../interpreter/activation

# ============================================================================
# Evaluation engine for Nimtalk
# Interprets AST nodes and executes currentMethods
# ============================================================================

type
  Interpreter* = ref object
    globals*: Table[string, NodeValue]
    activationStack*: seq[Activation]
    currentActivation*: Activation
    currentReceiver*: ProtoObject
    rootObject*: RootObject
    maxStackDepth*: int
    traceExecution*: bool
    lastResult*: NodeValue

type
  EvalError* = object of ValueError
    node*: Node

# Forward declarations
proc eval*(interp: var Interpreter, node: Node): NodeValue
proc evalMessage(interp: var Interpreter, msgNode: MessageNode): NodeValue

# Initialize interpreter
proc newInterpreter*(trace: bool = false): Interpreter =
  ## Create a new interpreter instance
  result = Interpreter(
    globals: initTable[string, NodeValue](),
    activationStack: @[],
    currentActivation: nil,
    currentReceiver: nil,
    maxStackDepth: 1000,
    traceExecution: trace,
    lastResult: nilValue()
  )

  # Initialize root object
  result.rootObject = initRootObject()
  result.currentReceiver = result.rootObject

# Check stack depth to prevent infinite recursion
proc checkStackDepth(interp: var Interpreter) =
  if interp.activationStack.len >= interp.maxStackDepth:
    raise newException(EvalError, "Stack overflow: max depth " & $interp.maxStackDepth)

# Helper to get method name from receiver
proc getMethodName(receiver: ProtoObject, blk: BlockNode): string =
  ## Get a display name for a method
  # Find method name by looking up in receiver
  for selector, meth in receiver.methods:
    if meth == blk:
      return selector
  return "<method>"

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
proc findActivatingMethod*(start: Activation, blk: BlockNode): Activation =
  ## Find the activation for the given method in the call stack
  var current = start
  while current != nil:
    if current.currentMethod == blk:
      return current
    current = current.sender
  return nil

proc performNonLocalReturn*(interp: var Interpreter, value: NodeValue,
                           targetMethod: BlockNode) =
  ## Perform non-local return to target method
  var current = interp.currentActivation
  while current != nil:
    if current.currentMethod == targetMethod:
      # Found target - set return value
      current.returnValue = value
      current.hasReturned = true
      break
    current = current.sender

# Display full call stack
proc printCallStack*(interp: Interpreter): string =
  ## Print the current call stack
  if interp.activationStack.len == 0:
    return "  (empty)"

  result = ""
  var level = interp.activationStack.len - 1
  for activation in interp.activationStack:
    let currentMethod = activation.currentMethod
    let receiver = activation.receiver
    let params = if currentMethod.parameters.len > 0:
                  "(" & currentMethod.parameters.join(", ") & ")"
                else:
                  ""
    result.add(&"  [{level}] {getMethodName(receiver, currentMethod)}{params}\n")
    dec level

# Variable lookup
proc lookupVariable(interp: Interpreter, name: string): NodeValue =
  ## Look up variable in activation chain and globals
  var activation = interp.currentActivation
  while activation != nil:
    if name in activation.locals:
      return activation.locals[name]
    activation = activation.sender

  # Check globals
  if name in interp.globals:
    return interp.globals[name]

  # Check if it's a property on self
  if interp.currentReceiver != nil:
    let prop = getProperty(interp.currentReceiver, name)
    if prop.kind != vkNil:
      return prop

  return nilValue()

# Variable assignment
proc setVariable(interp: var Interpreter, name: string, value: NodeValue) =
  ## Set variable in current activation or create global
  if interp.currentActivation != nil:
    # If it exists in current activation, update it
    if name in interp.currentActivation.locals:
      interp.currentActivation.locals[name] = value
    # Otherwise create in current activation
    else:
      interp.currentActivation.locals[name] = value
  else:
    # Set as global
    interp.globals[name] = value

# Method lookup and dispatch
type
  MethodResult* = object
    currentMethod*: BlockNode
    receiver*: ProtoObject
    found*: bool

proc lookupMethod(interp: Interpreter, receiver: ProtoObject, selector: string): MethodResult =
  ## Look up currentMethod in receiver and prototype chain
  var current = receiver
  while current != nil:
    let currentMethod = lookupMethod(current, selector)
    if currentMethod != nil:
      return MethodResult(currentMethod: currentMethod, receiver: current, found: true)

    # Search parent chain
    if current.parents.len > 0:
      current = current.parents[0]
    else:
      break

  return MethodResult(currentMethod: nil, receiver: nil, found: false)

# Execute a currentMethod
proc executeMethod(interp: var Interpreter, currentMethod: BlockNode,
                  receiver: ProtoObject, arguments: seq[Node]): NodeValue =
  ## Execute a currentMethod with given receiver and arguments
  interp.checkStackDepth()

  # Create new activation
  let activation = newActivation(currentMethod, receiver, interp.currentActivation)

  # Bind parameters
  if currentMethod.parameters.len != arguments.len:
    raise newException(EvalError,
      "Wrong number of arguments: expected " & $currentMethod.parameters.len &
      ", got " & $arguments.len)

  for i in 0..<currentMethod.parameters.len:
    let paramName = currentMethod.parameters[i]
    let argValue = interp.eval(arguments[i])
    activation.locals[paramName] = argValue

  # Push activation
  interp.activationStack.add(activation)
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  # Execute currentMethod body
  var result = nilValue()

  try:
    for stmt in currentMethod.body:
      result = interp.eval(stmt)
      if activation.hasReturned:
        break
  finally:
    # Pop activation
    discard interp.activationStack.pop()
    if interp.activationStack.len > 0:
      interp.currentActivation = interp.activationStack[^1]
    else:
      interp.currentActivation = nil
    interp.currentReceiver = receiver

  # Return result (or activation.returnValue if non-local return)
  if activation.hasReturned:
    return activation.returnValue
  else:
    return result

# Evaluation functions
proc eval*(interp: var Interpreter, node: Node): NodeValue =
  ## Evaluate an AST node
  if node == nil:
    return nilValue()

  interp.checkStackDepth()

  case node.kind
  of nkLiteral:
    # Literal value
    return node.LiteralNode.value

  of nkMessage:
    # Message send
    return interp.evalMessage(node.MessageNode)

  of nkBlock:
    # Block literal - return as value
    return NodeValue(kind: vkBlock, blockVal: node.BlockNode)

  of nkAssign:
    # Variable assignment
    let assign = node.AssignNode
    let value = interp.eval(assign.expression)
    setVariable(interp, assign.variable, value)
    return value

  of nkReturn:
    # Non-local return
    let ret = node.ReturnNode
    var value = nilValue()
    if ret.expression != nil:
      value = interp.eval(ret.expression)
    else:
      value = interp.currentReceiver.toValue()

    # Find the target activation for non-local return
    var activation = interp.currentActivation
    while activation != nil and not activation.currentMethod.isMethod:
      activation = activation.sender

    if activation != nil:
      activation.returnValue = value
      activation.hasReturned = true

    return value

  of nkArray:
    # Array literal - evaluate each element
    let arr = node.ArrayNode
    var elements: seq[NodeValue] = @[]
    for elem in arr.elements:
      elements.add(interp.eval(elem))
    return toValue(elements)

  of nkTable:
    # Table literal - evaluate each key-value pair
    let tab = node.TableNode
    var table = initTable[string, NodeValue]()
    for entry in tab.entries:
      # Keys must evaluate to strings
      let keyVal = interp.eval(entry.key)
      if keyVal.kind != vkString:
        raise newException(EvalError, "Table key must be string, got: " & $keyVal.kind)
      let valueVal = interp.eval(entry.value)
      table[keyVal.strVal] = valueVal
    return toValue(table)

  of nkObjectLiteral:
    # Object literal - create new object with properties
    let objLit = node.ObjectLiteralNode
    # Create new object derived from root object
    let obj = newObject()  # Creates new empty object
    for prop in objLit.properties:
      let valueVal = interp.eval(prop.value)
      obj.addProperty(prop.name, valueVal)
    return toValue(obj)

  else:
    raise newException(EvalError, "Unknown node type: " & $node.kind)

# Evaluate a message send
proc evalMessage(interp: var Interpreter, msgNode: MessageNode): NodeValue =
  ## Evaluate a message send

  # Evaluate receiver
  let receiverVal = if msgNode.receiver != nil:
                      interp.eval(msgNode.receiver)
                    else:
                      interp.currentReceiver.toValue()

  if receiverVal.kind != vkObject:
    raise newException(EvalError, "Message send to non-object: " & receiverVal.toString())

  let receiver = receiverVal.toObject()

  # Evaluate arguments
  var arguments = newSeq[NodeValue]()
  for argNode in msgNode.arguments:
    arguments.add(interp.eval(argNode))

  # Look up currentMethod
  let lookup = lookupMethod(interp, receiver, msgNode.selector)

  if lookup.found:
    # Found currentMethod - execute it
    let currentMethodNode = lookup.currentMethod

    # Convert arguments back to AST nodes if needed
    var argNodes = newSeq[Node]()
    for argVal in arguments:
      argNodes.add(LiteralNode(value: argVal))

    return interp.executeMethod(currentMethodNode, lookup.receiver, argNodes)
  else:
    # Method not found - send doesNotUnderstand:
    let dnuSelector = "doesNotUnderstand:"
    let dnuArgs = @[
      NodeValue(kind: vkSymbol, symVal: msgNode.selector)
    ] & arguments

    # Look up doesNotUnderstand:
    let dnuLookup = lookupMethod(interp, receiver, dnuSelector)
    if dnuLookup.found:
      var dnuArgNodes = newSeq[Node]()
      for argVal in dnuArgs:
        let node: Node = LiteralNode(value: argVal)
        dnuArgNodes.add(node)
      return interp.executeMethod(dnuLookup.currentMethod, receiver, dnuArgNodes)
    else:
      raise newException(EvalError,
        "Message not understood: " & msgNode.selector & " on " & $receiver.tags)

# Special form for sending messages directly without AST
proc sendMessage*(interp: var Interpreter, receiver: ProtoObject,
                 selector: string, args: varargs[NodeValue]): NodeValue =
  ## Direct message send for internal use
  var argNodes = newSeq[Node]()
  for argVal in args:
    let node: Node = LiteralNode(value: argVal)
    argNodes.add(node)

  let currentMethod = lookupMethod(receiver, selector)
  if currentMethod != nil:
    return interp.executeMethod(currentMethod, receiver, argNodes)
  else:
    raise newException(EvalError,
      "Message not understood: " & selector)

# Do-it evaluation (for REPL and interactive use)
proc doit*(interp: var Interpreter, source: string): (NodeValue, string) =
  ## Parse and evaluate source code, returning result and output
  # Parse
  let (node, parser) = parseExpression(source)

  if parser.hasError:
    return (nilValue(), "Parse error: " & parser.errorMsg)

  if node == nil:
    return (nilValue(), "No expression to evaluate")

  # Evaluate
  try:
    interp.lastResult = interp.eval(node)
    return (interp.lastResult, "")
  except EvalError as e:
    return (nilValue(), "Runtime error: " & e.msg)
  except Exception as e:
    return (nilValue(), "Error: " & e.msg)

# Batch evaluation of multiple statements
proc evalStatements*(interp: var Interpreter, source: string): (seq[NodeValue], string) =
  ## Parse and evaluate multiple statements
  let tokens = lex(source)
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()

  if parser.hasError:
    return (@[], "Parse error: " & parser.errorMsg)

  var results = newSeq[NodeValue]()

  try:
    for node in nodes:
      let result = interp.eval(node)
      results.add(result)

    return (results, "")
  except EvalError as e:
    return (@[], "Runtime error: " & e.msg)
  except Exception as e:
    return (@[], "Error: " & e.msg)

# Built-in globals
proc initGlobals*(interp: var Interpreter) =
  ## Initialize built-in global variables
  interp.globals["true"] = NodeValue(kind: vkBool, boolVal: true)
  interp.globals["false"] = NodeValue(kind: vkBool, boolVal: false)
  interp.globals["nil"] = nilValue()

  # Add some useful constants
  interp.globals["Object"] = interp.rootObject.toValue()
  interp.globals["root"] = interp.rootObject.toValue()

# Simple test function (incomplete - commented out)
## proc testBasicArithmetic*(): bool =
##   ## Test basic arithmetic: 3 + 4 = 7
##   var interp = newInterpreter()
##   initGlobals(interp)
##
##   # Add a simple addition method to Object - implementation needed
##   echo "Basic arithmetic test not yet implemented"
##   return false

# Execute code and capture output
proc execWithOutput*(interp: var Interpreter, source: string): (string, string) =
  ## Execute code and capture stdout/stderr separately
  let (result, err) = interp.doit(source)
  if err.len > 0:
    return ("", err)
  else:
    return (result.toString(), "")
