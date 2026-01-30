import std/[tables, strutils, math, strformat, logging, os]
import ../core/types
import ../parser/lexer
import ../parser/parser
import ../interpreter/objects
import ../interpreter/activation

# Forward declaration for prototype caches
var arrayPrototypeCache: ProtoObject = nil
var integerPrototypeCache: ProtoObject = nil
var stringPrototypeCache: ProtoObject = nil
var truePrototypeCache: ProtoObject = nil
var falsePrototypeCache: ProtoObject = nil
var blockPrototypeCache: ProtoObject = nil

# Forward declarations for methods defined later in this file
proc wrapIntAsObject*(value: int): NodeValue =
  ## Wrap an integer as a Nim proxy object that can receive messages
  let obj = ProtoObject()
  obj.methods = initTable[string, BlockNode]()
  # Use Integer prototype as parent if available
  if integerPrototypeCache != nil:
    obj.parents = @[integerPrototypeCache]
  else:
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
  # Use True/False prototype as parent if available
  if value and truePrototypeCache != nil:
    obj.parents = @[truePrototypeCache]
  elif not value and falsePrototypeCache != nil:
    obj.parents = @[falsePrototypeCache]
  else:
    obj.parents = @[initRootObject().ProtoObject]
  obj.tags = if value: @["Boolean", "True"] else: @["Boolean", "False"]
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
  # Use String prototype as parent if available
  if stringPrototypeCache != nil:
    obj.parents = @[stringPrototypeCache]
  else:
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

  # Try to use Array prototype as parent if available
  if arrayPrototypeCache != nil:
    obj.parents = @[arrayPrototypeCache]
  else:
    obj.parents = @[initRootObject().ProtoObject]

  obj.tags = @["Array", "Collection"]
  obj.isNimProxy = true
  obj.nimType = "array"
  # Store elements in properties with numeric keys
  obj.properties = initTable[string, NodeValue]()
  obj.properties["__size"] = NodeValue(kind: vkInt, intVal: arr.len)
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

# Implementation of wrapFloatAsObject for proxy floats
proc wrapFloatAsObject*(value: float): NodeValue =
  ## Wrap a float as a Nim proxy object that can receive messages
  let obj = ProtoObject()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Float", "Number"]
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](alloc(sizeof(float)))
  cast[ptr float](obj.nimValue)[] = value
  obj.nimType = "float"
  obj.hasSlots = false
  obj.slots = @[]
  obj.slotNames = initTable[string, int]()
  return NodeValue(kind: vkObject, objVal: obj)

# Implementation of wrapBlockAsObject for blocks (needed for methods like whileTrue:)
proc wrapBlockAsObject*(blockNode: BlockNode): NodeValue =
  ## Wrap a block as a ProtoObject that can receive messages (like whileTrue:)
  ## The BlockNode is stored so it can be executed later
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  # Use Block prototype as parent if available
  if blockPrototypeCache != nil:
    obj.parents = @[blockPrototypeCache]
  else:
    obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Block", "Closure"]
  obj.isNimProxy = false
  obj.nimType = "block"
  # Store block node in properties so whileTrue:/whileFalse: can access it
  obj.properties = initTable[string, NodeValue]()
  obj.properties["__blockNode"] = NodeValue(kind: vkBlock, blockVal: blockNode)
  return NodeValue(kind: vkObject, objVal: obj.ProtoObject)

# ============================================================================
# Evaluation engine for Nimtalk
# Interprets AST nodes and executes currentMethods
# ============================================================================

type
  # Exception handler record for on:do: mechanism
  ExceptionHandler* = object
    exceptionClass*: ProtoObject    # The exception class to catch
    handlerBlock*: BlockNode        # Block to execute when caught
    activation*: Activation         # Activation where handler was installed
    stackDepth*: int                # Stack depth when handler installed

  Interpreter* = ref object
    globals*: ref Table[string, NodeValue]
    activationStack*: seq[Activation]
    currentActivation*: Activation
    currentReceiver*: ProtoObject
    rootObject*: RootObject
    maxStackDepth*: int
    traceExecution*: bool
    lastResult*: NodeValue
    exceptionHandlers*: seq[ExceptionHandler]  # Stack of active exception handlers

type
  EvalError* = object of ValueError
    node*: Node

# Forward declarations
proc eval*(interp: var Interpreter, node: Node): NodeValue
proc evalMessage(interp: var Interpreter, msgNode: MessageNode): NodeValue
proc evalCascade(interp: var Interpreter, cascadeNode: CascadeNode): NodeValue
proc evalSuperSend(interp: var Interpreter, superNode: SuperSendNode): NodeValue
proc asSelfDoImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue

# Initialize interpreter
proc newInterpreter*(trace: bool = false): Interpreter =
  ## Create a new interpreter instance
  result = Interpreter(
    globals: new(Table[string, NodeValue]),
    activationStack: @[],
    currentActivation: nil,
    currentReceiver: nil,
    maxStackDepth: 1000,
    traceExecution: trace,
    lastResult: nilValue()
  )

  # Initialize the heap-allocated globals table
  result.globals[] = initTable[string, NodeValue]()

  # Initialize root object
  result.rootObject = initRootObject()
  result.currentReceiver = result.rootObject

  # Add asSelfDo: method to root object (interpreter-aware)
  let asSelfDoMethod = createCoreMethod("asSelfDo:")
  asSelfDoMethod.nativeImpl = cast[pointer](asSelfDoImpl)
  asSelfDoMethod.hasInterpreterParam = true
  addMethod(result.rootObject.ProtoObject, "asSelfDo:", asSelfDoMethod)

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

# Forward declarations for closure-related procs
proc captureEnvironment*(interp: Interpreter, blockNode: BlockNode)
proc invokeBlock*(interp: var Interpreter, blockNode: BlockNode, args: seq[NodeValue]): NodeValue

