import std/[tables, strutils, math, strformat, logging, os, hashes]
import ../core/types
import ../parser/lexer
import ../parser/parser
import ../interpreter/objects
import ../interpreter/activation
# Note: SchedulerContext is defined in types.nim
# initProcessorGlobal is called by newSchedulerContext in scheduler.nim

# Class caches are defined in objects.nim and shared across the interpreter

# Forward declarations - implementations are in objects.nim
# Note: These are imported from objects.nim via the import statement above
# They are re-exported for backward compatibility with code that imports evaluator

# ============================================================================
# Evaluation engine for Nemo
# Interprets AST nodes and executes currentMethods
# ============================================================================

# Protected globals that cannot be reassigned
var protectedGlobals*: seq[string] = @["Nemo", "GlobalTable", "Object", "Root", "Mixin", "nil", "true", "false"]

# Add a global to the protected list
proc protectGlobal*(name: string) =
  ## Protect a global variable from being reassigned
  if name notin protectedGlobals:
    protectedGlobals.add(name)

# Check if a name is a protected global
proc isProtectedGlobal*(name: string): bool =
  ## Check if a global variable is protected from reassignment
  name in protectedGlobals

type
  EvalError* = object of ValueError
    node*: Node

# Forward declarations
proc evalOld*(interp: var Interpreter, node: Node): NodeValue
proc evalMessage(interp: var Interpreter, msgNode: MessageNode): NodeValue
proc evalCascade(interp: var Interpreter, cascadeNode: CascadeNode): NodeValue
proc evalSuperSend(interp: var Interpreter, superNode: SuperSendNode): NodeValue
proc sendMessage*(interp: var Interpreter, receiver: Instance, selector: string, args: varargs[NodeValue]): NodeValue
proc performWithImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue
proc installGlobalTableMethods*(globalTableClass: Class)
proc initNemoGlobal*(interp: var Interpreter)

# ============================================================================
# AST Rewriter for Slot Access
# Rewrites IdentNodes to SlotAccessNodes where name matches a class slot
# This enables O(1) slot access by integer index instead of string lookup
# ============================================================================

proc rewriteNodeForSlotAccess(node: Node, cls: Class, shadowedNames: seq[string]): Node =
  ## Recursively rewrite a node, replacing slot access patterns with SlotAccessNodes
  ## shadowedNames contains parameter and temporary names that shadow slots
  if node == nil:
    return nil

  case node.kind
  of nkIdent:
    # Check if this identifier is a slot name (and not shadowed)
    let ident = cast[IdentNode](node)
    debug("rewriteNode: nkIdent name=", ident.name)
    if ident.name notin shadowedNames:
      let idx = cls.getSlotIndex(ident.name)
      debug("rewriteNode: slot lookup for '", ident.name, "' = ", $idx)
      if idx >= 0:
        # Replace with SlotAccessNode for O(1) access
        debug("rewriteNode: replacing ident '", ident.name, "' with SlotAccessNode index=", $idx)
        return SlotAccessNode(
          slotName: ident.name,
          slotIndex: idx,
          isAssignment: false,
          valueExpr: nil
        )
    return node

  of nkAssign:
    # Check if assignment target is a slot name
    let assign = cast[AssignNode](node)
    debug("rewriteNode: nkAssign var=", assign.variable)
    if assign.variable notin shadowedNames:
      let idx = cls.getSlotIndex(assign.variable)
      debug("rewriteNode: slot lookup for assignment '", assign.variable, "' = ", $idx)
      if idx >= 0:
        # Replace with SlotAccessNode for O(1) slot write
        debug("rewriteNode: replacing assignment '", assign.variable, "' with SlotAccessNode index=", $idx)
        return SlotAccessNode(
          slotName: assign.variable,
          slotIndex: idx,
          isAssignment: true,
          valueExpr: rewriteNodeForSlotAccess(assign.expression, cls, shadowedNames)
        )
    # Not a slot - rewrite the expression part only
    assign.expression = rewriteNodeForSlotAccess(assign.expression, cls, shadowedNames)
    return assign

  of nkMessage:
    # Rewrite receiver and arguments
    let msg = cast[MessageNode](node)
    if msg.receiver != nil:
      msg.receiver = rewriteNodeForSlotAccess(msg.receiver, cls, shadowedNames)
    for i in 0..<msg.arguments.len:
      msg.arguments[i] = rewriteNodeForSlotAccess(msg.arguments[i], cls, shadowedNames)
    return msg

  of nkReturn:
    # Rewrite return expression
    let ret = cast[ReturnNode](node)
    if ret.expression != nil:
      ret.expression = rewriteNodeForSlotAccess(ret.expression, cls, shadowedNames)
    return ret

  of nkBlock:
    # Rewrite block body, but add block's parameters and temporaries to shadowed names
    let blk = cast[BlockNode](node)
    var newShadowed = shadowedNames
    for param in blk.parameters:
      newShadowed.add(param)
    for temp in blk.temporaries:
      newShadowed.add(temp)
    for i in 0..<blk.body.len:
      blk.body[i] = rewriteNodeForSlotAccess(blk.body[i], cls, newShadowed)
    return blk

  of nkCascade:
    # Rewrite cascade receiver and all messages
    let cascade = cast[CascadeNode](node)
    if cascade.receiver != nil:
      cascade.receiver = rewriteNodeForSlotAccess(cascade.receiver, cls, shadowedNames)
    for i in 0..<cascade.messages.len:
      let msg = cascade.messages[i]
      for j in 0..<msg.arguments.len:
        msg.arguments[j] = rewriteNodeForSlotAccess(msg.arguments[j], cls, shadowedNames)
    return cascade

  of nkPrimitiveCall:
    # Rewrite primitive arguments
    let prim = cast[PrimitiveCallNode](node)
    for i in 0..<prim.arguments.len:
      prim.arguments[i] = rewriteNodeForSlotAccess(prim.arguments[i], cls, shadowedNames)
    return prim

  of nkSuperSend:
    # Rewrite super send arguments
    let superNode = cast[SuperSendNode](node)
    for i in 0..<superNode.arguments.len:
      superNode.arguments[i] = rewriteNodeForSlotAccess(superNode.arguments[i], cls, shadowedNames)
    return superNode

  of nkArray:
    # Rewrite array elements
    let arr = cast[ArrayNode](node)
    for i in 0..<arr.elements.len:
      arr.elements[i] = rewriteNodeForSlotAccess(arr.elements[i], cls, shadowedNames)
    return arr

  of nkTable:
    # Rewrite table entries
    let tbl = cast[TableNode](node)
    for i in 0..<tbl.entries.len:
      let (key, value) = tbl.entries[i]
      tbl.entries[i] = (
        rewriteNodeForSlotAccess(key, cls, shadowedNames),
        rewriteNodeForSlotAccess(value, cls, shadowedNames)
      )
    return tbl

  else:
    # Other node types don't need rewriting (literals, pseudo-vars, etc.)
    return node

proc rewriteMethodForSlotAccess*(blk: BlockNode, cls: Class) =
  ## Rewrite a method's AST to use SlotAccessNodes for slot access
  ## Called when a method is installed on a class via selector:put:
  debug("rewriteMethodForSlotAccess: class=", cls.name, " slots=", $cls.allSlotNames)
  if cls.allSlotNames.len == 0:
    debug("rewriteMethodForSlotAccess: no slots, skipping")
    return  # No slots to optimize

  # Slots are optimized - shadowing is handled by the rewriting logic

  # Build initial shadowed names from method parameters and temporaries
  var shadowedNames: seq[string] = @[]
  for param in blk.parameters:
    shadowedNames.add(param)
  for temp in blk.temporaries:
    shadowedNames.add(temp)
  debug("rewriteMethodForSlotAccess: shadowedNames=", $shadowedNames)

  # Rewrite the method body
  for i in 0..<blk.body.len:
    blk.body[i] = rewriteNodeForSlotAccess(blk.body[i], cls, shadowedNames)
  debug("rewriteMethodForSlotAccess: done")

# Initialize interpreter
proc newInterpreter*(trace: bool = false, maxStackDepth: int = 10000): Interpreter =
  ## Create a new interpreter instance
  result = Interpreter(
    globals: new(Table[string, NodeValue]),
    activationStack: @[],
    currentActivation: nil,
    currentReceiver: nil,
    maxStackDepth: maxStackDepth,
    traceExecution: trace,
    lastResult: nilValue(),
    rootObject: nil
  )

  # Initialize the heap-allocated globals table
  result.globals[] = initTable[string, NodeValue]()

  # Initialize core classes (new model)
  # This sets up: Root -> Object -> (Integer, Float, String, Array, Table, Block, Boolean)
  let objCls = initCoreClasses()
  result.rootClass = objCls
  result.currentReceiver = newInstance(objCls)
  result.rootObject = result.currentReceiver

# Create interpreter with shared globals and rootObject (for green threads)
proc newInterpreterWithShared*(globals: ref Table[string, NodeValue],
                                rootObject: Instance,
                                trace: bool = false,
                                maxStackDepth: int = 10000): Interpreter =
  ## Create a new interpreter that shares globals and rootClass with others
  ## Used for green threads where multiple interpreters share state
  result = Interpreter(
    globals: globals,
    activationStack: @[],
    currentActivation: nil,
    currentReceiver: nil,
    maxStackDepth: maxStackDepth,
    traceExecution: trace,
    lastResult: nilValue(),
    rootObject: rootObject,
    exceptionHandlers: @[],
    schedulerContextPtr: nil
  )

  # Use the shared root class and root object
  result.rootClass = rootObject.class
  result.currentReceiver = rootObject

# Check stack depth to prevent infinite recursion
proc checkStackDepth(interp: var Interpreter) =
  if interp.activationStack.len >= interp.maxStackDepth:
    raise newException(EvalError, "Stack overflow: max depth " & $interp.maxStackDepth)

# Helper to get method name from receiver
proc getMethodName(receiver: Instance, blk: BlockNode): string =
  ## Get a display name for a method
  # Find method name by looking up in receiver's class methods
  if receiver != nil and receiver.class != nil:
    for selector, meth in receiver.class.methods:
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

proc isCapturedEnvInitialized(blk: BlockNode): bool =
  ## Check if capturedEnv is initialized using the explicit flag
  return blk.capturedEnvInitialized

proc lookupVariableWithStatus(interp: Interpreter, name: string): LookupResult =
  ## Look up variable in activation chain, captured environment, and globals
  ## Returns (found: true, value: ...) if found, (found: false, value: nil) if not found
  debug("Looking up variable: ", name)
  var activation = interp.currentActivation

  # First check current activation (for block execution or method locals)
  if activation != nil:
    # Check captured environment FIRST - captured variables from outer lexical scope
    # should take precedence over local temporaries in the current activation
    # This is the key difference: blocks capture variables from where they were defined,
    # not where they're executed
    if activation.currentMethod != nil and activation.currentMethod.capturedEnvInitialized and activation.currentMethod.capturedEnv.len > 0:
      if name in activation.currentMethod.capturedEnv:
        let value = activation.currentMethod.capturedEnv[name].value
        debug("Found variable in captured environment: ", name, " = ", value.toString())
        return (true, value)

    # Then check locals (temporaries defined in this activation)
    if name in activation.locals:
      let val = activation.locals[name]
      let ptrStr = if val.kind == vkInstance and val.instVal != nil: $cast[int](val.instVal) else: "n/a"
      debug("lookupVariable: found ", name, " in locals kind=", $val.kind, " ptr=", ptrStr)
      return (true, val)

    # If this is a block activation and variable not found yet, check globals BEFORE
    # walking up the chain. This prevents blocks from inadvertently capturing variables
    # from the calling method's local scope, which would break lexical scoping.
    if activation.currentMethod != nil and activation.currentMethod.isMethod == false:
      # This is a block - check globals first
      if name in interp.globals[]:
        debug("Found variable in globals (in block): ", name, " = ", interp.globals[][name].toString())
        let val = interp.globals[][name]
        return (true, val)

  # Walk up the activation chain (for nested scopes)
  if activation != nil:
    activation = activation.sender
  while activation != nil:
    # Check captured environment
    if activation.currentMethod != nil and activation.currentMethod.capturedEnvInitialized and activation.currentMethod.capturedEnv.len > 0:
      if name in activation.currentMethod.capturedEnv:
        let value = activation.currentMethod.capturedEnv[name].value
        debug("Found variable in captured environment (parent): ", name, " = ", value.toString())
        return (true, value)

    # Check locals
    if name in activation.locals:
      debug("Found variable in activation (parent): ", name)
      return (true, activation.locals[name])

    activation = activation.sender

  # Check globals
  if name in interp.globals[]:
    debug("Found variable in globals: ", name, " = ", interp.globals[][name].toString())
    let val = interp.globals[][name]
    return (true, val)

  # Check if it's a property on self (legacy Dictionary objects - for backward compatibility)
  if interp.currentReceiver != nil and interp.currentReceiver.kind == ikTable:
    let val = getTableValue(interp.currentReceiver, toValue(name))
    if val.kind != vkNil:
      debug("Found table property on self: ", name)
      return (true, val)

  # Check if it's a slot on self (for ikObject instances with declared instance variables)
  if interp.currentReceiver != nil and interp.currentReceiver.kind == ikObject:
    let idx = getSlotIndex(interp.currentReceiver.class, name)
    if idx >= 0:
      let val = getSlot(interp.currentReceiver, idx)
      if val.kind != vkNil:
        debug("Found slot on self: ", name, " = ", val.toString())
        return (true, val)

  debug("Variable not found: ", name)
  return (false, nilValue())

# Backward-compatible wrapper
proc lookupVariable*(interp: Interpreter, name: string): NodeValue =
  ## Look up variable (returns nilValue if not found)
  lookupVariableWithStatus(interp, name).value

