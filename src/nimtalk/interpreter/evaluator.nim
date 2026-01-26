import std/[tables, strutils, sequtils, times, math, strformat, logging]
import ../core/types
import ../parser/lexer
import ../parser/parser
import ../interpreter/objects
import ../interpreter/activation

# Forward declare wrapIntAsObject that's used for proxy objects
proc wrapIntAsObject*(value: int): NodeValue
proc wrapBoolAsObject*(value: bool): NodeValue

# Implementation of wrapIntAsObject for proxy integers
proc wrapIntAsObject*(value: int): NodeValue =
  ## Wrap an integer as a Nim proxy object that can receive messages
  let obj = ProtoObject()
  obj.properties = initTable[string, NodeValue]()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Integer", "Number"]
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](alloc(sizeof(int)))
  cast[ptr int](obj.nimValue)[] = value
  obj.nimType = "int"
  return NodeValue(kind: vkObject, objVal: obj)

# Implementation of wrapBoolAsObject for proxy booleans
proc wrapBoolAsObject*(value: bool): NodeValue =
  ## Wrap a boolean as a Nim proxy object that can receive messages
  let obj = ProtoObject()
  obj.properties = initTable[string, NodeValue]()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Boolean"]
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](alloc(sizeof(bool)))
  cast[ptr bool](obj.nimValue)[] = value
  obj.nimType = "bool"
  return NodeValue(kind: vkObject, objVal: obj)

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
proc evalCascade(interp: var Interpreter, cascadeNode: CascadeNode): NodeValue

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
  debug("Looking up variable: ", name)
  var activation = interp.currentActivation
  while activation != nil:
    if name in activation.locals:
      debug("Found variable in activation: ", name)
      return activation.locals[name]
    activation = activation.sender

  # Check globals
  if name in interp.globals:
    debug("Found variable in globals: ", name)
    let val = interp.globals[name]
    return val

  # Check if it's a property on self
  if interp.currentReceiver != nil:
    let prop = getProperty(interp.currentReceiver, name)
    if prop.kind != vkNil:
      debug("Found property on self: ", name)
      return prop

  debug("Variable not found: ", name)
  return nilValue()

