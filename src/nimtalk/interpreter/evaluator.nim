import std/[tables, strutils, math, strformat, logging]
import ../core/types
import ../parser/lexer
import ../parser/parser
import ../interpreter/objects
import ../interpreter/activation

# Forward declarations for methods defined later in this file
proc wrapIntAsObject*(value: int): NodeValue =
  ## Wrap an integer as a Nim proxy object that can receive messages
  let obj = ProtoObject()
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
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Boolean"]
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](alloc(sizeof(bool)))
  cast[ptr bool](obj.nimValue)[] = value
  obj.nimType = "bool"
  return NodeValue(kind: vkObject, objVal: obj)

# Implementation of wrapStringAsObject for proxy strings
proc wrapStringAsObject*(s: string): NodeValue =
  ## Wrap a string as a Nim proxy object that can receive messages
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["String", "Text"]
  obj.isNimProxy = true
  obj.nimType = "string"
  # Store string value
  obj.properties = initTable[string, NodeValue]()
  obj.properties["__value"] = NodeValue(kind: vkString, strVal: s)
  return NodeValue(kind: vkObject, objVal: obj.ProtoObject)

# Implementation of wrapArrayAsObject for proxy arrays
# Uses DictionaryObj to store elements in properties for safety
proc wrapArrayAsObject*(arr: seq[NodeValue]): NodeValue =
  ## Wrap an array (seq) as a Nim proxy object that can receive messages
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Array", "Collection"]
  obj.isNimProxy = true
  obj.nimType = "array"
  # Store elements in properties with numeric keys
  obj.properties = initTable[string, NodeValue]()
  for i, elem in arr:
    obj.properties[$i] = elem  # 0-based index internally
  return NodeValue(kind: vkObject, objVal: obj.ProtoObject)

# Implementation of wrapTableAsObject for proxy tables
# Uses DictionaryObj to store entries in properties for safety
proc wrapTableAsObject*(tab: Table[string, NodeValue]): NodeValue =
  ## Wrap a table as a Nim proxy object that can receive messages
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Table", "Collection", "Dictionary"]
  obj.isNimProxy = true
  obj.nimType = "table"
  # Store entries in properties
  obj.properties = tab
  return NodeValue(kind: vkObject, objVal: obj.ProtoObject)

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
type
  LookupResult = tuple[found: bool, value: NodeValue]

proc lookupVariableWithStatus(interp: Interpreter, name: string): LookupResult =
  ## Look up variable in activation chain and globals
  ## Returns (found: true, value: ...) if found, (found: false, value: nil) if not found
  debug("Looking up variable: ", name)
  var activation = interp.currentActivation
  while activation != nil:
    if name in activation.locals:
      debug("Found variable in activation: ", name)
      return (true, activation.locals[name])
    activation = activation.sender

  # Check globals
  if name in interp.globals:
    debug("Found variable in globals: ", name, " = ", interp.globals[name].toString())
    let val = interp.globals[name]
    return (true, val)

  # Check if it's a property on self (only for Dictionary objects)
  if interp.currentReceiver != nil and interp.currentReceiver of DictionaryObj:
    let dict = cast[DictionaryObj](interp.currentReceiver)
    let prop = getProperty(dict, name)
    if prop.kind != vkNil:
      debug("Found property on self: ", name)
      return (true, prop)

  debug("Variable not found: ", name)
  return (false, nilValue())

# Backward-compatible wrapper
proc lookupVariable(interp: Interpreter, name: string): NodeValue =
  ## Look up variable (returns nilValue if not found)
  lookupVariableWithStatus(interp, name).value

# Variable assignment
proc setVariable(interp: var Interpreter, name: string, value: NodeValue) =
  ## Set variable in current activation or create global
  debug("Setting variable: ", name, " = ", value.toString(), " (activation: ", interp.currentActivation != nil, ")")
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
    debug("Global set: ", name, " now globals count: ", interp.globals.len)

# Method lookup and dispatch
type
  MethodResult* = object
    currentMethod*: BlockNode
    receiver*: ProtoObject
    definingObject*: ProtoObject  # where method was found (for super)
    found*: bool

proc lookupMethod(interp: Interpreter, receiver: ProtoObject, selector: string): MethodResult =
  ## Look up method in receiver and prototype chain using canonical symbol
  let sym = getSymbol(selector)
  let selectorKey = sym.symVal
  debug("Looking up method: '", selectorKey, "' in receiver with tags: ", $receiver.tags)
  var current = receiver
  var depth = 0
  while current != nil and depth < 100:
    inc depth
    if selectorKey in current.methods:
      debug("Found method ", selectorKey, " in methods table")
      let meth = current.methods[selectorKey]
      return MethodResult(currentMethod: meth, receiver: receiver, definingObject: current, found: true)

    # Check Dictionary properties for block values (only for Dictionary objects)
    if current of DictionaryObj:
      let dict = cast[DictionaryObj](current)
      if selector in dict.properties:
        debug("Found property with selector: ", selector)
        let prop = dict.properties[selector]
        if prop.kind == vkBlock:
          let blockNode = prop.blockVal
          debug("Property is a block, returning as method")
          # Mark block as method for non-local returns
          blockNode.isMethod = true
          # Return the block as a method
          return MethodResult(currentMethod: blockNode, receiver: receiver, definingObject: current, found: true)

    # Search parent chain
    if current.parents.len > 0:
      current = current.parents[0]
    else:
      break

  if depth >= 100:
    warn("Lookup depth exceeded 100 for selector: ", selector)
  debug("Method not found: ", selector)
  return MethodResult(currentMethod: nil, receiver: nil, definingObject: nil, found: false)