# Variable assignment
proc setVariable*(interp: var Interpreter, name: string, value: NodeValue) =
  ## Set variable in current activation, captured environment, or create global
  echo "DEBUG setVariable: name=", name, " activation=", interp.currentActivation != nil

  # First check if there's a current activation with a captured environment
  # that contains this variable
  if interp.currentActivation != nil:
    # Check if current method has a captured environment with this variable
    # This must be checked BEFORE locals because captured vars are copied to locals
    let currentMethod = interp.currentActivation.currentMethod
    if currentMethod != nil and currentMethod.capturedEnvInitialized:
      if currentMethod.capturedEnv.len > 0 and name in currentMethod.capturedEnv:
        currentMethod.capturedEnv[name].value = value
        # Also update the local copy to keep them in sync
        interp.currentActivation.locals[name] = value
        return

    # Check if variable exists in current activation's locals
    if name in interp.currentActivation.locals:
      echo "DEBUG setVariable: storing ", name, " in locals"
      interp.currentActivation.locals[name] = value
      return

    # Walk up the sender chain to find existing variable in outer scopes
    # This is crucial for closures to update variables defined in enclosing methods
    var parentActivation = interp.currentActivation.sender
    while parentActivation != nil:
      # Check captured environment in parent
      if parentActivation.currentMethod != nil and parentActivation.currentMethod.capturedEnvInitialized:
        if parentActivation.currentMethod.capturedEnv.len > 0 and name in parentActivation.currentMethod.capturedEnv:
          parentActivation.currentMethod.capturedEnv[name].value = value
          parentActivation.locals[name] = value
          debug("Variable updated in parent captured env: ", name, " = ", value.toString())
          return

      # Check locals in parent
      if name in parentActivation.locals:
        parentActivation.locals[name] = value
        debug("Variable updated in parent activation: ", name, " = ", value.toString())
        return

      parentActivation = parentActivation.sender

    # Check if variable exists in globals - if so, update it there
    if name in interp.globals[]:
      # Check for protected global
      if isProtectedGlobal(name):
        raise newException(EvalError, "Cannot reassign protected global: " & name)
      interp.globals[][name] = value
      debug("Global updated: ", name, " = ", value.toString())
      return

    # Check if it's a slot on self (for ikObject instances with declared instance variables)
    if interp.currentReceiver != nil and interp.currentReceiver.kind == ikObject:
      let idx = getSlotIndex(interp.currentReceiver.class, name)
      if idx >= 0:
        setSlot(interp.currentReceiver, idx, value)
        debug("Slot updated on self: ", name, " = ", value.toString())
        return

    # Create in current activation, UNLESS it should be a global (uppercase first letter)
    # This allows uppercase-named variables from stdlib files to be created as globals
    if name.len > 0 and name[0] in {'A'..'Z'}:
      # Check for protected global
      if isProtectedGlobal(name):
        raise newException(EvalError, "Cannot reassign protected global: " & name)
      # If assigning a Class, set its name to the variable name
      if value.kind == vkClass and value.classVal != nil:
        value.classVal.name = name
      interp.globals[][name] = value
      debug("Global set (uppercase variable): ", name, " = ", value.toString())
      return

    # Create in current activation for lowercase variables
    interp.currentActivation.locals[name] = value
    return

  # Set as global
  # Check for protected global
  if isProtectedGlobal(name):
    raise newException(EvalError, "Cannot reassign protected global: " & name)

  # Check capitalization: globals must start with uppercase (except special values)
  if name.len > 0 and name[0] notin {'A'..'Z'}:
    raise newException(EvalError, "Global variables must start with uppercase letter: " & name)

  # If assigning a Class, set its name to the variable name
  if value.kind == vkClass and value.classVal != nil:
    value.classVal.name = name

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
  if not blockNode.capturedEnvInitialized:
    blockNode.capturedEnv = initTable[string, MutableCell]()
    blockNode.capturedEnvInitialized = true

  # First, inherit captured variables from the current method if it's a block
  # This ensures nested closures share the same MutableCells
  if interp.currentActivation != nil and interp.currentActivation.currentMethod != nil:
    let currentMethod = interp.currentActivation.currentMethod
    # Check if capturedEnv is initialized before accessing
    if currentMethod.capturedEnvInitialized and currentMethod.capturedEnv.len > 0:
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

  # The block's homeActivation should indicate the method where the block was lexically defined
  # This is preserved for proper 'self' resolution and non-local return handling
  let blockHome = blockNode.homeActivation

  # Create activation for block execution
  # Use the block's home activation receiver for proper 'self' resolution
  # This ensures that 'self' inside a block refers to the receiver where
  # the block was created (lexical scope), not where it's being invoked
  let blockReceiver = if blockHome != nil and blockHome.receiver != nil:
                        blockHome.receiver
                      else:
                        interp.currentReceiver
  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

  # Keep track of captured variable names so we can save them back
  var capturedVarNames: seq[string] = @[]

  # Bind captured environment variables to the new activation
  # This makes captured variables available in the block's scope
  if isCapturedEnvInitialized(blockNode) and blockNode.capturedEnv.len > 0:
    debug("invokeBlock: capturedEnv has ", blockNode.capturedEnv.len, " entries")
    for name, cell in blockNode.capturedEnv:
      debug("invokeBlock: binding ", name, " kind=", $cell.value.kind)
      activation.locals[name] = cell.value
      capturedVarNames.add(name)

  # Bind parameters to arguments
  for i in 0..<blockNode.parameters.len:
    let paramName = blockNode.parameters[i]
    activation.locals[paramName] = args[i]
    debug("Bound parameter: ", paramName, " = ", args[i].toString())

  # Initialize temporaries to nil
  echo "DEBUG invokeBlock: temporaries.len=", blockNode.temporaries.len
  for tempName in blockNode.temporaries:
    activation.locals[tempName] = nilValue()
    echo "DEBUG invokeBlock: initialized temporary: ", tempName

  # Save current state
  let savedReceiver = interp.currentReceiver

  # Push the activation onto the stack
  interp.pushActivation(activation)

  # Set currentReceiver for proper 'self' resolution in the block
  interp.currentReceiver = blockReceiver

  # Execute block body
  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalOld(stmt)
      if activation.hasReturned:
        # Non-local return - the return value is already set in activation
        blockResult = activation.returnValue.unwrap()
        break
      # Check if process yielded - propagate the exception up
      if interp.shouldYield:
        raise newException(YieldException, "Process yielded from block")
  finally:
    # Save captured variable values back to their cells (for mutable closures)
    # This ensures changes to captured variables persist across invocations
    if blockNode.capturedEnvInitialized and blockNode.capturedEnv.len > 0:
      for name in capturedVarNames:
        if name in activation.locals:
          blockNode.capturedEnv[name].value = activation.locals[name]
          debug("Saved captured variable: ", name, " = ", activation.locals[name].toString())

    # Also update parent activation's locals for variables that came from there
    # This ensures changes to captured variables are visible in the outer scope
    # Walk up the sender chain to find the activation where the variable originated
    if blockNode.capturedEnvInitialized and blockNode.capturedEnv.len > 0:
      var parent = activation.sender
      while parent != nil:
        for name in capturedVarNames:
          if name in activation.locals and name in parent.locals:
            parent.locals[name] = activation.locals[name]
            debug("Updated parent activation variable: ", name, " = ", activation.locals[name].toString())
        parent = parent.sender

    # Pop the activation
    discard interp.popActivation()
    interp.currentReceiver = savedReceiver

  return blockResult.unwrap()

# Method lookup and dispatch
type
  MethodResult* = object
    currentMethod*: BlockNode
    receiver*: Instance         # Instance that received the message
    definingClass*: Class       # class where method was found (for super)
    found*: bool

proc lookupMethod*(interp: Interpreter, receiver: Instance, selector: string): MethodResult =
  ## Look up method in receiver's class using O(1) class lookup
  if receiver == nil or receiver.class == nil:
    debug("Method not found: ", selector, " (receiver or class is nil)")
    return MethodResult(currentMethod: nil, receiver: nil, definingClass: nil, found: false)

  let cls = receiver.class
  debug("Looking up method: '", selector, "' in class: ", cls.name)

  # Fast O(1) lookup in allMethods table (already flattened from parents)
  if selector in cls.allMethods:
    debug("Found method ", selector, " in class ", cls.name)
    return MethodResult(
      currentMethod: cls.allMethods[selector],
      receiver: receiver,
      definingClass: cls,
      found: true
    )

  debug("Method not found: ", selector)
  return MethodResult(currentMethod: nil, receiver: receiver, definingClass: nil, found: false)

proc lookupClassMethod*(cls: Class, selector: string): MethodResult =
  ## Look up class method in class (fast O(1) lookup)
  if cls == nil:
    return MethodResult(currentMethod: nil, receiver: nil, definingClass: nil, found: false)

  if selector in cls.allClassMethods:
    return MethodResult(
      currentMethod: cls.allClassMethods[selector],
      receiver: nil,  # Class methods don't have instance receiver
      definingClass: cls,
      found: true
    )
  return MethodResult(currentMethod: nil, receiver: nil, definingClass: nil, found: false)