proc lookupVariableWithStatus(interp: Interpreter, name: string): LookupResult =
  ## Look up variable in activation chain, captured environment, and globals
  ## Returns (found: true, value: ...) if found, (found: false, value: nil) if not found
  debug("Looking up variable: ", name)
  var activation = interp.currentActivation
  while activation != nil:
    # Check locals first
    if name in activation.locals:
      debug("Found variable in activation: ", name)
      return (true, activation.locals[name])

    # Check captured environment of the current method/block
    if activation.currentMethod != nil and activation.currentMethod.capturedEnv.len > 0:
      if name in activation.currentMethod.capturedEnv:
        let value = activation.currentMethod.capturedEnv[name].value
        debug("Found variable in captured environment: ", name, " = ", value.toString())
        return (true, value)

    activation = activation.sender

  # Check globals
  if name in interp.globals[]:
    debug("Found variable in globals: ", name, " = ", interp.globals[][name].toString())
    let val = interp.globals[][name]
    return (true, val)

  # Check if it's a property on self (only for Dictionary objects)
  if interp.currentReceiver != nil and interp.currentReceiver of DictionaryObj:
    let dict = cast[DictionaryObj](interp.currentReceiver)
    let prop = getProperty(dict, name)
    if prop.kind != vkNil:
      debug("Found property on self: ", name)
      return (true, prop)

  # Check if it's a slot on self (for objects with declared instance variables)
  if interp.currentReceiver != nil and interp.currentReceiver.hasSlots:
    if name in interp.currentReceiver.slotNames:
      let idx = interp.currentReceiver.slotNames[name]
      if idx < interp.currentReceiver.slots.len:
        let val = interp.currentReceiver.slots[idx]
        debug("Found slot on self: ", name, " = ", val.toString())
        return (true, val)

  debug("Variable not found: ", name)
  return (false, nilValue())

# Backward-compatible wrapper
proc lookupVariable(interp: Interpreter, name: string): NodeValue =
  ## Look up variable (returns nilValue if not found)
  lookupVariableWithStatus(interp, name).value

# Variable assignment
proc setVariable(interp: var Interpreter, name: string, value: NodeValue) =
  ## Set variable in current activation, captured environment, or create global
  debug("Setting variable: ", name, " = ", value.toString(), " (activation: ", interp.currentActivation != nil, ")")

  # First check if there's a current activation with a captured environment
  # that contains this variable
  if interp.currentActivation != nil:
    # Check if current method has a captured environment with this variable
    # This must be checked BEFORE locals because captured vars are copied to locals
    let currentMethod = interp.currentActivation.currentMethod
    if currentMethod != nil:
      if currentMethod.capturedEnv.len > 0 and name in currentMethod.capturedEnv:
        currentMethod.capturedEnv[name].value = value
        # Also update the local copy to keep them in sync
        interp.currentActivation.locals[name] = value
        return

    # Check if variable exists in current activation's locals
    if name in interp.currentActivation.locals:
      interp.currentActivation.locals[name] = value
      return

    # Check if variable exists in globals - if so, update it there
    if name in interp.globals[]:
      interp.globals[][name] = value
      debug("Global updated: ", name, " = ", value.toString())
      return

    # Check if it's a slot on self (for objects with declared instance variables)
    if interp.currentReceiver != nil and interp.currentReceiver.hasSlots:
      if name in interp.currentReceiver.slotNames:
        let idx = interp.currentReceiver.slotNames[name]
        if idx < interp.currentReceiver.slots.len:
          interp.currentReceiver.slots[idx] = value
          debug("Slot updated on self: ", name, " = ", value.toString())
          return

    # Create in current activation
    interp.currentActivation.locals[name] = value
    return

  # Set as global
  interp.globals[][name] = value
  debug("Global set: ", name, " now globals count: ", interp.globals[].len)

# ============================================================================
# Environment Capture and Block Invocation
# ============================================================================

proc captureEnvironment*(interp: Interpreter, blockNode: BlockNode) =
  ## Capture the current lexical environment when a block is created
  ## This walks up the activation chain and captures all local variables
  ## Variables captured by nested closures share the same MutableCell

  debug("Capturing environment for block")

  # Initialize captured environment if not already set
  # Note: Table is a value type, we check its length to see if initialized
  blockNode.capturedEnv = initTable[string, MutableCell]()

  # First, inherit captured variables from the current method if it's a block
  # This ensures nested closures share the same MutableCells
  if interp.currentActivation != nil and interp.currentActivation.currentMethod != nil:
    let currentMethod = interp.currentActivation.currentMethod
    if currentMethod.capturedEnv.len > 0:
      for name, cell in currentMethod.capturedEnv.pairs:
        blockNode.capturedEnv[name] = cell
        debug("Inherited captured variable from outer block: ", name)

  # Walk up the activation chain and capture all local variables
  var activation = interp.currentActivation
  while activation != nil:
    # Capture all locals from this activation (except 'self' and 'super')
    for name, value in activation.locals:
      if name != "self" and name != "super":
        # Only capture if not already captured (inner scope shadows outer)
        if not blockNode.capturedEnv.hasKey(name):
          # Check if this activation already has a captured cell for this variable
          # (from a sibling block created earlier in the same activation)
          var cell: MutableCell
          if activation.capturedVars.hasKey(name):
            # Share the existing cell from a sibling block
            cell = activation.capturedVars[name]
            debug("Sharing captured variable from sibling: ", name)
          else:
            # Create a new cell and store it in the activation for sibling blocks
            cell = MutableCell(value: value)
            activation.capturedVars[name] = cell
            debug("Captured variable: ", name, " = ", value.toString())
          blockNode.capturedEnv[name] = cell

    activation = activation.sender

  # Set home activation for non-local returns
  # The home activation is the method/block that lexically contains this block
  blockNode.homeActivation = interp.currentActivation
  debug("Set home activation for non-local returns")