# Execute a currentMethod
proc executeMethod(interp: var Interpreter, currentMethod: BlockNode,
                  receiver: ProtoObject, arguments: seq[Node],
                  definingObject: ProtoObject = nil): NodeValue =
  ## Execute a currentMethod with given receiver and arguments
  ## definingObject is where the method was found (for super sends)
  interp.checkStackDepth()

  debug("Executing method with ", arguments.len, " arguments")

  # Check for native implementation first
  if currentMethod.nativeImpl != nil:
    debug("Calling native implementation for " & $receiver.tags)
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

  # Create new activation with definingObject for super sends
  debug("Executing interpreted method with ", currentMethod.parameters.len, " parameters")
  let activation = newActivation(currentMethod, receiver, interp.currentActivation, definingObject)

  # Bind parameters
  if currentMethod.parameters.len != arguments.len:
    raise newException(EvalError,
      "Wrong number of arguments: expected " & $currentMethod.parameters.len &
      ", got " & $arguments.len)

  for i in 0..<currentMethod.parameters.len:
    let paramName = currentMethod.parameters[i]
    let argValue = interp.eval(arguments[i])
    debug("Binding parameter: ", paramName, " = ", argValue.toString())
    activation.locals[paramName] = argValue

  # Push activation
  debug("Pushing activation, stack depth: ", interp.activationStack.len + 1)
  interp.activationStack.add(activation)
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  # Execute currentMethod body
  var retVal = nilValue()

  try:
    for stmt in currentMethod.body:
      retVal = interp.eval(stmt)
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

  debug("Method execution complete, hasReturned: ", activation.hasReturned)
  # Return result (or activation.returnValue if non-local return)
  if activation.hasReturned:
    debug("Returning from method (non-local)")
    return activation.returnValue
  else:
    debug("Returning from method: ", retVal.toString())
    return retVal

# Evaluation functions
proc eval*(interp: var Interpreter, node: Node): NodeValue =
  ## Evaluate an AST node
  if node == nil:
    return nilValue()

  interp.checkStackDepth()

  debug("Evaluating node: ", node.kind)

  case node.kind
  of nkLiteral:
    # Literal value - return as-is (symbols are literal values, not variable references)
    return node.LiteralNode.value

  of nkIdent:
    # Identifier - look up as variable
    let ident = cast[IdentNode](node)
    debug("Identifier lookup: ", ident.name)
    return lookupVariable(interp, ident.name)

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
    var loopCount = 0
    while activation != nil and not activation.currentMethod.isMethod:
      activation = activation.sender
      inc loopCount
      if loopCount > 100:
        warn("Possible infinite loop in return - exceeded 100 activations")
        break

    if activation != nil:
      activation.returnValue = value
      activation.hasReturned = true

    return value

  of nkArray:
    # Array literal - evaluate each element
    let arr = node.ArrayNode
    debug("Evaluating array with ", arr.elements.len, " elements")
    var elements: seq[NodeValue] = @[]
    for elem in arr.elements:
      # Special handling for symbol literals inside arrays
      # They should be treated as literal symbols, not variable lookups
      if elem of LiteralNode:
        let lit = elem.LiteralNode
        if lit.value.kind == vkSymbol:
          # Use symbol value directly, don't evaluate as variable
          debug("Symbol literal in array: ", lit.value.symVal)
          elements.add(lit.value)
          continue
      # Inside #(...), bare identifiers like 'a' in #(a b) are syntactic sugar for symbols
      # So #(name age) is equivalent to #(#name #age)
      if elem of IdentNode:
        let ident = cast[IdentNode](elem)
        debug("Identifier in array literal treated as symbol: ", ident.name)
        elements.add(getSymbol(ident.name))
        continue
      # Normal evaluation for other elements
      elements.add(interp.eval(elem))
    debug("Array result: ", elements.len, " elements")
    # Wrap array in proxy object so it can receive messages like at:
    return wrapArrayAsObject(elements)

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
    # Wrap table in proxy object so it can receive messages like at:
    return wrapTableAsObject(table)

  of nkObjectLiteral:
    # Object literal - create new object with properties
    let objLit = node.ObjectLiteralNode
    # Create new object derived from root object
    let dict = newDictionary()  # Creates new Dictionary object
    for prop in objLit.properties:
      let valueVal = interp.eval(prop.value)
      addDictionaryProperty(dict, prop.name, valueVal)
    return toValue(dict.ProtoObject)

  of nkPrimitive:
    # Primitive declaration - ignore Nim code, evaluate fallback Smalltalk
    let prim = node.PrimitiveNode
    var fallbackResult = nilValue()
    # Evaluate fallback statements sequentially
    for stmt in prim.fallback:
      fallbackResult = interp.eval(stmt)
    return fallbackResult

  of nkCascade:
    # Cascade message - send multiple messages to same receiver
    return interp.evalCascade(node.CascadeNode)