# Execute a currentMethod
proc executeMethod(interp: var Interpreter, currentMethod: BlockNode,
                  receiver: Instance, arguments: seq[NodeValue],
                  definingClass: Class = nil,
                  isClassMethod: bool = false): NodeValue =
  ## Execute a currentMethod with given receiver and already-evaluated arguments
  ## definingClass is where the method was found (for super sends)
  ## isClassMethod: true if this is a class method (self returns the class)
  interp.checkStackDepth()

  debug("Executing method with ", arguments.len, " arguments")

  # Check for native implementation first
  if currentMethod.nativeImpl != nil:
    debug("Calling native implementation")
    # Save currentReceiver to restore after native method execution
    let savedReceiver = interp.currentReceiver
    try:
      # Check if this is an interpreter-aware native method (has interp parameter)
      if currentMethod.hasInterpreterParam:
        type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
        let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
        return nativeProc(interp, receiver, arguments)
      else:
        # Standard native method without interpreter
        type NativeProc = proc(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
        let nativeProc = cast[NativeProc](currentMethod.nativeImpl)
        return nativeProc(receiver, arguments)
    finally:
      # Restore currentReceiver after native method
      interp.currentReceiver = savedReceiver

  # Create new activation with definingClass for super sends
  debug("Executing interpreted method with ", currentMethod.parameters.len, " parameters")

  # Update homeActivation for proper non-local returns
  # When a block is stored as a method (via >>), its homeActivation was set at creation time.
  # We need to update it to the current activation so non-local returns work correctly.
  if currentMethod.isMethod:
    currentMethod.homeActivation = interp.currentActivation

  let activation = newActivation(currentMethod, receiver, interp.currentActivation, definingClass, isClassMethod)

  # Bind parameters
  if currentMethod.parameters.len != arguments.len:
    raise newException(EvalError,
      "Wrong number of arguments: expected " & $currentMethod.parameters.len &
      ", got " & $arguments.len)

  for i in 0..<currentMethod.parameters.len:
    let paramName = currentMethod.parameters[i]
    let argValue = arguments[i]
    debug("Binding parameter: ", paramName, " = ", argValue.toString())
    activation.locals[paramName] = argValue

  # Push activation
  debug("Pushing activation, stack depth: ", interp.activationStack.len + 1)
  let savedReceiver = interp.currentReceiver
  interp.activationStack.add(activation)
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  # Execute currentMethod body
  var retVal = nilValue()

  try:
    for i, stmt in currentMethod.body:
      debug("Executing method statement " & $i & " of " & $currentMethod.body.len & ", hasReturned: " & $activation.hasReturned)
      # Check if we've already returned from a non-local return in a nested block
      if activation.hasReturned:
        debug("Already marked as returned, breaking before statement")
        break
      retVal = interp.evalOld(stmt)
      debug("After evaluating statement " & $i & ", hasReturned: " & $activation.hasReturned & ", retVal: " & retVal.toString())
      if activation.hasReturned:
        debug("Breaking out of loop due to return")
        break
  finally:
    # Pop activation
    discard interp.activationStack.pop()
    debug("Popping activation, stack depth: ", interp.activationStack.len)
    if interp.activationStack.len > 0:
      interp.currentActivation = interp.activationStack[^1]
      interp.currentReceiver = interp.currentActivation.receiver
    else:
      interp.currentActivation = nil
      interp.currentReceiver = savedReceiver

  debug("Method execution complete, hasReturned: ", activation.hasReturned)
  # Return result (or activation.returnValue if non-local return)
  # Unwrap primitive types (ikInt, ikFloat, ikString) from Instance wrappers
  if activation.hasReturned:
    debug("Returning from method (non-local), returnValue: ", activation.returnValue.toString())
    return activation.returnValue.unwrap()
  else:
    debug("Returning from method: ", retVal.toString())
    return retVal.unwrap()

# Evaluation functions
proc evalOld*(interp: var Interpreter, node: Node): NodeValue =
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
    let identResult = lookupVariable(interp, ident.name)
    if identResult.kind == vkInstance:
      if identResult.instVal == nil:
        debug("Variable ", ident.name, " has nil instVal!")
      else:
        let className = if identResult.instVal.class == nil: "nil" else: identResult.instVal.class.name
        debug("Variable ", ident.name, " ptr=", cast[int](identResult.instVal), " kind=", $identResult.instVal.kind, " class=", className)
    return identResult

  of nkPseudoVar:
    # Pseudo-variable (self, nil, true, false)
    let pseudo = cast[PseudoVarNode](node)
    debug("Pseudo-variable: ", pseudo.name)
    case pseudo.name
    of "self":
      if interp.currentReceiver == nil:
        debug("currentReceiver is nil, returning nil")
        return nilValue()
      debug("currentReceiver class: ", interp.currentReceiver.class.name, " kind: ", interp.currentReceiver.kind)
      # For class methods, self should return the Class object
      # We track this via activation.isClassMethod rather than structural checks
      if interp.currentActivation != nil and interp.currentActivation.isClassMethod:
        debug("self returning as class: <class ", interp.currentReceiver.class.name, ">")
        return interp.currentReceiver.class.toValue()
      return interp.currentReceiver.toValue().unwrap()
    of "nil":
      return nilValue()
    of "true":
      return trueValue
    of "false":
      return falseValue
    of "super":
      # Bare super without message - return current receiver (same as self)
      if interp.currentReceiver != nil:
        return interp.currentReceiver.toValue().unwrap()
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
      isMethod: origBlock.isMethod,
      capturedEnv: initTable[string, MutableCell](),
      capturedEnvInitialized: true,
      homeActivation: nil
    )
    captureEnvironment(interp, blockNode)
    return NodeValue(kind: vkBlock, blockVal: blockNode)

  of nkAssign:
    # Variable assignment
    let assign = node.AssignNode
    debug("Variable assignment: ", assign.variable)
    let value = interp.evalOld(assign.expression)
    if value.kind == vkInstance:
      if value.instVal == nil:
        debug("assign: ", assign.variable, " got nil instVal!")
      else:
        let className = if value.instVal.class == nil: "nil" else: value.instVal.class.name
        debug("assign: ", assign.variable, " ptr=", cast[int](value.instVal), " class=", className)
    setVariable(interp, assign.variable, value)
    return value

  of nkReturn:
    # Non-local return
    debug("Non-local return")
    let ret = node.ReturnNode
    var value = nilValue()
    if ret.expression != nil:
      value = interp.evalOld(ret.expression).unwrap()
      debug("Non-local return value: ", value.toString())
    else:
      value = interp.currentReceiver.toValue().unwrap()
      debug("Non-local return self: ", value.toString())

    # Determine the target activation for return
    # If we're inside a block, use the block's home activation (non-local return)
    # If we're in a method, return from that method (local return)
    var targetActivation: Activation = nil

    if interp.currentActivation != nil and interp.currentActivation.currentMethod != nil:
      let currentMethod = interp.currentActivation.currentMethod
      debug("Return check: isMethod=", currentMethod.isMethod, " homeActivation nil?=", currentMethod.homeActivation == nil)
      if not currentMethod.isMethod and currentMethod.homeActivation != nil:
        # We're in a block (not a method) - return from the block's home activation
        # Keep going up the chain until we find a method (not another block)
        targetActivation = currentMethod.homeActivation
        var safetyCount = 0
        while targetActivation != nil and targetActivation.currentMethod != nil and
              not targetActivation.currentMethod.isMethod and
              targetActivation.currentMethod.homeActivation != nil:
          inc safetyCount
          if safetyCount > 1000:
            raise newException(EvalError, "Non-local return exceeded 1000 nested blocks - possible infinite loop")
          targetActivation = targetActivation.currentMethod.homeActivation
          debug("Following nested block home activation")
        debug("Non-local return from block to method activation")
      else:
        # We're in a method - local return from current method
        targetActivation = interp.currentActivation
        debug("Local return from method")

    if targetActivation != nil:
      # Unwrap primitive values before storing
      let unwrapped = value.unwrap()
      targetActivation.returnValue = unwrapped
      targetActivation.hasReturned = true

      # Check if this is a non-local return (target is different from current)
      let isNonLocal = targetActivation != interp.currentActivation

      # Propagate hasReturned flag to all activations from current up to target
      var current = interp.currentActivation
      var safetyCount = 0
      # First check if target is still on the stack
      var targetOnStack = false
      var checkAct = current
      while checkAct != nil:
        if checkAct == targetActivation:
          targetOnStack = true
          break
        checkAct = checkAct.sender
      # If target not on stack (orphaned block), use current activation as target
      if not targetOnStack:
        debug("Target activation not on stack - orphaned block, using current")
        targetActivation = interp.currentActivation
      while current != nil and current != targetActivation:
        inc safetyCount
        if safetyCount > 1000:
          raise newException(EvalError, "Return propagation exceeded 1000 activations - possible infinite loop")
        current.hasReturned = true
        if isNonLocal:
          current.nonLocalReturnTarget = targetActivation
        # Note: We intentionally do NOT set returnValue on intermediate activations.
        # Only the target activation should have the return value set.
        current = current.sender

      debug("Set return on target activation")

    return value.unwrap()

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
            elements.add(interp.currentReceiver.toValue().unwrap())
          else:
            elements.add(interp.globals[]["Object"])
        of "super":
          # super refers to parent of current receiver's class
          if interp.currentReceiver != nil and interp.currentReceiver.class != nil and
             interp.currentReceiver.class.superclasses.len > 0:
            elements.add(interp.currentReceiver.class.superclasses[0].toValue())
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
            elements.add(interp.currentReceiver.toValue().unwrap())
          else:
            elements.add(interp.globals[]["Object"])
        of "super":
          # super refers to parent of current receiver's class
          if interp.currentReceiver != nil and interp.currentReceiver.class != nil and
             interp.currentReceiver.class.superclasses.len > 0:
            elements.add(interp.currentReceiver.class.superclasses[0].toValue())
          else:
            elements.add(interp.globals[]["Object"])
        continue
      # Normal evaluation for other elements
      elements.add(interp.evalOld(elem))
    debug("Array result: ", elements.len, " elements")
    # Return array as Instance (ikArray variant)
    if arrayClass == nil:
      raise newException(EvalError, "Array class not initialized")
    return newArrayInstance(arrayClass, elements).toValue()

  of nkTable:
    # Table literal - evaluate each key-value pair
    let tab = node.TableNode
    var table = initTable[NodeValue, NodeValue]()
    for entry in tab.entries:
      # Keys can be any NodeValue (int, string, symbol, instance, etc.)
      let keyVal = interp.evalOld(entry.key)
      let valueVal = interp.evalOld(entry.value)
      table[keyVal] = valueVal
    # Return table as Instance (ikTable variant)
    if tableClass == nil:
      raise newException(EvalError, "Table class not initialized")
    return newTableInstance(tableClass, table).toValue()

  of nkObjectLiteral:
    # Object literal - create new object with properties
    let objLit = node.ObjectLiteralNode
    # Create new object derived from root object
    # Create a Table instance instead of Dictionary object
    # Property names are strings, convert to NodeValue for table keys
    var entries = initTable[NodeValue, NodeValue]()
    for prop in objLit.properties:
      let valueVal = interp.evalOld(prop.value)
      entries[toValue(prop.name)] = valueVal
    return toValue(newTableInstance(tableClass, entries))

  of nkPrimitive:
    # Primitive declaration - ignore Nim code, evaluate fallback Smalltalk
    let prim = node.PrimitiveNode
    var fallbackResult = nilValue()
    # Evaluate fallback statements sequentially
    for stmt in prim.fallback:
      fallbackResult = interp.evalOld(stmt)
    return fallbackResult

  of nkPrimitiveCall:
    # Inline primitive call - dispatch via standard method lookup
    let primCall = node.PrimitiveCallNode
    let receiver = interp.currentReceiver

    # Evaluate arguments
    var argValues: seq[NodeValue] = @[]
    for argNode in primCall.arguments:
      argValues.add(interp.evalOld(argNode))

    # Look up the method - primitives are registered as standard methods
    let lookup = lookupMethod(interp, receiver, primCall.selector)
    if lookup.found:
      return executeMethod(interp, lookup.currentMethod, receiver, argValues, lookup.definingClass)
    else:
      raise newException(EvalError,
        "Primitive not found: #" & primCall.selector)

  of nkCascade:
    # Cascade message - send multiple messages to same receiver
    return interp.evalCascade(node.CascadeNode)

  of nkSlotAccess:
    # Slot access - O(1) direct instance variable access by index
    let slotNode = cast[SlotAccessNode](node)
    if interp.currentReceiver != nil:
      # Check if receiver is an ikObject instance (new class-based model)
      if interp.currentReceiver.kind == ikObject:
        let inst = interp.currentReceiver
        if slotNode.slotIndex >= 0 and slotNode.slotIndex < inst.slots.len:
          if slotNode.isAssignment:
            # Assignment: evaluate valueExpr and store in slot
            if slotNode.valueExpr != nil:
              let newValue = interp.evalOld(slotNode.valueExpr)
              inst.slots[slotNode.slotIndex] = newValue
              return newValue
            # Legacy: get value from activation's locals (for generated setter methods)
            elif interp.currentActivation != nil and interp.currentActivation.locals.hasKey("newValue"):
              let newValue = interp.currentActivation.locals["newValue"]
              inst.slots[slotNode.slotIndex] = newValue
              return newValue
            return nilValue()
          else:
            # Getter: return slot value
            return inst.slots[slotNode.slotIndex]
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
                      interp.evalOld(msgNode.receiver)
                    else:
                      if interp.currentReceiver == nil:
                        nilValue()
                      else:
                        interp.currentReceiver.toValue().unwrap()

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
        argValues.add(interp.evalOld(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    of "value:value:":
      # Two arguments
      var argValues: seq[NodeValue] = @[]
      for argNode in msgNode.arguments:
        argValues.add(interp.evalOld(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    of "value:value:value:":
      # Three arguments
      var argValues: seq[NodeValue] = @[]
      for argNode in msgNode.arguments:
        argValues.add(interp.evalOld(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    of "value:value:value:value:":
      # Four arguments
      var argValues: seq[NodeValue] = @[]
      for argNode in msgNode.arguments:
        argValues.add(interp.evalOld(argNode))
      return invokeBlock(interp, receiverVal.blockVal, argValues)
    else:
      # Non-value: message sent to block - continue with normal dispatch
      discard

  debug("Message receiver: ", receiverVal.toString())

  # Handle class method lookup (messages sent to Class objects)
  if receiverVal.kind == vkClass:
    let cls = receiverVal.classVal

    # Evaluate arguments
    var arguments = newSeq[NodeValue]()
    for argNode in msgNode.arguments:
      arguments.add(interp.evalOld(argNode))

    debug("Looking up class method: ", msgNode.selector, " on class: ", cls.name)

    # Handle selector:put: - add instance method to class (for >> syntax)
    if msgNode.selector == "selector:put:":
      if arguments.len >= 2 and arguments[0].kind == vkSymbol and arguments[1].kind == vkBlock:
        let methodName = arguments[0].symVal
        let methodBlock = arguments[1].blockVal
        methodBlock.isMethod = true
        # Rewrite method AST to use SlotAccessNodes for O(1) slot access
        rewriteMethodForSlotAccess(methodBlock, cls)
        cls.methods[methodName] = methodBlock
        # Rebuild all allMethods tables to ensure inheritance works correctly
        rebuildAllDescendants(cls)
        debug("Added instance method: ", methodName, " to class: ", cls.name)
        return cls.toValue()
      else:
        raise newException(EvalError, "selector:put: expects symbol and block arguments")

    # Handle classSelector:put: - add class method to class (for class>> syntax)
    if msgNode.selector == "classSelector:put:":
      if arguments.len >= 2 and arguments[0].kind == vkSymbol and arguments[1].kind == vkBlock:
        let methodName = arguments[0].symVal
        let methodBlock = arguments[1].blockVal
        methodBlock.isMethod = true
        cls.classMethods[methodName] = methodBlock
        cls.allClassMethods[methodName] = methodBlock
        # Rebuild all allClassMethods tables to ensure inheritance works correctly
        for subclass in cls.subclasses:
          subclass.allClassMethods[methodName] = methodBlock
        debug("Added class method: ", methodName, " to class: ", cls.name)
        return cls.toValue()
      else:
        raise newException(EvalError, "classSelector:put: expects symbol and block arguments")

    # Look up class method
    let lookup = lookupClassMethod(cls, msgNode.selector)

    if lookup.found:
      # Found class method - execute it
      let currentMethodNode = lookup.currentMethod
      debug("Found class method, executing")

      # Handle native class methods without interpreter param specially
      # They expect Class directly, not Instance (used by initCoreClasses)
      if currentMethodNode.nativeImpl != nil and not currentMethodNode.hasInterpreterParam:
        debug("Calling native class method implementation (direct)")
        var argValues = newSeq[NodeValue]()
        for argNode in msgNode.arguments:
          argValues.add(interp.evalOld(argNode))

        type ClassMethodProc = proc(self: Class, args: seq[NodeValue]): NodeValue {.nimcall.}
        let nativeProc = cast[ClassMethodProc](currentMethodNode.nativeImpl)
        return nativeProc(cls, argValues)

      # For class methods, pass the class wrapped in a minimal Instance as receiver
      # This allows native methods to know which class they were called on
      let classReceiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)
      return interp.executeMethod(currentMethodNode, classReceiver, arguments, lookup.definingClass, isClassMethod = true)
    else:
      # Class method not found - fall through to instance method lookup
      # by changing receiverVal from vkClass to create an instance wrapper
      # We do this below in the vkClass case of the conversion section
      discard

  # Convert receiver to Instance - create Instance variants directly
  var receiver: Instance
  case receiverVal.kind
  of vkInstance:
    receiver = receiverVal.instVal
  of vkInt:
    if integerClass == nil:
      raise newException(EvalError, "Integer class not initialized")
    receiver = newIntInstance(integerClass, receiverVal.intVal)
  of vkFloat:
    if floatClass == nil:
      raise newException(EvalError, "Float class not initialized")
    receiver = newFloatInstance(floatClass, receiverVal.floatVal)
  of vkString:
    if stringClass == nil:
      raise newException(EvalError, "String class not initialized")
    receiver = newStringInstance(stringClass, receiverVal.strVal)
  of vkArray:
    if arrayClass == nil:
      raise newException(EvalError, "Array class not initialized")
    receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
  of vkTable:
    if tableClass == nil:
      raise newException(EvalError, "Table class not initialized")
    receiver = newTableInstance(tableClass, receiverVal.tableVal)
  of vkBool:
    # Boolean - create ikObject instance with nimValue
    # Use True or False class based on value
    let p = cast[pointer](alloc(sizeof(bool)))
    cast[ptr bool](p)[] = receiverVal.boolVal
    var boolInst: Instance
    new(boolInst)
    boolInst.kind = ikObject
    boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
    boolInst.slots = @[]
    boolInst.isNimProxy = true
    boolInst.nimValue = p
    receiver = boolInst
  of vkBlock:
    # Blocks - store in ikObject instance
    var blockInst: Instance
    new(blockInst)
    blockInst.kind = ikObject
    blockInst.class = blockClass
    blockInst.slots = @[]
    blockInst.isNimProxy = false
    # Store block reference in nimValue temporarily
    blockInst.nimValue = cast[pointer](receiverVal.blockVal)
    receiver = blockInst
  of vkNil:
    raise newException(EvalError, "Cannot send message to nil")
  of vkClass:
    # Class object - convert to instance wrapper for instance method lookup
    # This happens when a class method is not found but an instance method exists
    # (e.g., calling extend: on a Class object)
    let cls = receiverVal.classVal
    debug("Converting class to instance wrapper for instance method lookup")
    receiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)
  else:
    raise newException(EvalError, "Message send to unsupported value kind: " & $receiverVal.kind)

  # Evaluate arguments
  var arguments = newSeq[NodeValue]()
  for argNode in msgNode.arguments:
    arguments.add(interp.evalOld(argNode))

  debug("Looking up method: ", msgNode.selector)

  # Look up currentMethod using new class-based lookup
  let lookup = lookupMethod(interp, receiver, msgNode.selector)

  if lookup.found:
    # Found currentMethod - execute it
    let currentMethodNode = lookup.currentMethod
    debug("Found method, executing")

    return interp.executeMethod(currentMethodNode, receiver, arguments, lookup.definingClass)
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
      return interp.executeMethod(dnuLookup.currentMethod, receiver, dnuArgs, dnuLookup.definingClass)
    else:
      raise newException(EvalError,
        "Message not understood: " & msgNode.selector & " on " & receiver.class.name)

# Evaluate a super send
proc evalSuperSend(interp: var Interpreter, superNode: SuperSendNode): NodeValue =
  ## Evaluate super send - lookup method in parent class
  ## Unqualified super: lookup in parents[0] of the DEFINING class (not receiver's class)
  ## Qualified super<Parent>: lookup in specific parent

  if interp.currentReceiver == nil:
    raise newException(EvalError, "super send with no current receiver")

  # Get the defining class from the current activation
  # This is the class where the currently-executing method was defined
  var definingClass: Class = nil
  if interp.currentActivation != nil and interp.currentActivation.definingObject != nil:
    definingClass = interp.currentActivation.definingObject
  else:
    # Fallback to receiver's class if no defining class (first super send)
    definingClass = interp.currentReceiver.class

  if definingClass == nil:
    raise newException(EvalError, "super send with no defining class")

  # Determine which parent to look in
  var targetParent: Class = nil
  if superNode.explicitParent.len > 0:
    # Qualified super<Parent>: find specific parent by name
    for parent in definingClass.superclasses:
      if parent.name == superNode.explicitParent:
        targetParent = parent
        break
    if targetParent == nil:
      raise newException(EvalError, "Parent class '" & superNode.explicitParent & "' not found in inheritance chain")
  else:
    # Unqualified super: use first parent of the defining class
    if definingClass.superclasses.len == 0:
      raise newException(EvalError, "super send in class with no parents")
    targetParent = definingClass.superclasses[0]

  # Look up method in target parent's allMethods
  let methodBlock = lookupInstanceMethod(targetParent, superNode.selector)
  if methodBlock == nil:
    raise newException(EvalError, "Method '" & superNode.selector & "' not found in super class " & targetParent.name)

  # Evaluate arguments
  var arguments = newSeq[NodeValue]()
  for argNode in superNode.arguments:
    arguments.add(interp.evalOld(argNode))

  # Execute the method with current receiver, passing targetParent as the defining class
  # This is crucial: the defining class for the super method execution is targetParent
  return interp.executeMethod(methodBlock, interp.currentReceiver, arguments, targetParent)

# Evaluate a cascade of messages
proc evalCascade(interp: var Interpreter, cascadeNode: CascadeNode): NodeValue =
  ## Evaluate cascade messages - all sent to same receiver
  ## Return the result of the last message

  # Evaluate receiver once
  let receiverVal = interp.evalOld(cascadeNode.receiver)
  var cascadeResult = receiverVal

  # Convert receiver to Instance - same logic as evalMessage
  var receiver: Instance
  case receiverVal.kind
  of vkInstance:
    receiver = receiverVal.instVal
  of vkInt:
    if integerClass == nil:
      raise newException(EvalError, "Integer class not initialized")
    receiver = newIntInstance(integerClass, receiverVal.intVal)
  of vkFloat:
    if floatClass == nil:
      raise newException(EvalError, "Float class not initialized")
    receiver = newFloatInstance(floatClass, receiverVal.floatVal)
  of vkString:
    if stringClass == nil:
      raise newException(EvalError, "String class not initialized")
    receiver = newStringInstance(stringClass, receiverVal.strVal)
  of vkArray:
    if arrayClass == nil:
      raise newException(EvalError, "Array class not initialized")
    receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
  of vkTable:
    if tableClass == nil:
      raise newException(EvalError, "Table class not initialized")
    receiver = newTableInstance(tableClass, receiverVal.tableVal)
  of vkBool:
    # Boolean - create ikObject instance with nimValue
    # Use True or False class based on value
    let p = cast[pointer](alloc(sizeof(bool)))
    cast[ptr bool](p)[] = receiverVal.boolVal
    var boolInst: Instance
    new(boolInst)
    boolInst.kind = ikObject
    boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
    boolInst.slots = @[]
    boolInst.isNimProxy = true
    boolInst.nimValue = p
    receiver = boolInst
  of vkBlock:
    var blockInst: Instance
    new(blockInst)
    blockInst.kind = ikObject
    blockInst.class = blockClass
    blockInst.slots = @[]
    blockInst.isNimProxy = false
    blockInst.nimValue = cast[pointer](receiverVal.blockVal)
    receiver = blockInst
  of vkClass:
    # Class - create a proxy instance for the class
    var classInst: Instance
    new(classInst)
    classInst.kind = ikObject
    classInst.class = receiverVal.classVal
    classInst.slots = @[]
    classInst.isNimProxy = false
    classInst.nimValue = cast[pointer](receiverVal.classVal)
    receiver = classInst
  else:
    raise newException(EvalError, "Cascade to unsupported value kind: " & $receiverVal.kind)

  # Save original receiver
  let savedReceiver = interp.currentReceiver

  # Send each message to the receiver
  for msgNode in cascadeNode.messages:
    # Update current receiver for this message
    interp.currentReceiver = receiver

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
proc sendMessage*(interp: var Interpreter, receiver: Instance,
                 selector: string, args: varargs[NodeValue]): NodeValue =
  ## Direct message send for internal use
  # Look up method in receiver's class (O(1) lookup)
  let lookup = lookupMethod(interp, receiver, selector)
  if lookup.found:
    return interp.executeMethod(lookup.currentMethod, receiver, @args, lookup.definingClass)
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
      lastResult = interp.evalOld(node)
    interp.lastResult = lastResult
    return (lastResult, "")
  except ValueError:
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
    # Create a top-level activation context so variables can be locals instead of globals
    # This allows lowercase variable names without enforcing uppercase rule for globals
    if nodes.len > 0:
      # Create a temporary block node to wrap the statements
      let topLevelBlock = BlockNode(
        parameters: @[],
        temporaries: @[],
        body: nodes,
        isMethod: false,
        nativeImpl: nil,
        hasInterpreterParam: false,
        capturedEnv: initTable[string, MutableCell](),
        capturedEnvInitialized: false,
        homeActivation: nil
      )
      # Create activation with nil instance as receiver for top-level code
      let activation = newActivation(topLevelBlock, nilInstance, nil)
      interp.pushActivation(activation)
      let savedActivation = interp.currentActivation
      let savedReceiver = interp.currentReceiver
      interp.currentActivation = activation
      interp.currentReceiver = nilInstance

      try:
        for i, node in nodes:
          debug("evalStatements: evaluating node ", i, " of ", nodes.len)
          let evalResult = interp.evalOld(node)
          results.add(evalResult)
      finally:
        discard interp.popActivation()
        interp.currentActivation = savedActivation
        interp.currentReceiver = savedReceiver

    debug("evalStatements: done, returning ", results.len, " results")
    return (results, "")
  except EvalError as e:
    return (@[], "Runtime error: " & e.msg)
  except Exception as e:
    return (@[], "Error: " & e.msg)

# Block evaluation helper
proc evalBlock*(interp: var Interpreter, receiver: Instance, blockNode: BlockNode): NodeValue =
  ## Evaluate a block in the context of the given receiver
  ## Creates a proper activation to allow access to outer scope

  # Use the block's home activation receiver for proper 'self' resolution
  # This ensures that 'self' inside a block refers to the receiver where
  # the block was created, not the caller-provided receiver
  let blockReceiver = if blockNode.homeActivation != nil and
                        blockNode.homeActivation.receiver != nil:
                        blockNode.homeActivation.receiver
                      else:
                        receiver

  # Create activation for the block
  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

  # Push the activation onto the stack
  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = blockReceiver

  # Execute each statement in the block body
  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalOld(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue.unwrap()
        break
  finally:
    # Pop the activation
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult.unwrap().unwrap()

proc evalBlockWithArg(interp: var Interpreter, receiver: Instance, blockNode: BlockNode, arg: NodeValue): NodeValue =
  ## Evaluate a block with one argument
  # Use the block's home activation receiver for proper 'self' resolution
  let blockReceiver = if blockNode.homeActivation != nil and
                        blockNode.homeActivation.receiver != nil:
                        blockNode.homeActivation.receiver
                      else:
                        receiver
  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

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
      blockResult = interp.evalOld(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue.unwrap()
        break
  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult

proc evalBlockWithTwoArgs(interp: var Interpreter, receiver: Instance, blockNode: BlockNode, arg1, arg2: NodeValue): (NodeValue, bool) =
  ## Evaluate a block with two arguments
  ## Returns (value, true) if a non-local return occurred, (value, false) otherwise
  let blockReceiver = if blockNode.homeActivation != nil and
                        blockNode.homeActivation.receiver != nil:
                        blockNode.homeActivation.receiver
                      else:
                        receiver
  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

  if blockNode.parameters.len > 0:
    activation.locals[blockNode.parameters[0]] = arg1
  if blockNode.parameters.len > 1:
    activation.locals[blockNode.parameters[1]] = arg2

  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  var blockResult = nilValue()
  var nonLocalReturn = false
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalOld(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue.unwrap()
        nonLocalReturn = true
        break
  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return (blockResult, nonLocalReturn)

proc evalBlockWithThreeArgs(interp: var Interpreter, receiver: Instance, blockNode: BlockNode, arg1, arg2, arg3: NodeValue): NodeValue =
  ## Evaluate a block with three arguments
  let blockReceiver = if blockNode.homeActivation != nil and
                        blockNode.homeActivation.receiver != nil:
                        blockNode.homeActivation.receiver
                      else:
                        receiver
  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

  if blockNode.parameters.len > 0:
    activation.locals[blockNode.parameters[0]] = arg1
  if blockNode.parameters.len > 1:
    activation.locals[blockNode.parameters[1]] = arg2
  if blockNode.parameters.len > 2:
    activation.locals[blockNode.parameters[2]] = arg3

  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalOld(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue.unwrap()
        break
  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult

# perform:with: implementation (interpreter-aware)
proc performWithImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Send a message to self with arguments: self perform: #selector with: arg
  if args.len < 1:
    return nilValue()

  # Get the selector from first argument
  var selector: string
  if args[0].kind == vkSymbol:
    selector = args[0].symVal
  elif args[0].kind == vkString:
    selector = args[0].strVal
  else:
    return nilValue()

  # Look up the method
  let methodResult = lookupMethod(interp, self, selector)
  if not methodResult.found:
    return nilValue()

  # Prepare arguments (skip the selector, take remaining args)
  var messageArgs: seq[NodeValue] = @[]
  if args.len >= 2 and args[1].kind != vkNil:
    messageArgs.add(args[1])
  if args.len >= 3 and args[2].kind != vkNil:
    messageArgs.add(args[2])

  # Execute the method
  return executeMethod(interp, methodResult.currentMethod, self, messageArgs, methodResult.definingClass)

# Conditional method implementations (need to be defined before initGlobals)
proc ifTrueImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Execute block if receiver is true: true ifTrue: [code]
  debug("ifTrueImpl called, self.kind: ", self.kind, " self.isNimProxy: ", self.isNimProxy)
  if args.len < 1 or args[0].kind != vkBlock:
    debug("ifTrueImpl: no valid args")
    return nilValue()

  # Check if this is a true boolean (nimProxy indicates wrapped primitive)
  if self.isNimProxy and self.kind == ikObject:
    let boolVal = cast[ptr bool](self.nimValue)[]
    if boolVal:
      # Execute the block with proper context
      # Use the block's home activation's receiver for correct self resolution
      let blockNode = args[0].blockVal

      # Get caller's activation to detect non-local returns
      let callerActivation = if interp.activationStack.len > 0:
                               interp.activationStack[interp.activationStack.len - 1]
                             else:
                               nil

      let blockReceiver = if blockNode.homeActivation != nil and
                            blockNode.homeActivation.receiver != nil:
                            blockNode.homeActivation.receiver
                          else:
                            interp.currentReceiver
      let blockResult = evalBlock(interp, blockReceiver, blockNode)

      # Check if a non-local return was triggered (nonLocalReturnTarget set)
      if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
        return callerActivation.returnValue

      return blockResult
  return nilValue()

proc ifFalseImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Execute block if receiver is false: false ifFalse: [code]
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Check if this is a boolean (nimProxy indicates wrapped primitive)
  if self.isNimProxy and self.kind == ikObject:
    let boolVal = cast[ptr bool](self.nimValue)[]
    if not boolVal:
      # Execute the block with proper context
      # Use the block's home activation's receiver for correct self resolution
      let blockNode = args[0].blockVal

      # Get caller's activation to detect non-local returns
      let callerActivation = if interp.activationStack.len > 0:
                               interp.activationStack[interp.activationStack.len - 1]
                             else:
                               nil

      let blockReceiver = if blockNode.homeActivation != nil and
                            blockNode.homeActivation.receiver != nil:
                            blockNode.homeActivation.receiver
                          else:
                            interp.currentReceiver
      let blockResult = evalBlock(interp, blockReceiver, blockNode)

      # Check if a non-local return was triggered (nonLocalReturnTarget set)
      if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
        return callerActivation.returnValue

      return blockResult
  return nilValue()

# Loop method implementations (interpreter-aware)
proc whileTrueImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Execute bodyBlock while conditionBlock evaluates to true: [cond] whileTrue: [body]
  ## self is the condition block (receiver), args[0] is the body block
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Extract condition block node from self
  var conditionBlock: BlockNode = nil
  if self.kind == ikObject and self.class == blockClass and not self.isNimProxy:
    # New class-based model - block stored in nimValue
    conditionBlock = cast[BlockNode](self.nimValue)

  if conditionBlock == nil:
    return nilValue()

  let bodyBlock = args[0].blockVal
  var lastResult = nilValue()

  # Get the caller's activation to detect non-local returns
  let callerActivation = if interp.activationStack.len > 0:
                           interp.activationStack[interp.activationStack.len - 1]
                         else:
                           nil
  debug("whileTrueImpl: callerActivation nil? ", callerActivation == nil)

  # Loop while condition is true
  while true:
    # Evaluate condition block
    let conditionResult = evalBlock(interp, interp.currentReceiver, conditionBlock)

    # Check if a non-local return was triggered (nonLocalReturnTarget set)
    if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
      debug("whileTrueImpl: detected non-local return after condition")
      return callerActivation.returnValue

    # Check if condition is true
    var conditionIsTrue = false
    if conditionResult.kind == vkBool:
      conditionIsTrue = conditionResult.boolVal
    else:
      # Non-boolean condition - treat as false to exit loop
      break

    if not conditionIsTrue:
      break

    # Execute body block
    lastResult = evalBlock(interp, interp.currentReceiver, bodyBlock)

    # Check if a non-local return was triggered after body execution
    if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
      debug("whileTrueImpl: detected non-local return after body")
      return callerActivation.returnValue

  debug("whileTrueImpl: normal return, lastResult = ", lastResult.toString())
  return lastResult

proc whileFalseImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Execute bodyBlock while conditionBlock evaluates to false: [cond] whileFalse: [body]
  ## self is the condition block (receiver), args[0] is the body block
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Extract condition block node from self
  var conditionBlock: BlockNode = nil
  if self.kind == ikObject and self.class == blockClass and not self.isNimProxy:
    # New class-based model - block stored in nimValue
    conditionBlock = cast[BlockNode](self.nimValue)

  if conditionBlock == nil:
    return nilValue()

  let bodyBlock = args[0].blockVal
  var lastResult = nilValue()

  # Get the caller's activation to detect non-local returns
  let callerActivation = if interp.activationStack.len > 0:
                           interp.activationStack[interp.activationStack.len - 1]
                         else:
                           nil

  # Loop while condition is false
  while true:
    # Evaluate condition block
    let conditionResult = evalBlock(interp, interp.currentReceiver, conditionBlock)

    # Check if a non-local return was triggered (nonLocalReturnTarget set)
    if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
      return callerActivation.returnValue

    # Check if condition is false
    var conditionIsTrue = false
    if conditionResult.kind == vkBool:
      conditionIsTrue = conditionResult.boolVal
    else:
      # Non-boolean condition - treat as true to exit loop
      break

    if conditionIsTrue:
      break

    # Execute body block
    lastResult = evalBlock(interp, interp.currentReceiver, bodyBlock)

    # Check if a non-local return was triggered after body execution
    if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
      return callerActivation.returnValue

  return lastResult

# Object primitive methods

proc primitiveAsSelfDoImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Evaluate a block with self temporarily rebound to this object
  ## Usage: self perform: #primitiveAsSelfDo: with: block
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  let blockNode = args[0].blockVal
  debug("primitiveAsSelfDo called, evaluating block with self = ", self.class.name)

  # Save current receiver
  let savedReceiver = interp.currentReceiver

  # Temporarily set receiver to self
  interp.currentReceiver = self

  try:
    # Evaluate the block with new self
    return evalBlock(interp, self, blockNode)
  finally:
    # Restore original receiver
    interp.currentReceiver = savedReceiver

proc primitiveHasPropertyImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Check if object has a slots property (not inherited)
  if args.len < 1:
    return falseValue
  let key = if args[0].kind == vkString: args[0].strVal
            elif args[0].kind == vkSymbol: args[0].symVal
            else: ""
  if key.len == 0 or self.kind != ikObject or self.class == nil:
    return falseValue
  let slotIdx = self.class.slotNames.find(key)
  toValue(slotIdx >= 0 and slotIdx < self.slots.len)

proc primitivePropertiesImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return slot names as an array
  var slotNames: seq[NodeValue] = @[]
  if self.kind == ikObject and self.class != nil:
    for name in self.class.slotNames:
      slotNames.add(toSymbol(name))
  return newArrayInstance(arrayClass, slotNames).toValue()

proc primitiveRespondsToImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Check if the class responds to a message
  if args.len < 1:
    return falseValue
  let selector = if args[0].kind == vkString: args[0].strVal
                  elif args[0].kind == vkSymbol: args[0].symVal
                  else: ""
  if selector.len == 0:
    return falseValue
  let lookup = lookupMethod(interp, self, selector)
  toValue(lookup.found)

proc primitiveMethodsImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return the class's method selector names as an array
  var selectors: seq[NodeValue] = @[]
  if self.kind == ikObject and self.class != nil:
    for selector in self.class.allMethods.keys():
      selectors.add(toSymbol(selector))
  return newArrayInstance(arrayClass, selectors).toValue()

proc primitiveErrorImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Raise an exception with the given message
  let msg = if args.len > 0: args[0].toString()
            else: "Error"
  raise newException(EvalError, msg)

proc primitiveIsKindOfImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Check if object is an instance of the given class or any superclass
  if args.len < 1 or args[0].kind != vkClass:
    return falseValue
  let targetClass = args[0].classVal
  var currentClass: Class = self.class
  while currentClass != nil:
    if currentClass == targetClass:
      return trueValue
    if currentClass.superclasses.len > 0:
      currentClass = currentClass.superclasses[0]
    else:
      break
  falseValue

proc primitiveEqualsImpl(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Identity/value equality for Object
  ## For primitive types, compares values; for objects, compares identity (same instance)
  if args.len < 1:
    return falseValue
  let other = args[0]
  # Unwrap self to get the underlying primitive value for comparison
  let selfVal = self.toValue().unwrap()
  let otherVal = other.unwrap()
  if selfVal == otherVal:
    return trueValue
  return falseValue

proc primitiveSlotNamesImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return slot names of this class as an array of symbols
  if self.kind != ikObject or self.class == nil:
    return newArrayInstance(arrayClass, @[]).toValue()

  # For Class objects, the slots are stored in the class's slotNames field
  # The receiver here is an Instance with ikObject kind, and self.class is our Class
  # We need to check if this is a wrapper around a Class object or a regular instance
  # For simplicity, we'll just use the class's slot names
  var slotNames: seq[NodeValue] = @[]
  for name in self.class.slotNames:
    slotNames.add(toValue(name))
  return newArrayInstance(arrayClass, slotNames).toValue()

proc primitiveSuperclassNamesImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return the names of superclasses as an array of strings
  if self.kind != ikObject or self.class == nil:
    return newArrayInstance(arrayClass, @[]).toValue()

  var superClassNames: seq[NodeValue] = @[]
  for sc in self.class.superclasses:
    superClassNames.add(toValue(sc.name))
  return newArrayInstance(arrayClass, superClassNames).toValue()

# Block value methods
proc primitiveValueImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Evaluate this block with no arguments
  if self.kind == ikObject and self.class == blockClass and not self.isNimProxy:
    let blockNode = cast[BlockNode](self.nimValue)

    # Get caller's activation to detect non-local returns
    let callerActivation = if interp.activationStack.len > 0:
                             interp.activationStack[interp.activationStack.len - 1]
                           else:
                             nil

    let blockResult = evalBlock(interp, interp.currentReceiver, blockNode)

    # Check if a non-local return was triggered (nonLocalReturnTarget set)
    if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
      return callerActivation.returnValue

    return blockResult
  return nilValue()

proc primitiveValueWithArgImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Evaluate this block with one argument
  if args.len < 1:
    return nilValue()
  if self.kind == ikObject and self.class == blockClass and not self.isNimProxy:
    let blockNode = cast[BlockNode](self.nimValue)

    # Get caller's activation to detect non-local returns
    let callerActivation = if interp.activationStack.len > 0:
                             interp.activationStack[interp.activationStack.len - 1]
                           else:
                             nil

    let blockResult = evalBlockWithArg(interp, interp.currentReceiver, blockNode, args[0])

    # Check if a non-local return was triggered (nonLocalReturnTarget set)
    if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
      return callerActivation.returnValue

    return blockResult
  return nilValue()

proc primitiveValueWithTwoArgsImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Evaluate this block with two arguments
  if args.len < 2:
    return nilValue()
  if self.kind == ikObject and self.class == blockClass and not self.isNimProxy:
    let blockNode = cast[BlockNode](self.nimValue)

    # Get caller's activation to detect non-local returns
    let callerActivation = if interp.activationStack.len > 0:
                             interp.activationStack[interp.activationStack.len - 1]
                           else:
                             nil

    let (blockResult, _) = evalBlockWithTwoArgs(interp, interp.currentReceiver, blockNode, args[0], args[1])

    # Check if a non-local return was triggered (nonLocalReturnTarget set)
    if callerActivation != nil and callerActivation.nonLocalReturnTarget != nil:
      return callerActivation.returnValue

    return blockResult
  return nilValue()

proc primitiveValueWithThreeArgsImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Evaluate this block with three arguments
  if args.len < 3:
    return nilValue()
  if self.kind == ikObject and self.class == blockClass and not self.isNimProxy:
    let blockNode = cast[BlockNode](self.nimValue)
    return evalBlockWithThreeArgs(interp, interp.currentReceiver, blockNode, args[0], args[1], args[2])
  return nilValue()

# Exception handling methods
proc formatStackTrace*(interp: Interpreter): string =
  ## Format the current activation stack as a readable stack trace
  result = ""
  for i, activation in interp.activationStack:
    let frameNum = i + 1
    if activation.currentMethod != nil:
      result.add($frameNum & ": <method>\n")
    else:
      result.add($frameNum & ": <unknown>\n")

# Array iteration method
proc arrayDoImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Iterate over array elements: arr do: [ :elem | code ]
  ## self is the array, args[0] is the block to execute for each element
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  # Check if this is an array
  if self.kind != ikArray:
    return nilValue()

  let blockNode = args[0].blockVal
  var lastResult = nilValue()

  # Iterate over array elements
  for elem in self.elements:
    # Invoke block with element as argument
    lastResult = interp.invokeBlock(blockNode, @[elem])

  return lastResult

# Built-in globals - NEW Class-based implementation
proc initGlobals*(interp: var Interpreter) =
  ## Initialize built-in global variables using new Class-based model
  ##
  ## IMPORTANT: This function ADDS methods to existing classes created by initCoreClasses().
  ## Do NOT create new classes here - reuse existing ones:
  ##   var arrayCls: Class
  ##   if arrayClass != nil: arrayCls = arrayClass  # Reuse existing
  ##   else: arrayCls = newClass(...)               # Only if not exists
  ##
  ## See objects.nim for full design documentation.

  # Set rootClass and create the basic class hierarchy from Root
  let rootCls = initRootClass()

  # Register addSuperclass: class method on classes
  # This allows adding a superclass to an existing class after creation
  # Useful for resolving method conflicts by adding superclass after overriding methods
  proc addSuperclassImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    # self.class is the Class object receiving the addSuperclass: message
    let cls = self.class
    if args.len < 1:
      raise newException(ValueError, "addSuperclass: requires a superclass as argument")

    var parentClass: Class = nil
    if args[0].kind == vkClass:
      parentClass = args[0].classVal
    elif args[0].kind == vkInstance and args[0].instVal.class != nil:
      # Instance wrapping a class (from class method dispatch)
      parentClass = args[0].instVal.class
    else:
      raise newException(ValueError, "addSuperclass: requires a class object, got: " & $args[0].kind)

    if parentClass == nil:
      raise newException(ValueError, "addSuperclass: superclass cannot be nil")

    addSuperclass(cls, parentClass)
    return nilValue()

  let addSuperclassMethod = createCoreMethod("addSuperclass:")
  addSuperclassMethod.nativeImpl = cast[pointer](addSuperclassImpl)
  addSuperclassMethod.hasInterpreterParam = true
  rootCls.classMethods["addSuperclass:"] = addSuperclassMethod
  rootCls.allClassMethods["addSuperclass:"] = addSuperclassMethod

  # Use existing Object class from initCoreClasses if available
  # initCoreClasses is called in newInterpreter before initGlobals
  var objectCls: Class
  if objectClass == nil:
    # Fallback: create Object class if initCoreClasses wasn't called
    objectCls = newClass(superclasses = @[rootCls], name = "Object")
    objectCls.tags = @["Object"]
    objectClass = objectCls
  else:
    # Use the Object class already created by initCoreClasses
    objectCls = objectClass

  # Register Object class methods (Object new)
  proc objectClassNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    # self.class is the class receiving the message (e.g., Table for Table new)
    if self != nil and self.class != nil:
      return newInstance(self.class).toValue()
    return newInstance(objectClass).toValue()

  let classNewMethod = createCoreMethod("new")
  classNewMethod.nativeImpl = cast[pointer](objectClassNewImpl)
  classNewMethod.hasInterpreterParam = true
  objectCls.classMethods["new"] = classNewMethod
  objectCls.allClassMethods["new"] = classNewMethod

  # Add perform: methods to Object class (for primitive dispatch from Smalltalk)
  let objPerformMethod = createCoreMethod("perform:")
  objPerformMethod.nativeImpl = cast[pointer](performWithImpl)
  objPerformMethod.hasInterpreterParam = true
  objectCls.methods["perform:"] = objPerformMethod
  objectCls.allMethods["perform:"] = objPerformMethod

  let objPerformWithMethod = createCoreMethod("perform:with:")
  objPerformWithMethod.nativeImpl = cast[pointer](performWithImpl)
  objPerformWithMethod.hasInterpreterParam = true
  objectCls.methods["perform:with:"] = objPerformWithMethod
  objectCls.allMethods["perform:with:"] = objPerformWithMethod

  let objPerformWithWithMethod = createCoreMethod("perform:with:with:")
  objPerformWithWithMethod.nativeImpl = cast[pointer](performWithImpl)
  objPerformWithWithMethod.hasInterpreterParam = true
  objectCls.methods["perform:with:with:"] = objPerformWithWithMethod
  objectCls.allMethods["perform:with:with:"] = objPerformWithWithMethod

  # Add primitiveIdentity: for == comparison
  let objIdentityMethod = createCoreMethod("primitiveIdentity:")
  objIdentityMethod.nativeImpl = cast[pointer](instIdentityImpl)
  objectCls.methods["primitiveIdentity:"] = objIdentityMethod
  objectCls.allMethods["primitiveIdentity:"] = objIdentityMethod

  # Add primitiveAsSelfDo: for asSelfDo: implementation
  let objAsSelfDoMethod = createCoreMethod("primitiveAsSelfDo:")
  objAsSelfDoMethod.nativeImpl = cast[pointer](primitiveAsSelfDoImpl)
  objAsSelfDoMethod.hasInterpreterParam = true
  objectCls.methods["primitiveAsSelfDo:"] = objAsSelfDoMethod
  objectCls.allMethods["primitiveAsSelfDo:"] = objAsSelfDoMethod

  # Add primitiveHasProperty: for hasProperty: implementation
  let objHasPropertyMethod = createCoreMethod("primitiveHasProperty:")
  objHasPropertyMethod.nativeImpl = cast[pointer](primitiveHasPropertyImpl)
  objHasPropertyMethod.hasInterpreterParam = true
  objectCls.methods["primitiveHasProperty:"] = objHasPropertyMethod
  objectCls.allMethods["primitiveHasProperty:"] = objHasPropertyMethod

  # Add primitiveProperties for properties implementation
  let objPropertiesMethod = createCoreMethod("primitiveProperties")
  objPropertiesMethod.nativeImpl = cast[pointer](primitivePropertiesImpl)
  objPropertiesMethod.hasInterpreterParam = true
  objectCls.methods["primitiveProperties"] = objPropertiesMethod
  objectCls.allMethods["primitiveProperties"] = objPropertiesMethod

  # Add primitiveRespondsTo: for respondsTo: implementation
  let objRespondsToMethod = createCoreMethod("primitiveRespondsTo:")
  objRespondsToMethod.nativeImpl = cast[pointer](primitiveRespondsToImpl)
  objRespondsToMethod.hasInterpreterParam = true
  objectCls.methods["primitiveRespondsTo:"] = objRespondsToMethod
  objectCls.allMethods["primitiveRespondsTo:"] = objRespondsToMethod

  # Add primitiveMethods for methods implementation
  let objMethodsMethod = createCoreMethod("primitiveMethods")
  objMethodsMethod.nativeImpl = cast[pointer](primitiveMethodsImpl)
  objMethodsMethod.hasInterpreterParam = true
  objectCls.methods["primitiveMethods"] = objMethodsMethod

  # Add primitiveClass for class implementation
  let objClassMethod = createCoreMethod("primitiveClass")
  objClassMethod.nativeImpl = cast[pointer](classImpl)
  objectCls.methods["primitiveClass"] = objClassMethod
  objectCls.allMethods["primitiveClass"] = objClassMethod
  objectCls.allMethods["primitiveMethods"] = objMethodsMethod

  # Add primitiveError: for error: implementation
  let objErrorMethod = createCoreMethod("primitiveError:")
  objErrorMethod.nativeImpl = cast[pointer](primitiveErrorImpl)
  objErrorMethod.hasInterpreterParam = true
  objectCls.methods["primitiveError:"] = objErrorMethod
  objectCls.allMethods["primitiveError:"] = objErrorMethod

  # Add primitiveEquals: for == implementation
  let objEqualsMethod = createCoreMethod("primitiveEquals:")
  objEqualsMethod.nativeImpl = cast[pointer](primitiveEqualsImpl)
  objectCls.methods["primitiveEquals:"] = objEqualsMethod
  objectCls.allMethods["primitiveEquals:"] = objEqualsMethod

  # Add primitiveIsKindOf: for isKindOf: implementation
  let objIsKindOfMethod = createCoreMethod("primitiveIsKindOf:")
  objIsKindOfMethod.nativeImpl = cast[pointer](primitiveIsKindOfImpl)
  objIsKindOfMethod.hasInterpreterParam = true
  objectCls.methods["primitiveIsKindOf:"] = objIsKindOfMethod
  objectCls.allMethods["primitiveIsKindOf:"] = objIsKindOfMethod

  # Add slotNames for class introspection - returns slot names of this class
  let objSlotNamesMethod = createCoreMethod("slotNames")
  objSlotNamesMethod.nativeImpl = cast[pointer](primitiveSlotNamesImpl)
  objSlotNamesMethod.hasInterpreterParam = true
  objectCls.methods["slotNames"] = objSlotNamesMethod
  objectCls.allMethods["slotNames"] = objSlotNamesMethod
  # Also register with primitiveSlotNames for <primitive: #primitiveSlotNames> syntax
  objectCls.methods["primitiveSlotNames"] = objSlotNamesMethod
  objectCls.allMethods["primitiveSlotNames"] = objSlotNamesMethod

  # Add superclassNames for class introspection - returns names of superclasses
  let objSuperclassNamesMethod = createCoreMethod("superclassNames")
  objSuperclassNamesMethod.nativeImpl = cast[pointer](primitiveSuperclassNamesImpl)
  objSuperclassNamesMethod.hasInterpreterParam = true
  objectCls.methods["superclassNames"] = objSuperclassNamesMethod
  objectCls.allMethods["superclassNames"] = objSuperclassNamesMethod
  # Also register with primitiveSuperclassNames for <primitive: #primitiveSuperclassNames> syntax
  objectCls.methods["primitiveSuperclassNames"] = objSuperclassNamesMethod
  objectCls.allMethods["primitiveSuperclassNames"] = objSuperclassNamesMethod

  # Add className for Class - returns the class name
  proc primitiveClassNameImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    if self.class != nil:
      return toValue(self.class.name)
    return toValue("")

  let classNameMethod = createCoreMethod("className")
  classNameMethod.nativeImpl = cast[pointer](primitiveClassNameImpl)
  classNameMethod.hasInterpreterParam = true
  # Add to instance methods (for objects to get their class name via className)
  objectCls.methods["className"] = classNameMethod
  objectCls.allMethods["className"] = classNameMethod
  # Also register with primitiveClassName for <primitive: #primitiveClassName> syntax
  objectCls.methods["primitiveClassName"] = classNameMethod
  objectCls.allMethods["primitiveClassName"] = classNameMethod
  # Add to class methods (for Class objects like String to respond to name)
  objectCls.classMethods["className"] = classNameMethod
  objectCls.allClassMethods["className"] = classNameMethod
  objectCls.classMethods["primitiveClassName"] = classNameMethod
  objectCls.allClassMethods["primitiveClassName"] = classNameMethod

  # Add print and println as native methods
  proc objPrintImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    # Print self to stdout without newline
    stdout.write(self.toValue().toString())
    return self.toValue()

  proc objPrintlnImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    # Print self to stdout with newline
    echo(self.toValue().toString())
    return self.toValue()

  let printMethod = createCoreMethod("print")
  printMethod.nativeImpl = cast[pointer](objPrintImpl)
  objectCls.methods["print"] = printMethod
  objectCls.allMethods["print"] = printMethod

  let printlnMethod = createCoreMethod("println")
  printlnMethod.nativeImpl = cast[pointer](objPrintlnImpl)
  objectCls.methods["println"] = printlnMethod
  objectCls.allMethods["println"] = printlnMethod

  # Add eval class primitive for evaluating code strings
  proc primitiveEvalImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    ## Evaluate a Nemo code string and return the result
    ## Takes one argument: the code string to evaluate
    if args.len < 1 or args[0].kind != vkString:
      return nilValue()

    let code = args[0].strVal
    let (results, err) = interp.evalStatements(code)
    if err.len > 0:
      # Return error as string
      return err.toValue()
    if results.len > 0:
      # Return the last result
      return results[^1]
    return nilValue()

  let evalMethod = createCoreMethod("eval:")
  evalMethod.nativeImpl = cast[pointer](primitiveEvalImpl)
  evalMethod.hasInterpreterParam = true
  objectCls.classMethods["eval:"] = evalMethod
  objectCls.allClassMethods["eval:"] = evalMethod
  # Also register as primitiveEval: for declarative syntax
  objectCls.classMethods["primitiveEval:"] = evalMethod
  objectCls.allClassMethods["primitiveEval:"] = evalMethod

  # Create Number class (derives from Object)
  let numberCls = newClass(superclasses = @[objectCls], name = "Number")
  numberCls.tags = @["Number"]

  # Create Integer class (derives from Number)
  let intCls = newClass(superclasses = @[numberCls], name = "Integer")
  intCls.tags = @["Integer", "Number"]
  integerClass = intCls

  # Register Integer arithmetic methods
  let plusMethod = createCoreMethod("+")
  plusMethod.nativeImpl = cast[pointer](plusImpl)
  intCls.methods["+"] = plusMethod
  intCls.allMethods["+"] = plusMethod

  let minusMethod = createCoreMethod("-")
  minusMethod.nativeImpl = cast[pointer](minusImpl)
  intCls.methods["-"] = minusMethod
  intCls.allMethods["-"] = minusMethod

  let starMethod = createCoreMethod("*")
  starMethod.nativeImpl = cast[pointer](starImpl)
  intCls.methods["*"] = starMethod
  intCls.allMethods["*"] = starMethod

  let slashMethod = createCoreMethod("/")
  slashMethod.nativeImpl = cast[pointer](slashImpl)
  intCls.methods["/"] = slashMethod
  intCls.allMethods["/"] = slashMethod

  # Register Integer comparison methods
  let ltMethod = createCoreMethod("<")
  ltMethod.nativeImpl = cast[pointer](ltImpl)
  intCls.methods["<"] = ltMethod
  intCls.allMethods["<"] = ltMethod

  let gtMethod = createCoreMethod(">")
  gtMethod.nativeImpl = cast[pointer](gtImpl)
  intCls.methods[">"] = gtMethod
  intCls.allMethods[">"] = gtMethod

  let eqMethod = createCoreMethod("=")
  eqMethod.nativeImpl = cast[pointer](eqImpl)
  intCls.methods["="] = eqMethod
  intCls.allMethods["="] = eqMethod

  let leMethod = createCoreMethod("<=")
  leMethod.nativeImpl = cast[pointer](leImpl)
  intCls.methods["<="] = leMethod
  intCls.allMethods["<="] = leMethod

  let geMethod = createCoreMethod(">=")
  geMethod.nativeImpl = cast[pointer](geImpl)
  intCls.methods[">="] = geMethod
  intCls.allMethods[">="] = geMethod

  let neMethod = createCoreMethod("<>")
  neMethod.nativeImpl = cast[pointer](neImpl)
  intCls.methods["<>"] = neMethod
  intCls.allMethods["<>"] = neMethod

  # Register printString on Integer
  let intPrintStringMethod = createCoreMethod("printString")
  intPrintStringMethod.nativeImpl = cast[pointer](printStringImpl)
  intCls.methods["printString"] = intPrintStringMethod
  intCls.allMethods["printString"] = intPrintStringMethod

  # Register additional Integer methods
  let intDivMethod = createCoreMethod("//")
  intDivMethod.nativeImpl = cast[pointer](intDivImpl)
  intCls.methods["//"] = intDivMethod
  intCls.allMethods["//"] = intDivMethod

  let backslashModuloMethod = createCoreMethod("\\")
  backslashModuloMethod.nativeImpl = cast[pointer](backslashModuloImpl)
  intCls.methods["\\"] = backslashModuloMethod
  intCls.allMethods["\\"] = backslashModuloMethod

  let moduloMethod = createCoreMethod("%")
  moduloMethod.nativeImpl = cast[pointer](moduloImpl)
  intCls.methods["%"] = moduloMethod
  intCls.allMethods["%"] = moduloMethod

  # Create Float class (derives from Number)
  let floatCls = newClass(superclasses = @[numberCls], name = "Float")
  floatCls.tags = @["Float", "Number"]
  floatClass = floatCls

  # Copy arithmetic methods to Float
  floatCls.allMethods = intCls.allMethods

  # Add Float-specific methods
  let sqrtMethod = createCoreMethod("sqrt")
  sqrtMethod.nativeImpl = cast[pointer](sqrtImpl)
  floatCls.methods["sqrt"] = sqrtMethod
  floatCls.allMethods["sqrt"] = sqrtMethod

  # Create String class (derives from Object)
  let stringCls = newClass(superclasses = @[objectCls], name = "String")
  stringCls.tags = @["String", "Text"]
  stringClass = stringCls

  # Register String primitive methods
  let stringConcatMethod = createCoreMethod("primitiveConcat:")
  stringConcatMethod.nativeImpl = cast[pointer](instStringConcatImpl)
  stringCls.methods["primitiveConcat:"] = stringConcatMethod
  stringCls.allMethods["primitiveConcat:"] = stringConcatMethod

  let stringSizeMethod = createCoreMethod("primitiveStringSize")
  stringSizeMethod.nativeImpl = cast[pointer](instStringSizeImpl)
  stringCls.methods["primitiveStringSize"] = stringSizeMethod
  stringCls.allMethods["primitiveStringSize"] = stringSizeMethod

  let stringAtMethod = createCoreMethod("primitiveStringAt:")
  stringAtMethod.nativeImpl = cast[pointer](instStringAtImpl)
  stringCls.methods["primitiveStringAt:"] = stringAtMethod
  stringCls.allMethods["primitiveStringAt:"] = stringAtMethod

  let stringSplitMethod = createCoreMethod("primitiveSplit:")
  stringSplitMethod.nativeImpl = cast[pointer](instStringSplitImpl)
  stringCls.methods["primitiveSplit:"] = stringSplitMethod
  stringCls.allMethods["primitiveSplit:"] = stringSplitMethod

  # Register Instance-based String primitives
  let stringLowercaseMethod = createCoreMethod("primitiveLowercase")
  stringLowercaseMethod.nativeImpl = cast[pointer](instStringLowercaseImpl)
  stringCls.methods["primitiveLowercase"] = stringLowercaseMethod
  stringCls.allMethods["primitiveLowercase"] = stringLowercaseMethod

  let stringUppercaseMethod = createCoreMethod("primitiveUppercase")
  stringUppercaseMethod.nativeImpl = cast[pointer](instStringUppercaseImpl)
  stringCls.methods["primitiveUppercase"] = stringUppercaseMethod
  stringCls.allMethods["primitiveUppercase"] = stringUppercaseMethod

  let stringTrimMethod = createCoreMethod("primitiveTrim")
  stringTrimMethod.nativeImpl = cast[pointer](instStringTrimImpl)
  stringCls.methods["primitiveTrim"] = stringTrimMethod
  stringCls.allMethods["primitiveTrim"] = stringTrimMethod

  let stringFromToMethod = createCoreMethod("primitiveFromTo:")
  stringFromToMethod.nativeImpl = cast[pointer](instStringFromToImpl)
  stringCls.methods["primitiveFromTo:"] = stringFromToMethod
  stringCls.allMethods["primitiveFromTo:"] = stringFromToMethod

  let stringIndexOfMethod = createCoreMethod("primitiveIndexOf:")
  stringIndexOfMethod.nativeImpl = cast[pointer](instStringIndexOfImpl)
  stringCls.methods["primitiveIndexOf:"] = stringIndexOfMethod
  stringCls.allMethods["primitiveIndexOf:"] = stringIndexOfMethod

  let stringIncludesSubStringMethod = createCoreMethod("primitiveIncludesSubString:")
  stringIncludesSubStringMethod.nativeImpl = cast[pointer](instStringIncludesSubStringImpl)
  stringCls.methods["primitiveIncludesSubString:"] = stringIncludesSubStringMethod
  stringCls.allMethods["primitiveIncludesSubString:"] = stringIncludesSubStringMethod

  let stringReplaceWithMethod = createCoreMethod("primitiveReplaceWith:")
  stringReplaceWithMethod.nativeImpl = cast[pointer](instStringReplaceWithImpl)
  stringCls.methods["primitiveReplaceWith:"] = stringReplaceWithMethod
  stringCls.allMethods["primitiveReplaceWith:"] = stringReplaceWithMethod

  let stringAsIntegerMethod = createCoreMethod("primitiveAsInteger")
  stringAsIntegerMethod.nativeImpl = cast[pointer](instStringAsIntegerImpl)
  stringCls.methods["primitiveAsInteger"] = stringAsIntegerMethod
  stringCls.allMethods["primitiveAsInteger"] = stringAsIntegerMethod

  let stringAsSymbolMethod = createCoreMethod("primitiveAsSymbol")
  stringAsSymbolMethod.nativeImpl = cast[pointer](instStringAsSymbolImpl)
  stringCls.methods["primitiveAsSymbol"] = stringAsSymbolMethod
  stringCls.allMethods["primitiveAsSymbol"] = stringAsSymbolMethod

  let stringRepeatMethod = createCoreMethod("primitiveRepeat:")
  stringRepeatMethod.nativeImpl = cast[pointer](instStringRepeatImpl)
  stringCls.methods["primitiveRepeat:"] = stringRepeatMethod
  stringCls.allMethods["primitiveRepeat:"] = stringRepeatMethod

  # Use existing Array class from initCoreClasses or create if needed
  var arrayCls: Class
  if arrayClass != nil:
    arrayCls = arrayClass
  else:
    arrayCls = newClass(superclasses = @[objectCls], name = "Array")
    arrayCls.tags = @["Array", "Collection"]
    arrayClass = arrayCls

  # Register Array methods
  let arraySizeMethod = createCoreMethod("size")
  arraySizeMethod.nativeImpl = cast[pointer](arraySizeImpl)
  arrayCls.methods["size"] = arraySizeMethod
  arrayCls.allMethods["size"] = arraySizeMethod

  let arrayAddMethod = createCoreMethod("add:")
  arrayAddMethod.nativeImpl = cast[pointer](arrayAddImpl)
  arrayCls.methods["add:"] = arrayAddMethod
  arrayCls.allMethods["add:"] = arrayAddMethod

  let arrayAtMethod = createCoreMethod("at:")
  arrayAtMethod.nativeImpl = cast[pointer](arrayAtImpl)
  arrayCls.methods["at:"] = arrayAtMethod
  arrayCls.allMethods["at:"] = arrayAtMethod

  let arrayAtPutMethod = createCoreMethod("at:put:")
  arrayAtPutMethod.nativeImpl = cast[pointer](arrayAtPutImpl)
  arrayCls.methods["at:put:"] = arrayAtPutMethod
  arrayCls.allMethods["at:put:"] = arrayAtPutMethod

  let arrayIncludesMethod = createCoreMethod("includes:")
  arrayIncludesMethod.nativeImpl = cast[pointer](arrayIncludesImpl)
  arrayCls.methods["includes:"] = arrayIncludesMethod
  arrayCls.allMethods["includes:"] = arrayIncludesMethod

  let arrayReverseMethod = createCoreMethod("reverse")
  arrayReverseMethod.nativeImpl = cast[pointer](arrayReverseImpl)
  arrayCls.methods["reverse"] = arrayReverseMethod
  arrayCls.allMethods["reverse"] = arrayReverseMethod

  let arrayJoinMethod = createCoreMethod("join:")
  arrayJoinMethod.nativeImpl = cast[pointer](arrayJoinImpl)
  arrayCls.methods["join:"] = arrayJoinMethod
  arrayCls.allMethods["join:"] = arrayJoinMethod

  let arrayDoMethod = createCoreMethod("do:")
  arrayDoMethod.nativeImpl = cast[pointer](arrayDoImpl)
  arrayDoMethod.hasInterpreterParam = true
  arrayCls.methods["do:"] = arrayDoMethod
  arrayCls.allMethods["do:"] = arrayDoMethod

  # Use existing Table class from initCoreClasses or create if needed
  var tableCls: Class
  if tableClass != nil:
    tableCls = tableClass
  else:
    tableCls = newClass(superclasses = @[objectCls], name = "Table")
    tableCls.tags = @["Table", "Dictionary", "Collection"]
    tableClass = tableCls

  # Register Table primitive methods
  let tableAtMethod = createCoreMethod("at:")
  tableAtMethod.nativeImpl = cast[pointer](tableAtImpl)
  tableCls.methods["at:"] = tableAtMethod
  tableCls.allMethods["at:"] = tableAtMethod

  let tableAtPutMethod = createCoreMethod("at:put:")
  tableAtPutMethod.nativeImpl = cast[pointer](tableAtPutImpl)
  tableCls.methods["at:put:"] = tableAtPutMethod
  tableCls.allMethods["at:put:"] = tableAtPutMethod

  let tableKeysMethod = createCoreMethod("primitiveKeys")
  tableKeysMethod.nativeImpl = cast[pointer](tableKeysImpl)
  tableCls.methods["primitiveKeys"] = tableKeysMethod
  tableCls.allMethods["primitiveKeys"] = tableKeysMethod

  # Register Table class new method (creates ikTable instance)
  proc tableClassNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    # Create a Table instance with ikTable kind (not ikObject)
    # self.class is the class receiving the message (e.g., Table or a subclass)
    let targetClass = if self != nil and self.class != nil: self.class else: tableClass
    return newTableInstance(targetClass, initTable[NodeValue, NodeValue]()).toValue()

  let tableNewMethod = createCoreMethod("new")
  tableNewMethod.nativeImpl = cast[pointer](tableClassNewImpl)
  tableNewMethod.hasInterpreterParam = true
  tableCls.classMethods["new"] = tableNewMethod
  tableCls.allClassMethods["new"] = tableNewMethod

  # Create Boolean class (derives from Object)
  let booleanCls = newClass(superclasses = @[objectCls], name = "Boolean")
  booleanCls.tags = @["Boolean"]
  booleanClass = booleanCls

  # Register Boolean methods
  let ifTrueMethod = createCoreMethod("ifTrue:")
  ifTrueMethod.nativeImpl = cast[pointer](ifTrueImpl)
  ifTrueMethod.hasInterpreterParam = true
  booleanCls.methods["ifTrue:"] = ifTrueMethod
  booleanCls.allMethods["ifTrue:"] = ifTrueMethod

  let ifFalseMethod = createCoreMethod("ifFalse:")
  ifFalseMethod.nativeImpl = cast[pointer](ifFalseImpl)
  ifFalseMethod.hasInterpreterParam = true
  booleanCls.methods["ifFalse:"] = ifFalseMethod
  booleanCls.allMethods["ifFalse:"] = ifFalseMethod

  # Create True class (singleton class for true value)
  let trueCls = newClass(superclasses = @[booleanCls], name = "True")
  trueCls.tags = @["True", "Boolean"]
  trueClassCache = trueCls

  # Create False class (singleton class for false value)
  let falseCls = newClass(superclasses = @[booleanCls], name = "False")
  falseCls.tags = @["False", "Boolean"]
  falseClassCache = falseCls

  # Create Block class (derives from Object)
  let blockCls = newClass(superclasses = @[objectCls], name = "Block")
  blockCls.tags = @["Block", "Closure"]
  blockClass = blockCls

  # Register Block loop methods
  let whileTrueMethod = createCoreMethod("whileTrue:")
  whileTrueMethod.nativeImpl = cast[pointer](whileTrueImpl)
  whileTrueMethod.hasInterpreterParam = true
  blockCls.methods["whileTrue:"] = whileTrueMethod
  blockCls.allMethods["whileTrue:"] = whileTrueMethod

  let whileFalseMethod = createCoreMethod("whileFalse:")
  whileFalseMethod.nativeImpl = cast[pointer](whileFalseImpl)
  whileFalseMethod.hasInterpreterParam = true
  blockCls.methods["whileFalse:"] = whileFalseMethod
  blockCls.allMethods["whileFalse:"] = whileFalseMethod

  # Register Block value methods
  let primitiveValueMethod = createCoreMethod("primitiveValue")
  primitiveValueMethod.nativeImpl = cast[pointer](primitiveValueImpl)
  primitiveValueMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue"] = primitiveValueMethod
  blockCls.allMethods["primitiveValue"] = primitiveValueMethod

  let primitiveValueWithArgMethod = createCoreMethod("primitiveValue:")
  primitiveValueWithArgMethod.nativeImpl = cast[pointer](primitiveValueWithArgImpl)
  primitiveValueWithArgMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue:"] = primitiveValueWithArgMethod
  blockCls.allMethods["primitiveValue:"] = primitiveValueWithArgMethod

  let primitiveValueWithTwoArgsMethod = createCoreMethod("primitiveValue:value:")
  primitiveValueWithTwoArgsMethod.nativeImpl = cast[pointer](primitiveValueWithTwoArgsImpl)
  primitiveValueWithTwoArgsMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue:value:"] = primitiveValueWithTwoArgsMethod
  blockCls.allMethods["primitiveValue:value:"] = primitiveValueWithTwoArgsMethod

  let primitiveValueWithThreeArgsMethod = createCoreMethod("primitiveValue:value:value:")
  primitiveValueWithThreeArgsMethod.nativeImpl = cast[pointer](primitiveValueWithThreeArgsImpl)
  primitiveValueWithThreeArgsMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue:value:value:"] = primitiveValueWithThreeArgsMethod
  blockCls.allMethods["primitiveValue:value:value:"] = primitiveValueWithThreeArgsMethod

  # Create UndefinedObject class (derives from Object) - the class of nil
  let undefinedObjCls = newClass(superclasses = @[objectCls], name = "UndefinedObject")
  undefinedObjCls.tags = @["UndefinedObject", "Object"]
  undefinedObjectClass = undefinedObjCls  # Set global variable in types module

  # Create the singleton nil instance (instance of UndefinedObject)
  let nilInst = Instance(kind: ikObject, class: undefinedObjCls, slots: @[])
  nilInstance = nilInst  # Set global variable in types module

  # Note: FileStream class and Stdout instance are created in loadStdlib after
  # loading FileStream.nemo. We avoid creating them here to prevent class
  # identity issues where the .nemo file would replace the Nim-created class.

  # Create Class instance for each class so it can be stored as a value
  # Add global bindings for classes
  interp.globals[]["Root"] = rootCls.toValue()
  interp.globals[]["Object"] = objectCls.toValue()
  interp.globals[]["Number"] = numberCls.toValue()
  interp.globals[]["Integer"] = intCls.toValue()
  interp.globals[]["Float"] = floatCls.toValue()
  interp.globals[]["String"] = stringCls.toValue()
  interp.globals[]["Array"] = arrayCls.toValue()
  interp.globals[]["Table"] = tableCls.toValue()
  interp.globals[]["Boolean"] = booleanCls.toValue()
  interp.globals[]["True"] = trueCls.toValue()
  interp.globals[]["False"] = falseCls.toValue()
  interp.globals[]["Block"] = blockCls.toValue()
  interp.globals[]["UndefinedObject"] = undefinedObjCls.toValue()

  # Add primitive values
  interp.globals[]["true"] = NodeValue(kind: vkBool, boolVal: true)
  interp.globals[]["false"] = NodeValue(kind: vkBool, boolVal: false)
  interp.globals[]["nil"] = nilValue()

  # Protect core classes and values from reassignment
  protectGlobal("Class")
  protectGlobal("Root")
  protectGlobal("Object")
  protectGlobal("Number")
  protectGlobal("Integer")
  protectGlobal("Float")
  protectGlobal("String")
  protectGlobal("Array")
  protectGlobal("Table")
  protectGlobal("Boolean")
  protectGlobal("True")
  protectGlobal("False")
  protectGlobal("Block")
  protectGlobal("UndefinedObject")
  protectGlobal("true")
  protectGlobal("false")
  protectGlobal("nil")

  # Initialize the Nemo global - an instance of GlobalTable that wraps global namespace
  # Note: Process and Scheduler classes are initialized by initProcessorGlobal
  # which is called by newSchedulerContext in the scheduler module
  initNemoGlobal(interp)


proc loadStdlib*(interp: var Interpreter, bootstrapFile: string = "") =
  ## Load core library files
  ## If bootstrapFile is provided and exists, it will be loaded and should use
  ## Nemo load: to load other files. Otherwise, uses the default hardcoded list.

  # If bootstrap file is specified and exists, use it
  if bootstrapFile.len > 0 and fileExists(bootstrapFile):
    debug("Loading bootstrap file: ", bootstrapFile)
    let source = readFile(bootstrapFile)
    let (_, err) = interp.evalStatements(source)
    if err.len > 0:
      warn("Failed to load bootstrap file ", bootstrapFile, ": ", err)
    else:
      debug("Successfully loaded bootstrap: ", bootstrapFile)
  else:
    # Fall back to hardcoded list (for backward compatibility)
    let libPath = interp.nemoHome / "lib" / "core"

    let stdlibFiles = [
      "Object.nemo",
      "Boolean.nemo",
      "Block.nemo",
      "Number.nemo",
      "Collections.nemo",
      "String.nemo",
      "FileStream.nemo",
      "Exception.nemo",
      "TestCase.nemo"
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

  # Set up class caches for primitive types
  # These allow wrapped primitives to inherit methods from stdlib

  # Number hierarchy: Number -> Integer, Float
  if "Number" in interp.globals[]:
    let numVal = interp.globals[]["Number"]
    if numVal.kind == vkClass:
      numberClassCache = numVal.classVal
      debug("Set numberClassCache from Number global")

  if "Integer" in interp.globals[]:
    let intVal = interp.globals[]["Integer"]
    if intVal.kind == vkClass:
      integerClassCache = intVal.classVal
      debug("Set integerClassCache from Integer global")

  if "String" in interp.globals[]:
    let strVal = interp.globals[]["String"]
    if strVal.kind == vkClass:
      stringClassCache = strVal.classVal
      debug("Set stringClassCache from String global")

  # Boolean hierarchy: Boolean -> True, False
  if "Boolean" in interp.globals[]:
    let boolVal = interp.globals[]["Boolean"]
    if boolVal.kind == vkClass:
      booleanClassCache = boolVal.classVal
      debug("Set booleanClassCache from Boolean global")

  if "True" in interp.globals[]:
    let trueVal = interp.globals[]["True"]
    if trueVal.kind == vkClass:
      trueClassCache = trueVal.classVal
      debug("Set trueClassCache from True global")

  if "False" in interp.globals[]:
    let falseVal = interp.globals[]["False"]
    if falseVal.kind == vkClass:
      falseClassCache = falseVal.classVal
      debug("Set falseClassCache from False global")

  if "Block" in interp.globals[]:
    let blockVal = interp.globals[]["Block"]
    if blockVal.kind == vkClass:
      blockClassCache = blockVal.classVal
      debug("Set blockClassCache from Block global")

  if "Table" in interp.globals[]:
    let tableVal = interp.globals[]["Table"]
    if tableVal.kind == vkClass:
      tableClassCache = tableVal.classVal
      debug("Set tableClassCache from Table global")

  # Set up FileStream class and Stdout instance after loading FileStream.nemo
  # This ensures Stdout uses the class defined in the .nemo file, not a separate
  # Nim-created class that would cause method lookup issues.
  if "FileStream" in interp.globals[]:
    let fsVal = interp.globals[]["FileStream"]
    if fsVal.kind == vkClass:
      let fileStreamCls = fsVal.classVal
      # Register native write: and writeline: methods on the FileStream class
      let fsWriteMethod = createCoreMethod("write:")
      fsWriteMethod.nativeImpl = cast[pointer](writeImpl)
      fileStreamCls.methods["write:"] = fsWriteMethod
      fileStreamCls.allMethods["write:"] = fsWriteMethod
      let fsWritelineMethod = createCoreMethod("writeline:")
      fsWritelineMethod.nativeImpl = cast[pointer](writelineImpl)
      fileStreamCls.methods["writeline:"] = fsWritelineMethod
      fileStreamCls.allMethods["writeline:"] = fsWritelineMethod
      debug("Registered native FileStream methods")
      # Create Stdout instance from the FileStream class
      let stdoutInstance = fileStreamCls.newInstance()
      interp.globals[]["Stdout"] = stdoutInstance.toValue()
      debug("Created Stdout instance from FileStream class")

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

# ============================================================================
# GlobalTable Class and Nemo Global
# ============================================================================

type
  GlobalTableProxy* = ref object
    globals*: ref Table[string, NodeValue]

# Keep GlobalTableProxy references alive - stored as raw pointer in nimValue,
# the GC needs to see actual Nim refs to prevent collection
var globalTableProxies: seq[GlobalTableProxy] = @[]

proc createGlobalTableClass*(): Class =
  ## Create the GlobalTable class - a subclass of Table that wraps the globals table
  ## The global globals table is accessible via the 'Nemo' global

  # Ensure Table class exists
  if tableClass == nil or objectClass == nil:
    return nil

  if "GlobalTable" in objectClass.allClassMethods or "GlobalTable" in globals:
    # Already initialized
    for name, val in globals:
      if name == "GlobalTable" and val.kind == vkClass:
        return val.classVal

  let globalTableClass = newClass(superclasses = @[tableClass], name = "GlobalTable")
  globalTableClass.tags = @["GlobalTable", "Dictionary"]
  globalTableClass.isNimProxy = true
  globalTableClass.nemoType = "GlobalTable"

  # GlobalTable inherits all methods from Table (keys, at:, at:put:, includesKey:)
  # No additional methods needed - it just wraps the globals table

  return globalTableClass

proc initNemoGlobal*(interp: var Interpreter) =
  ## Initialize the Nemo global - an instance of GlobalTable that wraps global namespace

  # Create the GlobalTable class
  let globalTableClass = createGlobalTableClass()
  if globalTableClass == nil:
    return  # Table class not initialized yet

  # Install special GlobalTable methods that access the globals table
  installGlobalTableMethods(globalTableClass)

  # Create a GlobalTable proxy instance
  let proxy = GlobalTableProxy(globals: interp.globals)
  globalTableProxies.add(proxy)  # Keep reference alive for GC
  let globalTableInstance = Instance(kind: ikObject, class: globalTableClass, slots: @[])
  globalTableInstance.isNimProxy = true
  globalTableInstance.nimValue = cast[pointer](proxy)

  # Add to globals as 'Nemo' (the global namespace accessor)
  interp.globals[]["Nemo"] = globalTableInstance.toValue()

  # Also add the GlobalTable class itself to globals for reflection
  interp.globals[]["GlobalTable"] = globalTableClass.toValue()

# Special handling for GlobalTable - modify Table methods to access globals
proc globalTableAtImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## GlobalTable at: - access global variable
  let proxy = if self.isNimProxy and self.class.nemoType == "GlobalTable" and self.nimValue != nil:
                cast[GlobalTableProxy](self.nimValue)
              else:
                nil

  if proxy != nil and proxy.globals != nil:
    # This is a GlobalTable proxy - access the globals table
    let key = if args.len > 0:
                if args[0].kind == vkString: args[0].strVal
                elif args[0].kind == vkSymbol: args[0].symVal
                else: ""
              else:
                ""
    if key.len > 0 and key in proxy.globals[]:
      return proxy.globals[][key]
    return nilValue()
  else:
    # Fall through to regular Table behavior
    return tableAtImpl(self, args)

proc globalTableAtPutImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## GlobalTable at:put: - set global variable
  let proxy = if self.isNimProxy and self.class.nemoType == "GlobalTable" and self.nimValue != nil:
                cast[GlobalTableProxy](self.nimValue)
              else:
                nil

  if proxy != nil and proxy.globals != nil:
    # This is a GlobalTable proxy - access the globals table
    if args.len >= 2:
      let key = if args[0].kind == vkString: args[0].strVal
                elif args[0].kind == vkSymbol: args[0].symVal
                else: ""
      if key.len > 0:
        proxy.globals[][key] = args[1]
        return args[1]
    return nilValue()
  else:
    # Fall through to regular Table behavior
    return tableAtPutImpl(self, args)

proc globalTableKeysImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## GlobalTable keys - get all global names as array
  let proxy = if self.isNimProxy and self.class.nemoType == "GlobalTable" and self.nimValue != nil:
                cast[GlobalTableProxy](self.nimValue)
              else:
                nil

  if proxy != nil and proxy.globals != nil:
    # This is a GlobalTable proxy - access the globals table
    if proxy.globals != nil:  # Double-check before dereferencing
      var elements: seq[NodeValue] = @[]
      for key in proxy.globals[].keys():
        elements.add(toValue(key))
      return NodeValue(kind: vkInstance, instVal: newArrayInstance(arrayClass, elements))
  else:
    # Fall through to regular Table behavior
    return tableKeysImpl(self, args)

proc globalTableIncludesKeyImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## GlobalTable includesKey: - check if global exists
  let proxy = if self.isNimProxy and self.class.nemoType == "GlobalTable" and self.nimValue != nil:
                cast[GlobalTableProxy](self.nimValue)
              else:
                nil

  if proxy != nil and proxy.globals != nil:
    # This is a GlobalTable proxy - access the globals table
    if args.len > 0:
      let key = if args[0].kind == vkString: args[0].strVal
                elif args[0].kind == vkSymbol: args[0].symVal
                else: ""
      if proxy.globals != nil:  # Double-check before dereferencing
        return toValue(key in proxy.globals[])
    return toValue(false)
  else:
    # Fall through to regular Table behavior
    return tableIncludesKeyImpl(self, args)

proc globalTableLoadImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## GlobalTable load: - load and evaluate a Nemo file
  ## Resolves paths relative to NEMO_HOME if not absolute
  if args.len < 1:
    return nilValue()

  # Get the file path from arguments
  let pathArg = args[0]
  let filePath = case pathArg.kind
    of vkString: pathArg.strVal
    of vkSymbol: pathArg.symVal
    else: ""

  if filePath.len == 0:
    return nilValue()

  # Resolve path relative to nemoHome if not absolute
  let resolvedPath = if filePath.isAbsolute:
                       filePath
                     else:
                       interp.nemoHome / filePath

  # Check if file exists
  if not fileExists(resolvedPath):
    stderr.writeLine("Error: File not found: ", resolvedPath)
    return nilValue()

  # Read and evaluate the file
  try:
    let source = readFile(resolvedPath)
    let (_, err) = interp.evalStatements(source)
    if err.len > 0:
      stderr.writeLine("Error loading ", resolvedPath, ": ", err)
      return nilValue()
    debug("Successfully loaded: ", resolvedPath)
    return toValue(true)
  except Exception as e:
    stderr.writeLine("Error reading ", resolvedPath, ": ", e.msg)
    return nilValue()

# Patch GlobalTable methods after class creation
proc installGlobalTableMethods*(globalTableClass: Class) =
  ## Install special GlobalTable methods that wrap the globals table
  if globalTableClass == nil:
    return

  # Override at: method
  let atMethod = createCoreMethod("at:")
  atMethod.nativeImpl = cast[pointer](globalTableAtImpl)
  atMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "at:", atMethod)

  # Override at:put: method
  let atPutMethod = createCoreMethod("at:put:")
  atPutMethod.nativeImpl = cast[pointer](globalTableAtPutImpl)
  atPutMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "at:put:", atPutMethod)

  # Override keys method
  let keysMethod = createCoreMethod("keys")
  keysMethod.nativeImpl = cast[pointer](globalTableKeysImpl)
  keysMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "keys", keysMethod)

  # Override includesKey: method
  let includesKeyMethod = createCoreMethod("includesKey:")
  includesKeyMethod.nativeImpl = cast[pointer](globalTableIncludesKeyImpl)
  includesKeyMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "includesKey:", includesKeyMethod)

  # Add load: method for loading Nemo files
  let loadMethod = createCoreMethod("load:")
  loadMethod.nativeImpl = cast[pointer](globalTableLoadImpl)
  loadMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "load:", loadMethod)