# Variable assignment
proc setVariable(interp: var Interpreter, name: string, value: NodeValue) =
  ## Set variable in current activation or create global
  debug("Setting variable: ", name, " = ", value.toString())
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
    if selector in current.methods:
      let currentMethod = current.methods[selector]
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

  debug("Executing method with ", arguments.len, " arguments")

  # Check for native implementation first
  if currentMethod.nativeImpl != nil:
    # Evaluate arguments to get NodeValues
    var argValues = newSeq[NodeValue]()
    for argNode in arguments:
      argValues.add(interp.eval(argNode))

    # Check if this is an interpreter-aware native method (has interp parameter)
    if currentMethod.hasInterpreterParam:
      type NativeProcWithInterp = proc(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue {.nimcall.}
      let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
      return nativeProc(interp, receiver, argValues)
    else:
      # Standard native method without interpreter
      type NativeProc = proc(self: ProtoObject, args: seq[NodeValue]): NodeValue {.nimcall.}
      let nativeProc = cast[NativeProc](currentMethod.nativeImpl)
      return nativeProc(receiver, argValues)

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
  debug("Pushing activation, stack depth: ", interp.activationStack.len + 1)
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
    debug("Popping activation, stack depth: ", interp.activationStack.len)
    if interp.activationStack.len > 0:
      interp.currentActivation = interp.activationStack[^1]
    else:
      interp.currentActivation = nil
    interp.currentReceiver = receiver

  # Return result (or activation.returnValue if non-local return)
  if activation.hasReturned:
    debug("Returning from method (non-local)")
    return activation.returnValue
  else:
    debug("Returning from method: ", result.toString())
    return result

# Evaluation functions
proc eval*(interp: var Interpreter, node: Node): NodeValue =
  ## Evaluate an AST node
  if node == nil:
    return nilValue()

  interp.checkStackDepth()

  debug("Evaluating node: ", node.kind)

  case node.kind
  of nkLiteral:
    # Literal value - check if it's a symbol that should be looked up as a variable
    let val = node.LiteralNode.value
    if val.kind == vkSymbol:
      # Look up symbol as variable
      let varVal = lookupVariable(interp, val.symVal)
      if varVal.kind != vkNil:
        return varVal
    return val

  of nkMessage:
    # Message send
    debug("Message send: ", node.MessageNode.selector)
    return interp.evalMessage(node.MessageNode)

  of nkBlock:
    # Block literal - return as value
    return NodeValue(kind: vkBlock, blockVal: node.BlockNode)

  of nkAssign:
    # Variable assignment
    let assign = node.AssignNode
    debug("Variable assignment: ", assign.variable)
    let value = interp.eval(assign.expression)
    setVariable(interp, assign.variable, value)
    return value

  of nkReturn:
    # Non-local return
    debug("Non-local return")
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

  of nkPrimitive:
    # Primitive declaration - ignore Nim code, evaluate fallback Smalltalk
    let prim = node.PrimitiveNode
    var result = nilValue()
    # Evaluate fallback statements sequentially
    for stmt in prim.fallback:
      result = interp.eval(stmt)
    return result

  of nkCascade:
    # Cascade message - send multiple messages to same receiver
    return interp.evalCascade(node.CascadeNode)

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

  debug("Message receiver: ", receiverVal.toString())

  # Wrap non-object receivers (like integers and booleans) in Nim proxy objects
  let wrappedReceiver = case receiverVal.kind
                        of vkInt:
                          wrapIntAsObject(receiverVal.intVal)
                        of vkBool:
                          wrapBoolAsObject(receiverVal.boolVal)
                        else:
                          receiverVal

  if wrappedReceiver.kind != vkObject:
    raise newException(EvalError, "Message send to non-object: " & receiverVal.toString())

  let receiver = wrappedReceiver.toObject()

  # Evaluate arguments
  var arguments = newSeq[NodeValue]()
  for argNode in msgNode.arguments:
    arguments.add(interp.eval(argNode))

  debug("Looking up method: ", msgNode.selector)

  # Look up currentMethod
  let lookup = lookupMethod(interp, receiver, msgNode.selector)

  if lookup.found:
    # Found currentMethod - execute it
    let currentMethodNode = lookup.currentMethod
    debug("Found method, executing")

    # Convert arguments back to AST nodes if needed
    var argNodes = newSeq[Node]()
    for argVal in arguments:
      argNodes.add(LiteralNode(value: argVal))

    return interp.executeMethod(currentMethodNode, receiver, argNodes)
  else:
    # Method not found - send doesNotUnderstand:
    debug("Method not found, sending doesNotUnderstand:")
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

# Evaluate a cascade of messages
proc evalCascade(interp: var Interpreter, cascadeNode: CascadeNode): NodeValue =
  ## Evaluate cascade messages - all sent to same receiver
  ## Return the result of the last message

  # Evaluate receiver once
  let receiverVal = interp.eval(cascadeNode.receiver)
  var result = receiverVal

  # Send each message to the receiver
  for msgNode in cascadeNode.messages:
    # Temporarily set receiver for this message
    let savedReceiver = interp.currentReceiver

    # Wrap non-object receivers if needed
    let wrappedReceiver = if receiverVal.kind == vkInt:
                            wrapIntAsObject(receiverVal.intVal)
                          else:
                            receiverVal

    if wrappedReceiver.kind != vkObject:
      raise newException(EvalError, "Cascade to non-object: " & receiverVal.toString())

    interp.currentReceiver = wrappedReceiver.toObject()

    # Evaluate message - messages in cascade have receiver set to nil
    # so they use currentReceiver
    let msgWithNilReceiver = MessageNode(
      receiver: nil,
      selector: msgNode.selector,
      arguments: msgNode.arguments,
      isCascade: false
    )
    result = interp.evalMessage(msgWithNilReceiver)

    # Restore previous receiver
    interp.currentReceiver = savedReceiver

  # Return result of last message
  return result

# Special form for sending messages directly without AST
proc sendMessage*(interp: var Interpreter, receiver: ProtoObject,
                 selector: string, args: varargs[NodeValue]): NodeValue =
  ## Direct message send for internal use
  var argNodes = newSeq[Node]()
  for argVal in args:
    let node: Node = LiteralNode(value: argVal)
    argNodes.add(node)

  # Look up method in receiver
  var current = receiver
  var foundMethod: BlockNode = nil
  while current != nil:
    if selector in current.methods:
      foundMethod = current.methods[selector]
      break
    if current.parents.len > 0:
      current = current.parents[0]
    else:
      break

  if foundMethod != nil:
    return interp.executeMethod(foundMethod, receiver, argNodes)
  else:
    raise newException(EvalError,
      "Message not understood: " & selector)

# Do-it evaluation (for REPL and interactive use)
proc doit*(interp: var Interpreter, source: string, dumpAst = false): (NodeValue, string) =
  ## Parse and evaluate source code, returning result and output
  # Parse
  let (node, parser) = parseExpression(source)

  if parser.hasError:
    return (nilValue(), "Parse error: " & parser.errorMsg)

  if node == nil:
    return (nilValue(), "No expression to evaluate")

  # Dump AST if requested
  if dumpAst:
    echo "AST:"
    echo printAST(node)

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

# Block evaluation helper
proc evalBlock(interp: var Interpreter, receiver: ProtoObject, blockNode: BlockNode): NodeValue =
  ## Evaluate a block in the context of the given receiver
  ## Creates a proper activation to allow access to outer scope

  # Create activation for the block
  let activation = newActivation(blockNode, receiver, interp.currentActivation)

  # Push the activation onto the stack
  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  # Execute each statement in the block body
  var result = nilValue()
  try:
    for stmt in blockNode.body:
      result = interp.eval(stmt)
      if activation.hasReturned:
        result = activation.returnValue
        break
  finally:
    # Pop the activation
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return result

# Conditional method implementations (need to be defined before initGlobals)
proc ifTrueImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Execute block if receiver is true: true ifTrue: [code]
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Check if this is a true boolean
  if self.isNimProxy and self.nimType == "bool":
    let boolVal = cast[ptr bool](self.nimValue)[]
    if boolVal:
      # Execute the block with proper context
      let blockNode = args[0].blockVal
      return evalBlock(interp, interp.currentReceiver, blockNode)
  return nilValue()

proc ifFalseImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Execute block if receiver is false: false ifFalse: [code]
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Check if this is a boolean
  if self.isNimProxy and self.nimType == "bool":
    let boolVal = cast[ptr bool](self.nimValue)[]
    if not boolVal:
      # Execute the block with proper context
      let blockNode = args[0].blockVal
      return evalBlock(interp, interp.currentReceiver, blockNode)
  return nilValue()

# Built-in globals
proc initGlobals*(interp: var Interpreter) =
  ## Initialize built-in global variables

  # Add some useful constants
  interp.globals["Object"] = interp.rootObject.toValue()
  interp.globals["root"] = interp.rootObject.toValue()

  # Create and register Stdout object
  let stdoutObj = ProtoObject()
  stdoutObj.properties = initTable[string, NodeValue]()
  stdoutObj.methods = initTable[string, BlockNode]()
  stdoutObj.parents = @[interp.rootObject.ProtoObject]
  stdoutObj.tags = @["Stdio", "Stdout"]
  stdoutObj.isNimProxy = false
  stdoutObj.nimValue = nil
  stdoutObj.nimType = ""
  stdoutObj.hasSlots = false
  stdoutObj.slotNames = initTable[string, int]()

  let writeMethod = createCoreMethod("write:")
  writeMethod.nativeImpl = cast[pointer](writeImpl)
  addMethod(stdoutObj, "write:", writeMethod)

  let writelineMethod = createCoreMethod("writeline:")
  writelineMethod.nativeImpl = cast[pointer](writelineImpl)
  addMethod(stdoutObj, "writeline:", writelineMethod)

  interp.globals["Stdout"] = stdoutObj.toValue()
  interp.globals["stdout"] = stdoutObj.toValue()

  # Create true and false as objects with ifTrue: and ifFalse: methods
  let trueObj = ProtoObject()
  trueObj.properties = initTable[string, NodeValue]()
  trueObj.methods = initTable[string, BlockNode]()
  trueObj.parents = @[interp.rootObject.ProtoObject]
  trueObj.tags = @["Boolean", "True"]
  trueObj.isNimProxy = true
  trueObj.nimValue = cast[pointer](alloc(sizeof(bool)))
  cast[ptr bool](trueObj.nimValue)[] = true
  trueObj.nimType = "bool"
  trueObj.hasSlots = false
  trueObj.slotNames = initTable[string, int]()

  let falseObj = ProtoObject()
  falseObj.properties = initTable[string, NodeValue]()
  falseObj.methods = initTable[string, BlockNode]()
  falseObj.parents = @[interp.rootObject.ProtoObject]
  falseObj.tags = @["Boolean", "False"]
  falseObj.isNimProxy = true
  falseObj.nimValue = cast[pointer](alloc(sizeof(bool)))
  cast[ptr bool](falseObj.nimValue)[] = false
  falseObj.nimType = "bool"
  falseObj.hasSlots = false
  falseObj.slotNames = initTable[string, int]()

  # Add ifTrue: and ifFalse: methods to both true and false
  let ifTrueMethod = createCoreMethod("ifTrue:")
  ifTrueMethod.nativeImpl = cast[pointer](ifTrueImpl)
  ifTrueMethod.hasInterpreterParam = true
  addMethod(trueObj, "ifTrue:", ifTrueMethod)
  addMethod(falseObj, "ifTrue:", ifTrueMethod)

  let ifFalseMethod = createCoreMethod("ifFalse:")
  ifFalseMethod.nativeImpl = cast[pointer](ifFalseImpl)
  ifFalseMethod.hasInterpreterParam = true
  addMethod(trueObj, "ifFalse:", ifFalseMethod)
  addMethod(falseObj, "ifFalse:", ifFalseMethod)

  interp.globals["true"] = trueObj.toValue()
  interp.globals["false"] = falseObj.toValue()
  interp.globals["nil"] = nilValue()

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