# Evaluate a message send
proc evalMessage(interp: var Interpreter, msgNode: MessageNode): NodeValue =
  ## Evaluate a message send

  # Evaluate receiver
  let receiverVal = if msgNode.receiver != nil:
                      interp.eval(msgNode.receiver)
                    else:
                      interp.currentReceiver.toValue()

  debug("Message receiver: ", receiverVal.toString())

  # Wrap non-object receivers (like integers, booleans, strings, arrays, tables) in Nim proxy objects
  let wrappedReceiver = case receiverVal.kind
                        of vkInt:
                          wrapIntAsObject(receiverVal.intVal)
                        of vkBool:
                          wrapBoolAsObject(receiverVal.boolVal)
                        of vkString:
                          wrapStringAsObject(receiverVal.strVal)
                        of vkArray:
                          wrapArrayAsObject(receiverVal.arrayVal)
                        of vkTable:
                          wrapTableAsObject(receiverVal.tableVal)
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

    return interp.executeMethod(currentMethodNode, receiver, argNodes, lookup.definingObject)
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
      return interp.executeMethod(dnuLookup.currentMethod, receiver, dnuArgNodes, dnuLookup.definingObject)
    else:
      raise newException(EvalError,
        "Message not understood: " & msgNode.selector & " on " & $receiver.tags)

# Evaluate a cascade of messages
proc evalCascade(interp: var Interpreter, cascadeNode: CascadeNode): NodeValue =
  ## Evaluate cascade messages - all sent to same receiver
  ## Return the result of the last message

  # Evaluate receiver once
  let receiverVal = interp.eval(cascadeNode.receiver)
  var cascadeResult = receiverVal

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
    cascadeResult = interp.evalMessage(msgWithNilReceiver)

    # Restore previous receiver
    interp.currentReceiver = savedReceiver

  # Return result of last message
  return cascadeResult

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
  # Use parseStatements to properly handle assignments and other statements
  let tokens = lex(source)
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()

  if parser.hasError:
    return (nilValue(), "Parse error: " & parser.errorMsg)

  if nodes.len == 0:
    return (nilValue(), "No expression to evaluate")

  # Dump AST if requested
  if dumpAst:
    echo "AST:"
    for node in nodes:
      echo printAST(node)

  # Evaluate all nodes, return last result
  try:
    var lastResult = nilValue()
    for node in nodes:
      lastResult = interp.eval(node)
    interp.lastResult = lastResult
    return (lastResult, "")
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
      let evalResult = interp.eval(node)
      results.add(evalResult)

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
  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.eval(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue
        break
  finally:
    # Pop the activation
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult

# Collection iteration method (interpreter-aware)
proc doCollectionImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Iterate over collection: collection do: [:item | ... ]
  ## Returns the collection (like Smalltalk)
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  let blockNode = args[0].blockVal

  # Handle array iteration
  if self.isNimProxy and self.nimType == "array":
    let arr = cast[ptr seq[NodeValue]](self.nimValue)[]
    for elem in arr:
      # Create activation for block with element as parameter
      let activation = newActivation(blockNode, interp.currentReceiver, interp.currentActivation)
      # Bind the block parameter to the element
      if blockNode.parameters.len > 0:
        activation.locals[blockNode.parameters[0]] = elem
      # Execute block body
      for stmt in blockNode.body:
        discard interp.eval(stmt)
        if activation.hasReturned:
          break
      if activation.hasReturned:
        break
    return self.toValue()

  # Handle table iteration (key-value pairs)
  if self.isNimProxy and self.nimType == "table":
    let tab = cast[ptr Table[string, NodeValue]](self.nimValue)[]
    for key, val in tab:
      let activation = newActivation(blockNode, interp.currentReceiver, interp.currentActivation)
      # Bind block parameters
      if blockNode.parameters.len > 0:
        activation.locals[blockNode.parameters[0]] = NodeValue(kind: vkString, strVal: key)
      if blockNode.parameters.len > 1:
        activation.locals[blockNode.parameters[1]] = val
      # Execute block body
      for stmt in blockNode.body:
        discard interp.eval(stmt)
        if activation.hasReturned:
          break
      if activation.hasReturned:
        break
    return self.toValue()

  return nilValue()

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

  # Add Dictionary to globals
  if dictionaryPrototype != nil:
    interp.globals["Dictionary"] = dictionaryPrototype.ProtoObject.toValue()

  # Create and register Stdout object
  let stdoutObj = ProtoObject()
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

  # Note: do: method is registered on array and table proxy objects dynamically
  # It would be better to have a Collection prototype, but for now we rely on
  # the atCollectionImpl method registered on rootObject for at: access

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
  let (value, err) = interp.doit(source)
  if err.len > 0:
    return ("", err)
  else:
    return (value.toString(), "")