proc invokeBlock*(interp: var Interpreter, blockNode: BlockNode, args: seq[NodeValue]): NodeValue =
  ## Invoke a block with the given arguments
  ## Creates a new activation with captured environment as parent scope

  debug("Invoking block with ", args.len, " arguments")

  # Check argument count
  if blockNode.parameters.len != args.len:
    raise newException(EvalError,
      "Wrong number of arguments to block: expected " & $blockNode.parameters.len &
      ", got " & $args.len)

  # Create activation for block execution
  # The receiver is the same as the current receiver
  let activation = newActivation(blockNode, interp.currentReceiver, interp.currentActivation)

  # Keep track of captured variable names so we can save them back
  var capturedVarNames: seq[string] = @[]

  # Bind captured environment variables to the new activation
  # This makes captured variables available in the block's scope
  if blockNode.capturedEnv.len > 0:
    for name, cell in blockNode.capturedEnv:
      activation.locals[name] = cell.value
      capturedVarNames.add(name)
      debug("Bound captured variable: ", name, " = ", cell.value.toString())

  # Bind parameters to arguments
  for i in 0..<blockNode.parameters.len:
    let paramName = blockNode.parameters[i]
    activation.locals[paramName] = args[i]
    debug("Bound parameter: ", paramName, " = ", args[i].toString())

  # Initialize temporaries to nil
  for tempName in blockNode.temporaries:
    activation.locals[tempName] = nilValue()
    debug("Initialized temporary: ", tempName)

  # Save current state
  let savedReceiver = interp.currentReceiver

  # Push the activation onto the stack
  interp.pushActivation(activation)

  # Execute block body
  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.eval(stmt)
      if activation.hasReturned:
        # Non-local return - the return value is already set in activation
        blockResult = activation.returnValue
        break
  finally:
    # Save captured variable values back to their cells (for mutable closures)
    # This ensures changes to captured variables persist across invocations
    if blockNode.capturedEnv.len > 0:
      for name in capturedVarNames:
        if name in activation.locals:
          blockNode.capturedEnv[name].value = activation.locals[name]
          debug("Saved captured variable: ", name, " = ", activation.locals[name].toString())

    # Pop the activation
    discard interp.popActivation()
    interp.currentReceiver = savedReceiver

  return blockResult

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

  of nkPseudoVar:
    # Pseudo-variable (self, nil, true, false)
    let pseudo = cast[PseudoVarNode](node)
    debug("Pseudo-variable: ", pseudo.name)
    case pseudo.name
    of "self":
      if interp.currentReceiver != nil:
        return interp.currentReceiver.toValue()
      return nilValue()
    of "nil":
      return nilValue()
    of "true":
      return trueValue
    of "false":
      return falseValue
    of "super":
      # Bare super without message - return current receiver (same as self)
      if interp.currentReceiver != nil:
        return interp.currentReceiver.toValue()
      return nilValue()
    else:
      return nilValue()

  of nkMessage:
    # Message send
    debug("Message send: ", node.MessageNode.selector)
    return interp.evalMessage(node.MessageNode)

  of nkBlock:
    # Block literal - create a copy and capture environment
    # We must copy because the AST node is shared and we need unique captured env per evaluation
    let origBlock = node.BlockNode
    let blockNode = BlockNode(
      parameters: origBlock.parameters,
      temporaries: origBlock.temporaries,
      body: origBlock.body,
      isMethod: origBlock.isMethod
      # capturedEnv and homeActivation will be set by captureEnvironment
    )
    captureEnvironment(interp, blockNode)
    return NodeValue(kind: vkBlock, blockVal: blockNode)

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

    # Determine the target activation for return
    # If we're inside a block, use the block's home activation (non-local return)
    # If we're in a method, return from that method (local return)
    var targetActivation: Activation = nil

    if interp.currentActivation != nil and interp.currentActivation.currentMethod != nil:
      let currentMethod = interp.currentActivation.currentMethod
      if not currentMethod.isMethod and currentMethod.homeActivation != nil:
        # We're in a block (not a method) - return from the block's home activation
        targetActivation = currentMethod.homeActivation
        debug("Non-local return from block to home activation")
      else:
        # We're in a method - local return from current method
        targetActivation = interp.currentActivation
        debug("Local return from method")

    if targetActivation != nil:
      targetActivation.returnValue = value
      targetActivation.hasReturned = true

      # Propagate hasReturned flag to all activations from current up to target
      var current = interp.currentActivation
      var safetyCount = 0
      while current != nil and current != targetActivation:
        inc safetyCount
        if safetyCount > 1000:
          raise newException(EvalError, "Return propagation exceeded 1000 activations - possible infinite loop")
        current.hasReturned = true
        # Also set return value on intermediate activations for proper propagation
        current.returnValue = value
        debug("Marked intermediate activation as returned")
        current = current.sender

      debug("Set return on target activation")

    return value

  of nkArray:
    # Array literal - evaluate each element
    let arr = node.ArrayNode
    debug("Evaluating array with ", arr.elements.len, " elements")
    var elements: seq[NodeValue] = @[]
    for elem in arr.elements:
      # Special handling for symbol literals inside arrays
      # They should be treated as literal symbols, not variable lookups
      if elem.kind == nkLiteral:
        let lit = elem.LiteralNode
        if lit.value.kind == vkSymbol:
          # Use symbol value directly, don't evaluate as variable
          debug("Symbol literal in array: ", lit.value.symVal)
          elements.add(lit.value)
          continue
      # Inside #(...), bare identifiers like 'a' in #(a b) are syntactic sugar for symbols
      # So #(name age) is equivalent to #(#name #age)
      # But true/false/nil/self/super are keywords with special handling
      if elem.kind == nkIdent:
        let ident = cast[IdentNode](elem)
        case ident.name
        of "true":
          elements.add(NodeValue(kind: vkBool, boolVal: true))
        of "false":
          elements.add(NodeValue(kind: vkBool, boolVal: false))
        of "nil":
          elements.add(nilValue())
        of "self":
          if interp.currentReceiver != nil:
            elements.add(interp.currentReceiver.toValue())
          else:
            elements.add(interp.globals[]["Object"])
        of "super":
          # super refers to parent of current receiver
          if interp.currentReceiver != nil and interp.currentReceiver.parents.len > 0:
            elements.add(interp.currentReceiver.parents[0].toValue())
          else:
            elements.add(interp.globals[]["Object"])
        else:
          debug("Identifier in array literal treated as symbol: ", ident.name)
          elements.add(getSymbol(ident.name))
        continue
      # Handle pseudo-variables (true, false, nil, self, super) when parsed as PseudoVarNode
      if elem.kind == nkPseudoVar:
        let pseudo = cast[PseudoVarNode](elem)
        case pseudo.name
        of "true":
          elements.add(NodeValue(kind: vkBool, boolVal: true))
        of "false":
          elements.add(NodeValue(kind: vkBool, boolVal: false))
        of "nil":
          elements.add(nilValue())
        of "self":
          if interp.currentReceiver != nil:
            elements.add(interp.currentReceiver.toValue())
          else:
            elements.add(interp.globals[]["Object"])
        of "super":
          # super refers to parent of current receiver
          if interp.currentReceiver != nil and interp.currentReceiver.parents.len > 0:
            elements.add(interp.currentReceiver.parents[0].toValue())
          else:
            elements.add(interp.globals[]["Object"])
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
      # Keys must evaluate to strings or symbols
      let keyVal = interp.eval(entry.key)
      var keyStr: string
      case keyVal.kind
      of vkString:
        keyStr = keyVal.strVal
      of vkSymbol:
        keyStr = keyVal.symVal
      else:
        raise newException(EvalError, "Table key must be string or symbol, got: " & $keyVal.kind)
      let valueVal = interp.eval(entry.value)
      table[keyStr] = valueVal
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

  of nkSlotAccess:
    # Slot access - O(1) direct instance variable access by index
    let slotNode = cast[SlotAccessNode](node)
    if interp.currentReceiver != nil:
      # Check if receiver is an Instance (new class-based model)
      if interp.currentReceiver of Instance:
        let inst = cast[Instance](interp.currentReceiver)
        if slotNode.slotIndex >= 0 and slotNode.slotIndex < inst.slots.len:
          return inst.slots[slotNode.slotIndex]
      # Fall back to legacy ProtoObject slot access by name
      else:
        return getSlot(interp.currentReceiver, slotNode.slotName)
    return nilValue()

  of nkSuperSend:
    # Super send - lookup method in parent class
    let superNode = cast[SuperSendNode](node)
    return interp.evalSuperSend(superNode)


# Evaluate a message send
proc evalMessage(interp: var Interpreter, msgNode: MessageNode): NodeValue =
  ## Evaluate a message send

  # Evaluate receiver
  let receiverVal = if msgNode.receiver != nil:
                      interp.eval(msgNode.receiver)
                    else:
                      interp.currentReceiver.toValue()

  debug("Checking receiver kind: ", receiverVal.kind, " selector: ", msgNode.selector)

  # Special handling for block invocation via value: messages
  if receiverVal.kind == vkBlock:
    case msgNode.selector
    of "value":
      # No arguments
      return invokeBlock(interp, receiverVal.blockVal, @[])
    of "value:":
      # One argument - evaluate arguments first
      var argValues: seq[NodeValue] = @[]
      for argNode in msgNode.arguments:
        argValues.add(interp.eval(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    of "value:value:":
      # Two arguments
      var argValues: seq[NodeValue] = @[]
      for argNode in msgNode.arguments:
        argValues.add(interp.eval(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    of "value:value:value:":
      # Three arguments
      var argValues: seq[NodeValue] = @[]
      for argNode in msgNode.arguments:
        argValues.add(interp.eval(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    of "value:value:value:value:":
      # Four arguments
      var argValues: seq[NodeValue] = @[]
      for argNode in msgNode.arguments:
        argValues.add(interp.eval(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    else:
      # Non-value: message sent to block - continue with normal dispatch
      discard

  debug("Message receiver: ", receiverVal.toString())

  # Wrap non-object receivers (like integers, booleans, strings, arrays, tables, blocks) in Nim proxy objects
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
                        of vkBlock:
                          wrapBlockAsObject(receiverVal.blockVal)
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

# Evaluate a super send
proc evalSuperSend(interp: var Interpreter, superNode: SuperSendNode): NodeValue =
  ## Evaluate super send - lookup method in parent class
  ## Unqualified super: lookup in parents[0]
  ## Qualified super<Parent>: lookup in specific parent

  if interp.currentReceiver == nil:
    raise newException(EvalError, "super send with no current receiver")

  # Get the class of the current receiver
  var cls: Class = nil
  if interp.currentReceiver of Instance:
    cls = cast[Instance](interp.currentReceiver).class
  elif interp.currentReceiver of ProtoObject:
    # Legacy: try to find class from protoObject
    # For now, raise error - super requires class-based model
    raise newException(EvalError, "super requires class-based object model")
  else:
    raise newException(EvalError, "super send on invalid receiver type")

  # Determine which parent to look in
  var targetParent: Class = nil
  if superNode.explicitParent.len > 0:
    # Qualified super<Parent>: find specific parent by name
    for parent in cls.parents:
      if parent.name == superNode.explicitParent:
        targetParent = parent
        break
    if targetParent == nil:
      raise newException(EvalError, "Parent class '" & superNode.explicitParent & "' not found in inheritance chain")
  else:
    # Unqualified super: use first parent
    if cls.parents.len == 0:
      raise newException(EvalError, "super send in class with no parents")
    targetParent = cls.parents[0]

  # Look up method in target parent's allMethods
  let methodBlock = lookupInstanceMethod(targetParent, superNode.selector)
  if methodBlock == nil:
    raise newException(EvalError, "Method '" & superNode.selector & "' not found in super class " & targetParent.name)

  # Evaluate arguments
  var arguments = newSeq[NodeValue]()
  for argNode in superNode.arguments:
    arguments.add(interp.eval(argNode))

  # Convert arguments to AST nodes
  var argNodes = newSeq[Node]()
  for argVal in arguments:
    argNodes.add(LiteralNode(value: argVal))

  # Execute the method with current receiver
  return interp.executeMethod(methodBlock, interp.currentReceiver, argNodes, nil)

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
  except ValueError as e:
    raise  # Re-raise ValueError for error handling tests
  except EvalError as e:
    return (nilValue(), "Runtime error: " & e.msg)
  except Exception as e:
    return (nilValue(), "Error: " & e.msg)

# Batch evaluation of multiple statements
proc evalStatements*(interp: var Interpreter, source: string): (seq[NodeValue], string) =
  ## Parse and evaluate multiple statements
  debug("evalStatements: starting lex")
  let tokens = lex(source)
  debug("evalStatements: got ", tokens.len, " tokens, starting parse")
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()
  debug("evalStatements: parsed ", nodes.len, " nodes, parser pos=", parser.pos, ", hasError=", parser.hasError)
  if parser.pos < parser.tokens.len:
    debug("evalStatements: leftover token at pos ", parser.pos, " = ", parser.tokens[parser.pos].kind, " value='", parser.tokens[parser.pos].value, "'")

  if parser.hasError:
    return (@[], "Parse error: " & parser.errorMsg)

  var results = newSeq[NodeValue]()

  debug("evalStatements: starting evaluation")
  try:
    for i, node in nodes:
      debug("evalStatements: evaluating node ", i, " of ", nodes.len)
      let evalResult = interp.eval(node)
      results.add(evalResult)

    debug("evalStatements: done, returning ", results.len, " results")
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

proc evalBlockWithArg(interp: var Interpreter, receiver: ProtoObject, blockNode: BlockNode, arg: NodeValue): NodeValue =
  ## Evaluate a block with one argument
  let activation = newActivation(blockNode, receiver, interp.currentActivation)

  # Bind the first parameter to the argument
  if blockNode.parameters.len > 0:
    activation.locals[blockNode.parameters[0]] = arg

  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.eval(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue
        break
  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult

# asSelfDo: implementation (interpreter-aware)
proc asSelfDoImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Evaluate a block with self temporarily bound to the receiver
  ## Usage: someObject asSelfDo: [ ... self ... ]
  ## Inside the block, 'self' refers to someObject
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  let blockNode = args[0].blockVal

  # Evaluate the block with self (the receiver) as the receiver
  # This makes 'self' inside the block refer to the receiver of asSelfDo:
  return evalBlock(interp, self, blockNode)

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

# Loop method implementations (interpreter-aware)
proc whileTrueImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Execute bodyBlock while conditionBlock evaluates to true: [cond] whileTrue: [body]
  ## self is the condition block (receiver), args[0] is the body block
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Extract condition block node from self (stored in properties by wrapBlockAsObject)
  var conditionBlock: BlockNode = nil
  if self of DictionaryObj:
    let dict = cast[DictionaryObj](self)
    if dict.properties.hasKey("__blockNode"):
      let blockVal = dict.properties["__blockNode"]
      if blockVal.kind == vkBlock:
        conditionBlock = blockVal.blockVal

  if conditionBlock == nil:
    return nilValue()

  let bodyBlock = args[0].blockVal
  var lastResult = nilValue()

  # Loop while condition is true
  while true:
    # Evaluate condition block
    let conditionResult = evalBlock(interp, interp.currentReceiver, conditionBlock)

    # Check if condition is true
    var conditionIsTrue = false
    if conditionResult.kind == vkBool:
      conditionIsTrue = conditionResult.boolVal
    elif conditionResult.kind == vkObject and conditionResult.objVal.isNimProxy and conditionResult.objVal.nimType == "bool":
      conditionIsTrue = cast[ptr bool](conditionResult.objVal.nimValue)[]
    else:
      # Non-boolean condition - treat as false to exit loop
      break

    if not conditionIsTrue:
      break

    # Execute body block
    lastResult = evalBlock(interp, interp.currentReceiver, bodyBlock)

  return lastResult

proc whileFalseImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Execute bodyBlock while conditionBlock evaluates to false: [cond] whileFalse: [body]
  ## self is the condition block (receiver), args[0] is the body block
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Extract condition block node from self (stored in properties by wrapBlockAsObject)
  var conditionBlock: BlockNode = nil
  if self of DictionaryObj:
    let dict = cast[DictionaryObj](self)
    if dict.properties.hasKey("__blockNode"):
      let blockVal = dict.properties["__blockNode"]
      if blockVal.kind == vkBlock:
        conditionBlock = blockVal.blockVal

  if conditionBlock == nil:
    return nilValue()

  let bodyBlock = args[0].blockVal
  var lastResult = nilValue()

  # Loop while condition is false
  while true:
    # Evaluate condition block
    let conditionResult = evalBlock(interp, interp.currentReceiver, conditionBlock)

    # Check if condition is false
    var conditionIsTrue = false
    if conditionResult.kind == vkBool:
      conditionIsTrue = conditionResult.boolVal
    elif conditionResult.kind == vkObject and conditionResult.objVal.isNimProxy and conditionResult.objVal.nimType == "bool":
      conditionIsTrue = cast[ptr bool](conditionResult.objVal.nimValue)[]
    else:
      # Non-boolean condition - treat as true to exit loop
      break

    if conditionIsTrue:
      break

    # Execute body block
    lastResult = evalBlock(interp, interp.currentReceiver, bodyBlock)

  return lastResult

# Exception handling methods
proc onDoImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Install exception handler: [ protectedBlock ] on: ExceptionClass do: [ :ex | handler ]
  ## self is the protected block (receiver), args[0] is exception class, args[1] is handler block
  if args.len < 2 or args[1].kind != vkBlock:
    return nilValue()

  # Extract protected block from self
  var protectedBlock: BlockNode = nil
  if self of DictionaryObj:
    let dict = cast[DictionaryObj](self)
    if dict.properties.hasKey("__blockNode"):
      let blockVal = dict.properties["__blockNode"]
      if blockVal.kind == vkBlock:
        protectedBlock = blockVal.blockVal

  if protectedBlock == nil:
    return nilValue()

  let exceptionClass = args[0]
  let handlerBlock = args[1].blockVal

  # Push exception handler onto stack
  let handler = ExceptionHandler(
    exceptionClass: if exceptionClass.kind == vkObject: exceptionClass.objVal else: nil,
    handlerBlock: handlerBlock,
    activation: interp.currentActivation,
    stackDepth: interp.activationStack.len
  )
  interp.exceptionHandlers.add(handler)

  var blockResult = nilValue()
  try:
    # Execute protected block
    blockResult = evalBlock(interp, interp.currentReceiver, protectedBlock)
  except ValueError as e:
    # Check if we have a handler for this exception type
    var handled = false
    for i in countdown(interp.exceptionHandlers.len - 1, 0):
      let h = interp.exceptionHandlers[i]
      # Simple type check - in full implementation, check inheritance
      if h.stackDepth <= interp.activationStack.len:
        # Found a handler - execute it
        let exObj = ExceptionObj()
        exObj.message = e.msg
        exObj.stackTrace = "Stack trace placeholder"
        exObj.methods = initTable[string, BlockNode]()
        exObj.parents = @[rootObject.ProtoObject]
        exObj.tags = @["Exception", "Error"]
        exObj.isNimProxy = false
        exObj.hasSlots = false

        # Remove this handler and all above it
        interp.exceptionHandlers.setLen(i)

        # Execute handler with exception as argument
        let exVal = NodeValue(kind: vkObject, objVal: exObj.ProtoObject)
        blockResult = evalBlockWithArg(interp, interp.currentReceiver, h.handlerBlock, exVal)
        handled = true
        break

    if not handled:
      # No handler found - re-raise
      raise
  finally:
    # Remove our handler if still present (if no exception was raised)
    if interp.exceptionHandlers.len > 0:
      let lastIdx = interp.exceptionHandlers.len - 1
      if interp.exceptionHandlers[lastIdx].handlerBlock == handlerBlock:
        interp.exceptionHandlers.setLen(lastIdx)

  return blockResult

proc signalImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Signal an exception: exception signal
  ## self is the exception object
  var message = "Unknown error"
  if args.len >= 1 and args[0].kind == vkString:
    message = args[0].strVal
  elif self of ExceptionObj:
    let ex = cast[ExceptionObj](self)
    message = ex.message
  raise newException(ValueError, message)

# Global namespace methods - using shared table reference
proc globalAtImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Global at: key - lookup global by name
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()
  let key = args[0].strVal
  if interp.globals[].hasKey(key):
    return interp.globals[][key]
  return nilValue()

proc globalAtPutImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Global at: key put: value - set global
  if args.len < 2 or args[0].kind != vkString:
    return nilValue()
  let key = args[0].strVal
  let val = args[1]
  interp.globals[][key] = val
  return val

proc globalAtIfAbsentImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Global at: key ifAbsent: block - lookup or execute block
  if args.len < 2 or args[0].kind != vkString or args[1].kind != vkBlock:
    return nilValue()
  let key = args[0].strVal
  if interp.globals[].hasKey(key):
    return interp.globals[][key]
  # Execute the ifAbsent block
  return evalBlock(interp, self, args[1].blockVal)

# Array iteration method
proc arrayDoImpl(interp: var Interpreter, self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Iterate over array elements: arr do: [ :elem | code ]
  ## self is the array, args[0] is the block to execute for each element
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Check if this is an array
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)
  if not dict.properties.hasKey("__size"):
    return nilValue()

  let size = dict.properties["__size"].intVal
  let blockNode = args[0].blockVal
  var lastResult = nilValue()

  # Iterate over array elements (1-based indexing for Smalltalk)
  for i in 1..size:
    let elem = dict.properties.getOrDefault($(i-1))  # Convert to 0-based for storage
    # Invoke block with element as argument
    lastResult = interp.invokeBlock(blockNode, @[elem])

  return lastResult

# Built-in globals
proc initGlobals*(interp: var Interpreter) =
  ## Initialize built-in global variables

  # Add some useful constants
  interp.globals[]["Object"] = interp.rootObject.toValue()
  interp.globals[]["root"] = interp.rootObject.toValue()

  # Add Dictionary to globals
  if dictionaryPrototype != nil:
    interp.globals[]["Dictionary"] = dictionaryPrototype.ProtoObject.toValue()

  # Create Float prototype
  let floatProto = ProtoObject()
  floatProto.methods = initTable[string, BlockNode]()
  floatProto.parents = @[interp.rootObject.ProtoObject]
  floatProto.tags = @["Float", "Number"]
  floatProto.isNimProxy = false
  floatProto.nimValue = nil
  floatProto.nimType = ""
  floatProto.hasSlots = false
  floatProto.slots = @[]
  floatProto.slotNames = initTable[string, int]()
  interp.globals[]["Float"] = floatProto.toValue()

  # Create Array prototype
  let arrayProto = ProtoObject()
  arrayProto.methods = initTable[string, BlockNode]()
  arrayProto.parents = @[interp.rootObject.ProtoObject]
  arrayProto.tags = @["Array", "Collection"]
  arrayProto.isNimProxy = false
  arrayProto.nimValue = nil
  arrayProto.nimType = ""
  arrayProto.hasSlots = false
  arrayProto.slots = @[]
  arrayProto.slotNames = initTable[string, int]()

  # Add Array primitive methods
  let arrayNewMethod = createCoreMethod("primitiveNew:")
  arrayNewMethod.nativeImpl = cast[pointer](arrayNewImpl)
  addMethod(arrayProto, "primitiveNew:", arrayNewMethod)

  let arraySizeMethod = createCoreMethod("primitiveSize")
  arraySizeMethod.nativeImpl = cast[pointer](arraySizeImpl)
  addMethod(arrayProto, "primitiveSize", arraySizeMethod)

  let arrayAddMethod = createCoreMethod("primitiveAdd:")
  arrayAddMethod.nativeImpl = cast[pointer](arrayAddImpl)
  addMethod(arrayProto, "primitiveAdd:", arrayAddMethod)

  let arrayAddAliasMethod = createCoreMethod("add:")
  arrayAddAliasMethod.nativeImpl = cast[pointer](arrayAddImpl)
  addMethod(arrayProto, "add:", arrayAddAliasMethod)

  let arrayAtMethod = createCoreMethod("at:")
  arrayAtMethod.nativeImpl = cast[pointer](arrayAtImpl)
  addMethod(arrayProto, "at:", arrayAtMethod)

  let arrayAtPutMethod = createCoreMethod("at:put:")
  arrayAtPutMethod.nativeImpl = cast[pointer](arrayAtPutImpl)
  addMethod(arrayProto, "at:put:", arrayAtPutMethod)

  let arrayRemoveAtMethod = createCoreMethod("primitiveRemoveAt:")
  arrayRemoveAtMethod.nativeImpl = cast[pointer](arrayRemoveAtImpl)
  addMethod(arrayProto, "primitiveRemoveAt:", arrayRemoveAtMethod)

  let arrayIncludesMethod = createCoreMethod("primitiveIncludes:")
  arrayIncludesMethod.nativeImpl = cast[pointer](arrayIncludesImpl)
  addMethod(arrayProto, "primitiveIncludes:", arrayIncludesMethod)

  let arrayReverseMethod = createCoreMethod("primitiveReverse")
  arrayReverseMethod.nativeImpl = cast[pointer](arrayReverseImpl)
  addMethod(arrayProto, "primitiveReverse", arrayReverseMethod)

  let arrayDoMethod = createCoreMethod("do:")
  arrayDoMethod.nativeImpl = cast[pointer](arrayDoImpl)
  arrayDoMethod.hasInterpreterParam = true
  addMethod(arrayProto, "do:", arrayDoMethod)

  interp.globals[]["Array"] = arrayProto.toValue()
  arrayPrototypeCache = arrayProto  # Set cache for array literals

  # Create Table prototype
  let tableProto = ProtoObject()
  tableProto.methods = initTable[string, BlockNode]()
  tableProto.parents = @[interp.rootObject.ProtoObject]
  tableProto.tags = @["Table", "Collection", "Dictionary"]
  tableProto.isNimProxy = false
  tableProto.nimValue = nil
  tableProto.nimType = ""
  tableProto.hasSlots = false
  tableProto.slots = @[]
  tableProto.slotNames = initTable[string, int]()

  # Add Table primitive methods
  let tableNewMethod = createCoreMethod("primitiveTableNew")
  tableNewMethod.nativeImpl = cast[pointer](tableNewImpl)
  addMethod(tableProto, "primitiveTableNew", tableNewMethod)

  let tableAtMethod = createCoreMethod("at:")
  tableAtMethod.nativeImpl = cast[pointer](tableAtImpl)
  addMethod(tableProto, "at:", tableAtMethod)

  let tableAtPutMethod = createCoreMethod("at:put:")
  tableAtPutMethod.nativeImpl = cast[pointer](tableAtPutImpl)
  addMethod(tableProto, "at:put:", tableAtPutMethod)

  let tableKeysMethod = createCoreMethod("primitiveKeys")
  tableKeysMethod.nativeImpl = cast[pointer](tableKeysImpl)
  addMethod(tableProto, "primitiveKeys", tableKeysMethod)

  let tableIncludesKeyMethod = createCoreMethod("primitiveIncludesKey:")
  tableIncludesKeyMethod.nativeImpl = cast[pointer](tableIncludesKeyImpl)
  addMethod(tableProto, "primitiveIncludesKey:", tableIncludesKeyMethod)

  let tableRemoveKeyMethod = createCoreMethod("primitiveRemoveKey:")
  tableRemoveKeyMethod.nativeImpl = cast[pointer](tableRemoveKeyImpl)
  addMethod(tableProto, "primitiveRemoveKey:", tableRemoveKeyMethod)

  interp.globals[]["Table"] = tableProto.toValue()

  # Create String prototype
  let stringProto = ProtoObject()
  stringProto.methods = initTable[string, BlockNode]()
  stringProto.parents = @[interp.rootObject.ProtoObject]
  stringProto.tags = @["String", "Text"]
  stringProto.isNimProxy = false
  stringProto.nimValue = nil
  stringProto.nimType = ""
  stringProto.hasSlots = false
  stringProto.slots = @[]
  stringProto.slotNames = initTable[string, int]()

  # Add String primitive methods
  let stringConcatMethod = createCoreMethod("primitiveConcat:")
  stringConcatMethod.nativeImpl = cast[pointer](stringConcatImpl)
  addMethod(stringProto, "primitiveConcat:", stringConcatMethod)

  let stringSizeMethod = createCoreMethod("primitiveStringSize")
  stringSizeMethod.nativeImpl = cast[pointer](stringSizeImpl)
  addMethod(stringProto, "primitiveStringSize", stringSizeMethod)

  let stringAtMethod = createCoreMethod("primitiveStringAt:")
  stringAtMethod.nativeImpl = cast[pointer](stringAtImpl)
  addMethod(stringProto, "primitiveStringAt:", stringAtMethod)

  let stringFromToMethod = createCoreMethod("primitiveFromTo:")
  stringFromToMethod.nativeImpl = cast[pointer](stringFromToImpl)
  addMethod(stringProto, "primitiveFromTo:", stringFromToMethod)

  let stringIndexOfMethod = createCoreMethod("primitiveIndexOf:")
  stringIndexOfMethod.nativeImpl = cast[pointer](stringIndexOfImpl)
  addMethod(stringProto, "primitiveIndexOf:", stringIndexOfMethod)

  let stringIncludesSubStringMethod = createCoreMethod("primitiveIncludesSubString:")
  stringIncludesSubStringMethod.nativeImpl = cast[pointer](stringIncludesSubStringImpl)
  addMethod(stringProto, "primitiveIncludesSubString:", stringIncludesSubStringMethod)

  let stringReplaceWithMethod = createCoreMethod("primitiveReplaceWith:")
  stringReplaceWithMethod.nativeImpl = cast[pointer](stringReplaceWithImpl)
  addMethod(stringProto, "primitiveReplaceWith:", stringReplaceWithMethod)

  let stringUppercaseMethod = createCoreMethod("primitiveUppercase")
  stringUppercaseMethod.nativeImpl = cast[pointer](stringUppercaseImpl)
  addMethod(stringProto, "primitiveUppercase", stringUppercaseMethod)

  let stringLowercaseMethod = createCoreMethod("primitiveLowercase")
  stringLowercaseMethod.nativeImpl = cast[pointer](stringLowercaseImpl)
  addMethod(stringProto, "primitiveLowercase", stringLowercaseMethod)

  let stringTrimMethod = createCoreMethod("primitiveTrim")
  stringTrimMethod.nativeImpl = cast[pointer](stringTrimImpl)
  addMethod(stringProto, "primitiveTrim", stringTrimMethod)

  let stringSplitMethod = createCoreMethod("primitiveSplit:")
  stringSplitMethod.nativeImpl = cast[pointer](stringSplitImpl)
  addMethod(stringProto, "primitiveSplit:", stringSplitMethod)

  interp.globals[]["String"] = stringProto.toValue()

  # Create FileStream prototype
  let fileStreamProto = FileStreamObj()
  fileStreamProto.methods = initTable[string, BlockNode]()
  fileStreamProto.parents = @[interp.rootObject.ProtoObject]
  fileStreamProto.tags = @["FileStream", "IO"]
  fileStreamProto.isNimProxy = false
  fileStreamProto.nimValue = nil
  fileStreamProto.nimType = ""
  fileStreamProto.hasSlots = false
  fileStreamProto.slots = @[]
  fileStreamProto.slotNames = initTable[string, int]()
  fileStreamProto.file = nil
  fileStreamProto.mode = ""
  fileStreamProto.isOpen = false

  # Add FileStream primitive methods
  let fileOpenMethod = createCoreMethod("primitiveFileOpen:mode:")
  fileOpenMethod.nativeImpl = cast[pointer](fileOpenImpl)
  addMethod(fileStreamProto.ProtoObject, "primitiveFileOpen:mode:", fileOpenMethod)

  let fileCloseMethod = createCoreMethod("primitiveFileClose")
  fileCloseMethod.nativeImpl = cast[pointer](fileCloseImpl)
  addMethod(fileStreamProto.ProtoObject, "primitiveFileClose", fileCloseMethod)

  let fileReadLineMethod = createCoreMethod("primitiveFileReadLine")
  fileReadLineMethod.nativeImpl = cast[pointer](fileReadLineImpl)
  addMethod(fileStreamProto.ProtoObject, "primitiveFileReadLine", fileReadLineMethod)

  let fileWriteMethod = createCoreMethod("primitiveFileWrite:")
  fileWriteMethod.nativeImpl = cast[pointer](fileWriteImpl)
  addMethod(fileStreamProto.ProtoObject, "primitiveFileWrite:", fileWriteMethod)

  let fileAtEndMethod = createCoreMethod("primitiveFileAtEnd")
  fileAtEndMethod.nativeImpl = cast[pointer](fileAtEndImpl)
  addMethod(fileStreamProto.ProtoObject, "primitiveFileAtEnd", fileAtEndMethod)

  let fileReadAllMethod = createCoreMethod("primitiveFileReadAll")
  fileReadAllMethod.nativeImpl = cast[pointer](fileReadAllImpl)
  addMethod(fileStreamProto.ProtoObject, "primitiveFileReadAll", fileReadAllMethod)

  interp.globals[]["FileStream"] = fileStreamProto.ProtoObject.toValue()

  # Add Random to globals
  if randomPrototype != nil:
    interp.globals[]["Random"] = randomPrototype.ProtoObject.toValue()

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

  interp.globals[]["Stdout"] = stdoutObj.toValue()
  interp.globals[]["stdout"] = stdoutObj.toValue()

  # Create Transcript object for logging/output
  let transcriptObj = ProtoObject()
  transcriptObj.methods = initTable[string, BlockNode]()
  transcriptObj.parents = @[interp.rootObject.ProtoObject]
  transcriptObj.tags = @["Transcript"]
  transcriptObj.isNimProxy = false
  transcriptObj.nimValue = nil
  transcriptObj.nimType = ""
  transcriptObj.hasSlots = false
  transcriptObj.slotNames = initTable[string, int]()

  let showMethod = createCoreMethod("show:")
  showMethod.nativeImpl = cast[pointer](writeImpl)
  addMethod(transcriptObj, "show:", showMethod)

  let crMethod = createCoreMethod("cr")
  crMethod.nativeImpl = cast[pointer](writelineImpl)
  addMethod(transcriptObj, "cr", crMethod)

  let showCrMethod = createCoreMethod("show:cr:")
  showCrMethod.nativeImpl = cast[pointer](writelineImpl)
  addMethod(transcriptObj, "show:cr:", showCrMethod)

  interp.globals[]["Transcript"] = transcriptObj.toValue()

  # Create Global namespace object with shared table reference
  let globalObj = GlobalObj()
  globalObj.methods = initTable[string, BlockNode]()
  globalObj.parents = @[interp.rootObject.ProtoObject]
  globalObj.tags = @["Global", "Registry"]
  globalObj.isNimProxy = false
  globalObj.nimValue = nil
  globalObj.nimType = ""
  globalObj.hasSlots = false
  globalObj.slots = @[]
  globalObj.slotNames = initTable[string, int]()
  globalObj.tableRef = interp.globals  # Share the heap-allocated table!
  globalObj.categories = initTable[string, seq[string]]()

  # Add at: and at:put: methods to Global
  let globalAtMethod = createCoreMethod("at:")
  globalAtMethod.nativeImpl = cast[pointer](globalAtImpl)
  globalAtMethod.hasInterpreterParam = true
  addMethod(globalObj.ProtoObject, "at:", globalAtMethod)

  let globalAtPutMethod = createCoreMethod("at:put:")
  globalAtPutMethod.nativeImpl = cast[pointer](globalAtPutImpl)
  globalAtPutMethod.hasInterpreterParam = true
  addMethod(globalObj.ProtoObject, "at:put:", globalAtPutMethod)

  let globalAtIfAbsentMethod = createCoreMethod("at:ifAbsent:")
  globalAtIfAbsentMethod.nativeImpl = cast[pointer](globalAtIfAbsentImpl)
  globalAtIfAbsentMethod.hasInterpreterParam = true
  addMethod(globalObj.ProtoObject, "at:ifAbsent:", globalAtIfAbsentMethod)

  interp.globals[]["Global"] = globalObj.ProtoObject.toValue()

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

  # Create Block prototype with loop methods
  let blockProto = ProtoObject()
  blockProto.methods = initTable[string, BlockNode]()
  blockProto.parents = @[interp.rootObject.ProtoObject]
  blockProto.tags = @["Block", "Closure"]
  blockProto.isNimProxy = false
  blockProto.nimValue = nil
  blockProto.nimType = ""
  blockProto.hasSlots = false
  blockProto.slots = @[]
  blockProto.slotNames = initTable[string, int]()

  let whileTrueMethod = createCoreMethod("whileTrue:")
  whileTrueMethod.nativeImpl = cast[pointer](whileTrueImpl)
  whileTrueMethod.hasInterpreterParam = true
  addMethod(blockProto, "whileTrue:", whileTrueMethod)

  let whileFalseMethod = createCoreMethod("whileFalse:")
  whileFalseMethod.nativeImpl = cast[pointer](whileFalseImpl)
  whileFalseMethod.hasInterpreterParam = true
  addMethod(blockProto, "whileFalse:", whileFalseMethod)

  let onDoMethod = createCoreMethod("on:do:")
  onDoMethod.nativeImpl = cast[pointer](onDoImpl)
  onDoMethod.hasInterpreterParam = true
  addMethod(blockProto, "on:do:", onDoMethod)

  interp.globals[]["Block"] = blockProto.toValue()

  interp.globals[]["true"] = trueObj.toValue()
  interp.globals[]["false"] = falseObj.toValue()
  interp.globals[]["nil"] = nilValue()

  # Set global true/false values for comparison operators
  trueValue = trueObj.toValue()
  falseValue = falseObj.toValue()

  # Create Exception prototype
  let exceptionProto = ExceptionObj()
  exceptionProto.methods = initTable[string, BlockNode]()
  exceptionProto.parents = @[interp.rootObject.ProtoObject]
  exceptionProto.tags = @["Exception", "Error"]
  exceptionProto.isNimProxy = false
  exceptionProto.nimValue = nil
  exceptionProto.nimType = ""
  exceptionProto.hasSlots = false
  exceptionProto.slots = @[]
  exceptionProto.slotNames = initTable[string, int]()
  exceptionProto.message = ""
  exceptionProto.stackTrace = ""
  exceptionProto.signaler = nil

  let signalMethod = createCoreMethod("signal:")
  signalMethod.nativeImpl = cast[pointer](signalImpl)
  addMethod(exceptionProto.ProtoObject, "signal:", signalMethod)

  let signalNoArgMethod = createCoreMethod("signal")
  signalNoArgMethod.nativeImpl = cast[pointer](signalImpl)
  addMethod(exceptionProto.ProtoObject, "signal", signalNoArgMethod)

  interp.globals[]["Exception"] = exceptionProto.ProtoObject.toValue()
  interp.globals[]["Error"] = exceptionProto.ProtoObject.toValue()

  # Note: do: method is registered on array and table proxy objects dynamically
  # It would be better to have a Collection prototype, but for now we rely on
  # the atCollectionImpl method registered on rootObject for at: access

# Load standard library files
proc loadStdlib*(interp: var Interpreter, basePath: string = "") =
  ## Load core library files from lib/core/
  ## basePath allows specifying a different root (e.g., for tests or installed location)
  let libPath = if basePath.len > 0: basePath / "lib" / "core" else: "lib" / "core"

  let stdlibFiles = [
    "Object.nt",
    "Boolean.nt",
    "Block.nt",
    "Number.nt",
    "Collections.nt",
    "String.nt",
    "FileStream.nt",
    "Exception.nt",
    "TestCase.nt"
  ]

  for filename in stdlibFiles:
    let filepath = libPath / filename
    if fileExists(filepath):
      debug("Loading stdlib file: ", filepath)
      let source = readFile(filepath)
      let (_, err) = interp.evalStatements(source)
      if err.len > 0:
        warn("Failed to load ", filepath, ": ", err)
      else:
        debug("Successfully loaded: ", filepath)
    else:
      warn("Stdlib file not found: ", filepath)

  # Set up prototype caches for primitive types
  # These allow wrapped primitives to inherit methods from stdlib
  if "Integer" in interp.globals[]:
    let intVal = interp.globals[]["Integer"]
    if intVal.kind == vkObject:
      integerPrototypeCache = intVal.objVal
      debug("Set integerPrototypeCache from Integer global")

  if "String" in interp.globals[]:
    let strVal = interp.globals[]["String"]
    if strVal.kind == vkObject:
      stringPrototypeCache = strVal.objVal
      debug("Set stringPrototypeCache from String global")

  if "True" in interp.globals[]:
    let trueVal = interp.globals[]["True"]
    if trueVal.kind == vkObject:
      truePrototypeCache = trueVal.objVal
      debug("Set truePrototypeCache from True global")

  if "False" in interp.globals[]:
    let falseVal = interp.globals[]["False"]
    if falseVal.kind == vkObject:
      falsePrototypeCache = falseVal.objVal
      debug("Set falsePrototypeCache from False global")

  if "Block" in interp.globals[]:
    let blockVal = interp.globals[]["Block"]
    if blockVal.kind == vkObject:
      blockPrototypeCache = blockVal.objVal
      debug("Set blockPrototypeCache from Block global")

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
