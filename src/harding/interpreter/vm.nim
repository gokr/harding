import std/[tables, strutils, math, strformat, logging, os, hashes]
import ../core/types
import ../parser/lexer
import ../parser/parser
import ../interpreter/objects
import ../interpreter/activation

when defined(granite):
  import ../interpreter/compiler_primitives

# Class caches are defined in objects.nim and shared across the interpreter

# Forward declarations - implementations are in objects.nim
# Note: These are imported from objects.nim via the import statement above

# ============================================================================
# Platform-Specific Output Helpers
# ============================================================================

template writeStderr*(s: string) =
  stderr.write(s)
template nativeImplIsSet*(meth: BlockNode): bool =
  meth.nativeImpl != nil

# ============================================================================
# Evaluation engine for Harding
# Interprets AST nodes and executes currentMethods
# ============================================================================

# Protected globals that cannot be reassigned
var protectedGlobals*: seq[string] = @["Harding", "GlobalTable", "Object", "Root", "Mixin", "nil", "true", "false"]

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
proc performWithImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue
proc evalWithVM*(interp: var Interpreter, node: Node): NodeValue
proc doit*(interp: var Interpreter, source: string, dumpAst = false): (NodeValue, string)
proc evalStatements*(interp: var Interpreter, source: string): (seq[NodeValue], string)
proc installGlobalTableMethods*(globalTableClass: Class)
proc installLibraryMethods*()
proc initHardingGlobal*(interp: var Interpreter)

# ============================================================================
# Stack Trace Printing
# ============================================================================

proc findSelectorForMethod(classObj: Class, methodBlk: BlockNode, isClassMethod: bool): string =
  ## Look up the selector name for a given method block in a class
  if classObj == nil or methodBlk == nil:
    return "(unknown)"
  let methods = if isClassMethod: classObj.classMethods else: classObj.methods
  for selector, blk in methods:
    if blk == methodBlk:
      return selector
  return "(unknown)"

proc printStackTrace*(interp: var Interpreter) =
  ## Print the current activation stack for debugging
  writeStderr("\n=== Stack Trace ===")
  if interp.activationStack.len == 0:
    writeStderr("  (empty activation stack)")
  else:
    for i in countdown(interp.activationStack.len - 1, 0):
      let activation = interp.activationStack[i]
      let className = if activation.definingObject != nil:
                        activation.definingObject.name
                      elif activation.receiver != nil and activation.receiver.class != nil:
                        activation.receiver.class.name
                      else:
                        "(unknown)"
      let receiverClass = if activation.receiver != nil and activation.receiver.class != nil:
                            activation.receiver.class.name
                          else:
                            "(nil)"
      let isMethod = activation.currentMethod != nil and activation.currentMethod.isMethod
      let methodType = if isMethod: "" else: "(block) "
      let selector = if isMethod:
                       findSelectorForMethod(activation.definingObject, activation.currentMethod, activation.isClassMethod)
                     else:
                       ""
      let methodDisplay = if selector.len > 0: selector else: methodType
      writeStderr(fmt("  {interp.activationStack.len - 1 - i}: {className}>>{methodDisplay}(self={receiverClass})"))
  writeStderr("===================\n")

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
    # not where they're executed. IMPORTANT: Only apply to blocks, NOT methods.
    # Methods should access slots on the receiver, not captured lexical variables.
    if activation.currentMethod != nil and activation.currentMethod.capturedEnvInitialized and activation.currentMethod.capturedEnv.len > 0 and not activation.currentMethod.isMethod:
      if name in activation.currentMethod.capturedEnv:
        let value = activation.currentMethod.capturedEnv[name].value
        debug("Found variable in captured environment: ", name, " = ", value.toString())
        return (true, value)

    # Check capturedVars on the activation - these are shared MutableCells for
    # variables captured by child blocks. Reading from the cell ensures we see
    # updates made by nested block executions.
    if name in activation.capturedVars:
      let val = activation.capturedVars[name].value
      debug("lookupVariable: found ", name, " in capturedVars kind=", $val.kind)
      return (true, val)

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
      # This is a block - check imported libraries then globals first
      for i in countdown(interp.importedLibraries.high, 0):
        let lib = interp.importedLibraries[i]
        if lib != nil and lib.kind == ikObject and lib.class == libraryClass:
          let bindingsVal = lib.slots[0]
          if bindingsVal.kind == vkInstance and bindingsVal.instVal != nil and bindingsVal.instVal.kind == ikTable:
            let key = toValue(name)
            if key in bindingsVal.instVal.entries:
              debug("Found variable in imported library (in block): ", name)
              return (true, bindingsVal.instVal.entries[key])
      if name in interp.globals[]:
        debug("Found variable in globals (in block): ", name, " = ", interp.globals[][name].toString())
        let val = interp.globals[][name]
        return (true, val)

  # Walk up the activation chain (for nested scopes)
  if activation != nil:
    activation = activation.sender
  while activation != nil:
    # Check captured environment - IMPORTANT: Only for blocks, NOT methods
    # Methods should access slots on the receiver, not captured lexical variables
    if activation.currentMethod != nil and activation.currentMethod.capturedEnvInitialized and activation.currentMethod.capturedEnv.len > 0 and not activation.currentMethod.isMethod:
      if name in activation.currentMethod.capturedEnv:
        let value = activation.currentMethod.capturedEnv[name].value
        debug("Found variable in captured environment (parent): ", name, " = ", value.toString())
        return (true, value)

    # Check capturedVars (shared cells from child blocks)
    if name in activation.capturedVars:
      let val = activation.capturedVars[name].value
      debug("Found variable in capturedVars (parent): ", name, " = ", val.toString())
      return (true, val)

    # Check locals
    if name in activation.locals:
      debug("Found variable in activation (parent): ", name)
      return (true, activation.locals[name])

    activation = activation.sender

  # Check imported libraries (most recently imported first)
  for i in countdown(interp.importedLibraries.high, 0):
    let lib = interp.importedLibraries[i]
    if lib != nil and lib.kind == ikObject and lib.class == libraryClass:
      let bindingsVal = lib.slots[0]
      if bindingsVal.kind == vkInstance and bindingsVal.instVal != nil and bindingsVal.instVal.kind == ikTable:
        let key = toValue(name)
        if key in bindingsVal.instVal.entries:
          debug("Found variable in imported library: ", name)
          return (true, bindingsVal.instVal.entries[key])

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
  debug("setVariable: name=", name, " activation=", $( interp.currentActivation != nil))

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

    # Check capturedVars on the activation - if a child block captured this
    # variable, update the shared cell so nested blocks see the new value
    if name in interp.currentActivation.capturedVars:
      interp.currentActivation.capturedVars[name].value = value
      interp.currentActivation.locals[name] = value
      debug("setVariable: storing ", name, " in capturedVars cell")
      return

    # Check if variable exists in current activation's locals
    if name in interp.currentActivation.locals:
      debug("setVariable: storing ", name, " in locals")
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

      # Check capturedVars in parent (shared cells from child blocks)
      if name in parentActivation.capturedVars:
        parentActivation.capturedVars[name].value = value
        parentActivation.locals[name] = value
        debug("Variable updated in parent capturedVars: ", name, " = ", value.toString())
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
  # For Smalltalk semantics, non-local return (^) should return from the
  # enclosing method, not the immediately enclosing block. Walk up to find
  # the nearest method activation.
  if interp.currentActivation != nil:
    var act = interp.currentActivation
    while act != nil:
      if act.currentMethod != nil and act.currentMethod.isMethod:
        blockNode.homeActivation = act
        break
      # If the current block already has a homeActivation pointing to a method,
      # inherit it (nested blocks should all return to the same method)
      if act.currentMethod != nil and not act.currentMethod.isMethod and act.currentMethod.homeActivation != nil:
        blockNode.homeActivation = act.currentMethod.homeActivation
        break
      act = act.sender
    if blockNode.homeActivation == nil:
      # Fallback: use current activation (e.g., in top-level scripts)
      blockNode.homeActivation = interp.currentActivation
  debug("Set home activation for non-local returns")

# Method lookup and dispatch
type
  MethodResult* = object
    currentMethod*: BlockNode
    receiver*: Instance         # Instance that received the message
    definingClass*: Class       # class where method was found (for super)
    found*: bool

proc lookupMethod*(interp: Interpreter, receiver: Instance, selector: string): MethodResult =
  ## Look up method in receiver's class using O(1) class lookup
  ## Lazily rebuilds method tables if class is marked dirty
  if receiver == nil or receiver.class == nil:
    debug("Method not found: ", selector, " (receiver or class is nil)")
    return MethodResult(currentMethod: nil, receiver: nil, definingClass: nil, found: false)

  let cls = receiver.class
  debug("Looking up method: '", selector, "' in class: ", cls.name)

  # Lazy rebuild: check if method tables are dirty and rebuild if needed
  if cls.methodsDirty:
    rebuildAllDescendants(cls)
    cls.methodsDirty = false

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
  ## Lazily rebuilds method tables if class is marked dirty
  if cls == nil:
    return MethodResult(currentMethod: nil, receiver: nil, definingClass: nil, found: false)

  # Lazy rebuild: check if method tables are dirty and rebuild if needed
  if cls.methodsDirty:
    rebuildAllDescendants(cls)
    cls.methodsDirty = false

  if selector in cls.allClassMethods:
    return MethodResult(
      currentMethod: cls.allClassMethods[selector],
      receiver: nil,  # Class methods don't have instance receiver
      definingClass: cls,
      found: true
    )
  return MethodResult(currentMethod: nil, receiver: nil, definingClass: nil, found: false)

# Execute a method using the stackless VM
proc executeMethod(interp: var Interpreter, currentMethod: BlockNode,
                  receiver: Instance, arguments: seq[NodeValue],
                  definingClass: Class = nil,
                  isClassMethod: bool = false): NodeValue =
  ## Execute a method with given receiver and already-evaluated arguments
  ## Uses the stackless VM via evalWithVM for execution
  interp.checkStackDepth()

  debug("Executing method with ", arguments.len, " arguments")

  # Check for native implementation first
  if nativeImplIsSet(currentMethod):
      debug("Calling native implementation")
      let savedReceiver = interp.currentReceiver
      try:
        if currentMethod.hasInterpreterParam:
          type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
          let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
          return nativeProc(interp, receiver, arguments)
        else:
          type NativeProc = proc(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
          let nativeProc = cast[NativeProc](currentMethod.nativeImpl)
          return nativeProc(receiver, arguments)
      finally:
        interp.currentReceiver = savedReceiver

  # Create activation and execute via evalWithVM
  debug("Executing interpreted method with ", currentMethod.parameters.len, " parameters")

  if currentMethod.isMethod:
    currentMethod.homeActivation = interp.currentActivation

  let activation = newActivation(currentMethod, receiver, interp.currentActivation, definingClass, isClassMethod)

  if currentMethod.parameters.len != arguments.len:
    raise newException(EvalError,
      "Wrong number of arguments: expected " & $currentMethod.parameters.len &
      ", got " & $arguments.len)

  for i in 0..<currentMethod.parameters.len:
    let paramName = currentMethod.parameters[i]
    let argValue = arguments[i]
    activation.locals[paramName] = argValue

  for tempName in currentMethod.temporaries:
    if tempName notin activation.locals:
      activation.locals[tempName] = nilValue()

  let savedReceiver = interp.currentReceiver
  interp.activationStack.add(activation)
  interp.currentActivation = activation
  interp.currentReceiver = receiver

  var retVal = nilValue()
  try:
    for stmt in currentMethod.body:
      if activation.hasReturned:
        break
      retVal = interp.evalWithVM(stmt)
      if activation.hasReturned:
        break
  finally:
    discard interp.activationStack.pop()
    if interp.activationStack.len > 0:
      interp.currentActivation = interp.activationStack[^1]
      interp.currentReceiver = interp.currentActivation.receiver
    else:
      interp.currentActivation = nil
      interp.currentReceiver = savedReceiver

  if activation.hasReturned:
    return activation.returnValue.unwrap()
  else:
    return retVal.unwrap()

# Block evaluation helpers using the stackless VM
proc evalBlock(interp: var Interpreter, receiver: Instance, blockNode: BlockNode): NodeValue =
  ## Evaluate a block in the context of the given receiver using the stackless VM
  let blockReceiver = if blockNode.homeActivation != nil and
                        blockNode.homeActivation.receiver != nil:
                        blockNode.homeActivation.receiver
                      else:
                        receiver

  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = blockReceiver

  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalWithVM(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue.unwrap()
        break
  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult.unwrap().unwrap()

proc evalBlockWithArg(interp: var Interpreter, receiver: Instance, blockNode: BlockNode, arg: NodeValue): NodeValue =
  ## Evaluate a block with one argument using the stackless VM
  let blockReceiver = if blockNode.homeActivation != nil and
                        blockNode.homeActivation.receiver != nil:
                        blockNode.homeActivation.receiver
                      else:
                        receiver
  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

  if blockNode.parameters.len > 0:
    activation.locals[blockNode.parameters[0]] = arg

  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = blockReceiver

  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalWithVM(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue.unwrap()
        break
  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult

proc evalBlockWithTwoArgs(interp: var Interpreter, receiver: Instance, blockNode: BlockNode, arg1, arg2: NodeValue): (NodeValue, bool) =
  ## Evaluate a block with two arguments using the stackless VM
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
  interp.currentReceiver = blockReceiver

  var blockResult = nilValue()
  var nonLocalReturn = false
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalWithVM(stmt)
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
  ## Evaluate a block with three arguments using the stackless VM
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
  interp.currentReceiver = blockReceiver

  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      blockResult = interp.evalWithVM(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue.unwrap()
        break
  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult

# Invoke a block with arguments using the stackless VM
proc invokeBlock*(interp: var Interpreter, blockNode: BlockNode, args: seq[NodeValue]): NodeValue =
  ## Invoke a block with the given arguments using the stackless VM

  debug("Invoking block with ", args.len, " arguments")

  if blockNode.parameters.len != args.len:
    raise newException(EvalError,
      "Wrong number of arguments to block: expected " & $blockNode.parameters.len &
      ", got " & $args.len)

  let blockHome = blockNode.homeActivation
  let blockReceiver = if blockHome != nil and blockHome.receiver != nil:
                        blockHome.receiver
                      else:
                        interp.currentReceiver
  let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

  var capturedVarNames: seq[string] = @[]

  if isCapturedEnvInitialized(blockNode) and blockNode.capturedEnv.len > 0:
    for name, cell in blockNode.capturedEnv:
      activation.locals[name] = cell.value
      capturedVarNames.add(name)

  for i in 0..<blockNode.parameters.len:
    activation.locals[blockNode.parameters[i]] = args[i]

  for tempName in blockNode.temporaries:
    if tempName notin activation.locals:
      activation.locals[tempName] = nilValue()

  interp.activationStack.add(activation)
  let savedActivation = interp.currentActivation
  let savedReceiver = interp.currentReceiver
  interp.currentActivation = activation
  interp.currentReceiver = blockReceiver

  var blockResult = nilValue()
  try:
    for stmt in blockNode.body:
      if activation.hasReturned:
        blockResult = activation.returnValue
        break
      blockResult = interp.evalWithVM(stmt)
      if activation.hasReturned:
        blockResult = activation.returnValue
        break

    # Save back captured variables to their shared cells
    if capturedVarNames.len > 0:
      for name in capturedVarNames:
        if name in activation.locals and name in blockNode.capturedEnv:
          blockNode.capturedEnv[name].value = activation.locals[name]

    # Also update parent activation's captured variables
    if savedActivation != nil:
      var parent = savedActivation
      while parent != nil:
        for name in capturedVarNames:
          if name in parent.locals and name in activation.locals:
            parent.locals[name] = activation.locals[name]
        parent = parent.sender

  finally:
    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation
    interp.currentReceiver = savedReceiver

  return blockResult.unwrap()

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

# Forward declarations for work frame constructors (defined later in the file)
proc newPushHandlerFrame*(exceptionClass: Class, handlerBlock: BlockNode): WorkFrame
proc newPopHandlerFrame*(): WorkFrame
proc newApplyBlockFrame*(blockVal: BlockNode, argCount: int): WorkFrame
proc newEvalFrame*(node: Node): WorkFrame
proc pushWorkFrame*(interp: var Interpreter, frame: WorkFrame)
proc popValue*(interp: var Interpreter): NodeValue
proc pushValue*(interp: var Interpreter, value: NodeValue)

proc isKindOf(cls: Class, parentClass: Class): bool =
  ## Check if cls is the same as or a subclass of parentClass
  if cls == nil or parentClass == nil:
    return false
  if cls == parentClass:
    return true
  # Walk the superclass chain
  for super in cls.superclasses:
    if isKindOf(super, parentClass):
      return true
  return false

proc primitiveOnDoImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Install exception handler and execute protected block using work queue
  ## Usage: [protectedBlock] on: ExceptionClass do: [:ex | handlerBlock]
  ##
  ## Uses work queue integration, NOT Nim try/finally.
  ## The stackless VM requires all control flow to go through the work queue.
  if args.len < 2:
    return nilValue()

  # Get exception class
  let exceptionClass = if args[0].kind == vkClass: args[0].classVal
                       else: nil

  # Get handler block
  let handlerBlock = if args[1].kind == vkBlock: args[1].blockVal
                     else: nil

  if exceptionClass == nil or handlerBlock == nil:
    return nilValue()

  # Get the protected block (self is a Block instance here)
  if self.kind == ikObject and self.class == blockClass and nimValueIsSet(self.nimValue):
    let blockNode = cast[BlockNode](self.nimValue)

    debug("primitiveOnDo: installing handler for ", exceptionClass.name)

    # Schedule work frames: [pushHandler] -> [evalBlock] -> [popHandler]
    # We push in reverse order (LIFO) so they execute in correct order

    # 3. Pop handler after block completes (pushed first, runs last)
    interp.pushWorkFrame(newPopHandlerFrame())

    # 2. Evaluate the protected block (pushed second, runs middle)
    # Note: if primitiveSignal: is called during block execution,
    # it will search the handler stack and find our handler
    interp.pushWorkFrame(newApplyBlockFrame(blockNode, 0))

    # 1. Push handler onto stack (pushed last, runs first)
    # This schedules the handler push before block execution
    interp.pushWorkFrame(newPushHandlerFrame(exceptionClass, handlerBlock))

    # Return - let VM process the work queue
    # The result will be left on the eval stack by the block execution
    return nilValue()

  return nilValue()

proc primitiveSignalImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Signal/raise an exception - walk handler stack WITHOUT unwinding
  ## Called from Exception>>signal - usage: Exception signal: "message"
  ## Stack remains intact so Debugger can inspect signal point
  ##
  ## self is the Exception instance (not the class)

  # Get message from exception instance if available
  var message = "Exception"
  if self != nil and self.kind == ikObject and self.class != nil:
    # Try to get message from the exception instance
    let messageSlotIdx = self.class.allSlotNames.find("message")
    if messageSlotIdx >= 0 and messageSlotIdx < self.slots.len:
      let msgValue = self.slots[messageSlotIdx]
      if msgValue.kind == vkString:
        message = msgValue.strVal

  # Walk exceptionHandlers stack from top (newest) to bottom
  for i in countdown(interp.exceptionHandlers.len - 1, 0):
    let handler = interp.exceptionHandlers[i]

    # Check if exception isKindOf: handler's exceptionClass
    if isKindOf(self.class, handler.exceptionClass):
      debug("primitiveSignal: found matching handler at index ", i)

      # Unwind VM state to the point where the handler was installed:
      # 1. Truncate work queue - removes all frames from protected block and signal chain
      interp.workQueue.setLen(handler.workQueueDepth)
      debug("primitiveSignal: truncated workQueue to depth ", handler.workQueueDepth)

      # 2. Truncate eval stack - removes intermediate values from protected block
      interp.evalStack.setLen(handler.evalStackDepth)

      # 3. Unwind activation stack to handler's depth
      while interp.activationStack.len > handler.stackDepth:
        discard interp.activationStack.pop()
      if interp.activationStack.len > 0:
        interp.currentActivation = interp.activationStack[^1]
        interp.currentReceiver = interp.currentActivation.receiver

      # 4. Remove the consumed handler (and any handlers above it)
      interp.exceptionHandlers.setLen(i)

      # 5. Schedule handler block with exception as argument
      let exValue = self.toValue()
      debug("primitiveSignal: scheduling handler with exception class=", self.class.name, " value kind=", $exValue.kind)

      var applyFrame = WorkFrame(
        kind: wfApplyBlock,
        blockVal: handler.handlerBlock,
        argCount: 1,
        blockArgs: @[exValue]
      )
      interp.pushWorkFrame(applyFrame)

      # Return nil - the handler block will push its result
      return nilValue()

  # No handler found - for now write to stderr and return nil
  # In full implementation, this would open the Debugger
  debug("primitiveSignal: no handler found for exception")
  writeStderr("Uncaught exception: " & message)
  return nilValue()

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
  ## Check if the receiver responds to a message (both instance and class methods)
  if args.len < 1:
    return falseValue
  let selector = if args[0].kind == vkString: args[0].strVal
                  elif args[0].kind == vkSymbol: args[0].symVal
                  else: ""
  if selector.len == 0:
    return falseValue
  # Check instance methods
  let lookup = lookupMethod(interp, self, selector)
  if lookup.found:
    return trueValue
  # Check class methods (for class objects)
  if self.class != nil:
    let classLookup = lookupClassMethod(self.class, selector)
    if classLookup.found:
      return trueValue
  return falseValue

proc primitiveMethodsImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return the class's method selector names as an array
  var selectors: seq[NodeValue] = @[]
  if self.kind == ikObject and self.class != nil:
    for selector in self.class.allMethods.keys():
      selectors.add(toSymbol(selector))
  return newArrayInstance(arrayClass, selectors).toValue()

proc primitiveAllInstanceMethodsImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return the class's instance method selector names as an array
  var selectors: seq[NodeValue] = @[]
  if self.kind == ikObject and self.class != nil:
    for selector in self.class.allMethods.keys():
      selectors.add(toSymbol(selector))
  return newArrayInstance(arrayClass, selectors).toValue()

proc primitiveAllClassMethodsImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return the class's class method selector names as an array
  var selectors: seq[NodeValue] = @[]
  if self.kind == ikObject and self.class != nil:
    for selector in self.class.allClassMethods.keys():
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

# Set iteration primitive (needs interpreter for block evaluation)
proc primitiveSetDoImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Iterate over all elements in the set
  if self.kind == ikObject and self.slots.len > 0:
    let elementsVal = self.slots[0]
    if elementsVal.kind == vkInstance and elementsVal.instVal != nil and elementsVal.instVal.kind == ikTable:
      if args.len == 0:
        return nilValue()
      let blockVal = args[0]
      if blockVal.kind != vkInstance or blockVal.instVal.class != blockClass:
        return nilValue()
      let theBlock = cast[BlockNode](blockVal.instVal.nimValue)
      for key in elementsVal.instVal.entries.keys():
        discard evalBlockWithArg(interp, interp.currentReceiver, theBlock, key)
      return nilValue()
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
  addSuperclassMethod.setNativeImpl(addSuperclassImpl)
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
  classNewMethod.setNativeImpl(objectClassNewImpl)
  classNewMethod.hasInterpreterParam = true
  objectCls.classMethods["new"] = classNewMethod
  objectCls.allClassMethods["new"] = classNewMethod

  # Register Object class>>basicNew - creates instance without calling initialize
  # This is the primitive that 'new' uses after creating the instance
  proc objectClassBasicNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    # self.class is the class receiving the message
    if self != nil and self.class != nil:
      return newInstance(self.class).toValue()
    return newInstance(objectClass).toValue()

  let classBasicNewMethod = createCoreMethod("basicNew")
  classBasicNewMethod.setNativeImpl(objectClassBasicNewImpl)
  classBasicNewMethod.hasInterpreterParam = true
  objectCls.classMethods["basicNew"] = classBasicNewMethod
  objectCls.allClassMethods["basicNew"] = classBasicNewMethod
  # Also register primitiveBasicNew for <primitive> syntax
  objectCls.classMethods["primitiveBasicNew"] = classBasicNewMethod
  objectCls.allClassMethods["primitiveBasicNew"] = classBasicNewMethod

  # Add perform: methods to Object class (for primitive dispatch from Smalltalk)
  let objPerformMethod = createCoreMethod("perform:")
  objPerformMethod.setNativeImpl(performWithImpl)
  objPerformMethod.hasInterpreterParam = true
  objectCls.methods["perform:"] = objPerformMethod
  objectCls.allMethods["perform:"] = objPerformMethod

  let objPerformWithMethod = createCoreMethod("perform:with:")
  objPerformWithMethod.setNativeImpl(performWithImpl)
  objPerformWithMethod.hasInterpreterParam = true
  objectCls.methods["perform:with:"] = objPerformWithMethod
  objectCls.allMethods["perform:with:"] = objPerformWithMethod

  let objPerformWithWithMethod = createCoreMethod("perform:with:with:")
  objPerformWithWithMethod.setNativeImpl(performWithImpl)
  objPerformWithWithMethod.hasInterpreterParam = true
  objectCls.methods["perform:with:with:"] = objPerformWithWithMethod
  objectCls.allMethods["perform:with:with:"] = objPerformWithWithMethod

  # Register primitivePerform: selectors for Object.hrd <primitive> syntax
  objectCls.methods["primitivePerform:"] = objPerformMethod
  objectCls.allMethods["primitivePerform:"] = objPerformMethod
  objectCls.methods["primitivePerform:with:"] = objPerformWithMethod
  objectCls.allMethods["primitivePerform:with:"] = objPerformWithMethod
  objectCls.methods["primitivePerform:with:with:"] = objPerformWithWithMethod
  objectCls.allMethods["primitivePerform:with:with:"] = objPerformWithWithMethod

  # Add primitiveIdentity: for == comparison
  let objIdentityMethod = createCoreMethod("primitiveIdentity:")
  objIdentityMethod.setNativeImpl(instIdentityImpl)
  objectCls.methods["primitiveIdentity:"] = objIdentityMethod
  objectCls.allMethods["primitiveIdentity:"] = objIdentityMethod

  # Add primitiveAsSelfDo: for asSelfDo: implementation (as both instance and class method)
  let objAsSelfDoMethod = createCoreMethod("primitiveAsSelfDo:")
  objAsSelfDoMethod.setNativeImpl(primitiveAsSelfDoImpl)
  objAsSelfDoMethod.hasInterpreterParam = true
  # Register as instance method on Object (for instances)
  objectCls.methods["primitiveAsSelfDo:"] = objAsSelfDoMethod
  objectCls.allMethods["primitiveAsSelfDo:"] = objAsSelfDoMethod
  # Also register as class method on Object (for class receivers/extend usage)
  objectCls.classMethods["primitiveAsSelfDo:"] = objAsSelfDoMethod
  objectCls.allClassMethods["primitiveAsSelfDo:"] = objAsSelfDoMethod

  # Add primitiveHasProperty: for hasProperty: implementation
  let objHasPropertyMethod = createCoreMethod("primitiveHasProperty:")
  objHasPropertyMethod.setNativeImpl(primitiveHasPropertyImpl)
  objHasPropertyMethod.hasInterpreterParam = true
  objectCls.methods["primitiveHasProperty:"] = objHasPropertyMethod
  objectCls.allMethods["primitiveHasProperty:"] = objHasPropertyMethod

  # Add primitiveProperties for properties implementation
  let objPropertiesMethod = createCoreMethod("primitiveProperties")
  objPropertiesMethod.setNativeImpl(primitivePropertiesImpl)
  objPropertiesMethod.hasInterpreterParam = true
  objectCls.methods["primitiveProperties"] = objPropertiesMethod
  objectCls.allMethods["primitiveProperties"] = objPropertiesMethod

  # Add primitiveRespondsTo: for respondsTo: implementation
  let objRespondsToMethod = createCoreMethod("primitiveRespondsTo:")
  objRespondsToMethod.setNativeImpl(primitiveRespondsToImpl)
  objRespondsToMethod.hasInterpreterParam = true
  objectCls.methods["primitiveRespondsTo:"] = objRespondsToMethod
  objectCls.allMethods["primitiveRespondsTo:"] = objRespondsToMethod

  # Add primitiveMethods for methods implementation
  let objMethodsMethod = createCoreMethod("primitiveMethods")
  objMethodsMethod.setNativeImpl(primitiveMethodsImpl)
  objMethodsMethod.hasInterpreterParam = true
  objectCls.methods["primitiveMethods"] = objMethodsMethod
  objectCls.allMethods["primitiveMethods"] = objMethodsMethod

  # Add primitiveAllInstanceMethods for allInstanceMethods implementation
  let objAllInstanceMethodsMethod = createCoreMethod("primitiveAllInstanceMethods")
  objAllInstanceMethodsMethod.setNativeImpl(primitiveAllInstanceMethodsImpl)
  objAllInstanceMethodsMethod.hasInterpreterParam = true
  objectCls.methods["primitiveAllInstanceMethods"] = objAllInstanceMethodsMethod
  objectCls.allMethods["primitiveAllInstanceMethods"] = objAllInstanceMethodsMethod

  # Add primitiveAllClassMethods for allClassMethods implementation
  let objAllClassMethodsMethod = createCoreMethod("primitiveAllClassMethods")
  objAllClassMethodsMethod.setNativeImpl(primitiveAllClassMethodsImpl)
  objAllClassMethodsMethod.hasInterpreterParam = true
  objectCls.methods["primitiveAllClassMethods"] = objAllClassMethodsMethod
  objectCls.allMethods["primitiveAllClassMethods"] = objAllClassMethodsMethod

  # Add primitiveClass for class implementation
  let objClassMethod = createCoreMethod("primitiveClass")
  objClassMethod.setNativeImpl(classImpl)
  objectCls.methods["primitiveClass"] = objClassMethod
  objectCls.allMethods["primitiveClass"] = objClassMethod
  objectCls.allMethods["primitiveMethods"] = objMethodsMethod

  # Add primitiveError: for error: implementation
  let objErrorMethod = createCoreMethod("primitiveError:")
  objErrorMethod.setNativeImpl(primitiveErrorImpl)
  objErrorMethod.hasInterpreterParam = true
  objectCls.methods["primitiveError:"] = objErrorMethod
  objectCls.allMethods["primitiveError:"] = objErrorMethod

  # Add primitiveEquals: for == implementation
  let objEqualsMethod = createCoreMethod("primitiveEquals:")
  objEqualsMethod.setNativeImpl(primitiveEqualsImpl)
  objectCls.methods["primitiveEquals:"] = objEqualsMethod
  objectCls.allMethods["primitiveEquals:"] = objEqualsMethod

  # Add primitiveIsKindOf: for isKindOf: implementation
  let objIsKindOfMethod = createCoreMethod("primitiveIsKindOf:")
  objIsKindOfMethod.setNativeImpl(primitiveIsKindOfImpl)
  objIsKindOfMethod.hasInterpreterParam = true
  objectCls.methods["primitiveIsKindOf:"] = objIsKindOfMethod
  objectCls.allMethods["primitiveIsKindOf:"] = objIsKindOfMethod

  # Add slotNames for class introspection - returns slot names of this class
  let objSlotNamesMethod = createCoreMethod("slotNames")
  objSlotNamesMethod.setNativeImpl(primitiveSlotNamesImpl)
  objSlotNamesMethod.hasInterpreterParam = true
  objectCls.methods["slotNames"] = objSlotNamesMethod
  objectCls.allMethods["slotNames"] = objSlotNamesMethod
  # Also register with primitiveSlotNames for <primitive: #primitiveSlotNames> syntax
  objectCls.methods["primitiveSlotNames"] = objSlotNamesMethod
  objectCls.allMethods["primitiveSlotNames"] = objSlotNamesMethod

  # Add superclassNames for class introspection - returns names of superclasses
  let objSuperclassNamesMethod = createCoreMethod("superclassNames")
  objSuperclassNamesMethod.setNativeImpl(primitiveSuperclassNamesImpl)
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
  classNameMethod.setNativeImpl(primitiveClassNameImpl)
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
  # Add "name" alias for class-side (Object class>>name in Object.hrd uses primitiveClassName)
  objectCls.classMethods["name"] = classNameMethod
  objectCls.allClassMethods["name"] = classNameMethod

  # Add isClass method to Object - returns true if self is a Class object
  proc primitiveIsClassImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    # Check if self is a Class object (like Object, String, Number, etc.)
    # Class objects are ikObject instances with 0 slots (they don't have instance variables)
    # Regular instances have slots defined by their class.
    #
    # When a Class (vkClass) is wrapped as an Instance, it becomes an ikObject
    # with 0 slots because classes don't have instance slots in this system.
    # When a regular instance is created, it has slots as defined by its class.
    #
    # So the check is: ikObject with 0 slots = likely a class object
    if self.kind == ikObject and self.slots.len == 0:
      return trueValue
    return falseValue

  let isClassMethod = createCoreMethod("isClass")
  isClassMethod.setNativeImpl(primitiveIsClassImpl)
  isClassMethod.hasInterpreterParam = true
  objectCls.methods["isClass"] = isClassMethod
  objectCls.allMethods["isClass"] = isClassMethod
  # Also add primitiveIsClass for <primitive: #primitiveIsClass> syntax
  objectCls.methods["primitiveIsClass"] = isClassMethod
  objectCls.allMethods["primitiveIsClass"] = isClassMethod

  # Add print and println as native methods
  proc objPrintImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    # Print self to stdout without newline
    let s = self.toValue().toString()
    stdout.write(s)
    return self.toValue()

  proc objPrintlnImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    # Print self to stdout with newline
    let s = self.toValue().toString()
    echo(s)
    return self.toValue()

  let printMethod = createCoreMethod("print")
  printMethod.setNativeImpl(objPrintImpl)
  objectCls.methods["print"] = printMethod
  objectCls.allMethods["print"] = printMethod

  let printlnMethod = createCoreMethod("println")
  printlnMethod.setNativeImpl(objPrintlnImpl)
  objectCls.methods["println"] = printlnMethod
  objectCls.allMethods["println"] = printlnMethod

  # Add eval class primitive for evaluating code strings
  proc primitiveEvalImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
    ## Evaluate a Harding code string and return the result
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
  evalMethod.setNativeImpl(primitiveEvalImpl)
  evalMethod.hasInterpreterParam = true
  objectCls.classMethods["eval:"] = evalMethod
  objectCls.allClassMethods["eval:"] = evalMethod
  # Also register as primitiveEval: for declarative syntax
  objectCls.classMethods["primitiveEval:"] = evalMethod
  objectCls.allClassMethods["primitiveEval:"] = evalMethod

  # Create Number class (derives from Object)
  # Number is an abstract class; methods are defined in .hrd files
  let numberCls = newClass(superclasses = @[objectCls], name = "Number")
  numberCls.tags = @["Number"]

  # Create Integer class (derives from Number)
  # Methods are defined in lib/core/Integer.hrd using <primitive> syntax
  let intCls = newClass(superclasses = @[numberCls], name = "Integer")
  intCls.tags = @["Integer", "Number"]
  integerClass = intCls

  # Create Float class (derives from Number)
  # Methods are defined in lib/core/Float.hrd using <primitive> syntax
  let floatCls = newClass(superclasses = @[numberCls], name = "Float")
  floatCls.tags = @["Float", "Number"]
  floatClass = floatCls

  # Create String class (derives from Object)
  let stringCls = newClass(superclasses = @[objectCls], name = "String")
  stringCls.tags = @["String", "Text"]
  stringClass = stringCls

  # Register String primitive methods
  let stringConcatMethod = createCoreMethod("primitiveConcat:")
  stringConcatMethod.setNativeImpl(instStringConcatImpl)
  stringCls.methods["primitiveConcat:"] = stringConcatMethod
  stringCls.allMethods["primitiveConcat:"] = stringConcatMethod

  let stringSizeMethod = createCoreMethod("primitiveStringSize")
  stringSizeMethod.setNativeImpl(instStringSizeImpl)
  stringCls.methods["primitiveStringSize"] = stringSizeMethod
  stringCls.allMethods["primitiveStringSize"] = stringSizeMethod

  let stringAtMethod = createCoreMethod("primitiveStringAt:")
  stringAtMethod.setNativeImpl(instStringAtImpl)
  stringCls.methods["primitiveStringAt:"] = stringAtMethod
  stringCls.allMethods["primitiveStringAt:"] = stringAtMethod

  let stringSplitMethod = createCoreMethod("primitiveSplit:")
  stringSplitMethod.setNativeImpl(instStringSplitImpl)
  stringCls.methods["primitiveSplit:"] = stringSplitMethod
  stringCls.allMethods["primitiveSplit:"] = stringSplitMethod

  # Register Instance-based String primitives
  let stringLowercaseMethod = createCoreMethod("primitiveLowercase")
  stringLowercaseMethod.setNativeImpl(instStringLowercaseImpl)
  stringCls.methods["primitiveLowercase"] = stringLowercaseMethod
  stringCls.allMethods["primitiveLowercase"] = stringLowercaseMethod

  let stringUppercaseMethod = createCoreMethod("primitiveUppercase")
  stringUppercaseMethod.setNativeImpl(instStringUppercaseImpl)
  stringCls.methods["primitiveUppercase"] = stringUppercaseMethod
  stringCls.allMethods["primitiveUppercase"] = stringUppercaseMethod

  let stringTrimMethod = createCoreMethod("primitiveTrim")
  stringTrimMethod.setNativeImpl(instStringTrimImpl)
  stringCls.methods["primitiveTrim"] = stringTrimMethod
  stringCls.allMethods["primitiveTrim"] = stringTrimMethod

  let stringFromToMethod = createCoreMethod("primitiveFromTo:")
  stringFromToMethod.setNativeImpl(instStringFromToImpl)
  stringCls.methods["primitiveFromTo:"] = stringFromToMethod
  stringCls.allMethods["primitiveFromTo:"] = stringFromToMethod

  let stringIndexOfMethod = createCoreMethod("primitiveIndexOf:")
  stringIndexOfMethod.setNativeImpl(instStringIndexOfImpl)
  stringCls.methods["primitiveIndexOf:"] = stringIndexOfMethod
  stringCls.allMethods["primitiveIndexOf:"] = stringIndexOfMethod

  let stringIncludesSubStringMethod = createCoreMethod("primitiveIncludesSubString:")
  stringIncludesSubStringMethod.setNativeImpl(instStringIncludesSubStringImpl)
  stringCls.methods["primitiveIncludesSubString:"] = stringIncludesSubStringMethod
  stringCls.allMethods["primitiveIncludesSubString:"] = stringIncludesSubStringMethod

  let stringReplaceWithMethod = createCoreMethod("primitiveReplaceWith:")
  stringReplaceWithMethod.setNativeImpl(instStringReplaceWithImpl)
  stringCls.methods["primitiveReplaceWith:"] = stringReplaceWithMethod
  stringCls.allMethods["primitiveReplaceWith:"] = stringReplaceWithMethod

  let stringAsIntegerMethod = createCoreMethod("primitiveAsInteger")
  stringAsIntegerMethod.setNativeImpl(instStringAsIntegerImpl)
  stringCls.methods["primitiveAsInteger"] = stringAsIntegerMethod
  stringCls.allMethods["primitiveAsInteger"] = stringAsIntegerMethod

  let stringAsSymbolMethod = createCoreMethod("primitiveAsSymbol")
  stringAsSymbolMethod.setNativeImpl(instStringAsSymbolImpl)
  stringCls.methods["primitiveAsSymbol"] = stringAsSymbolMethod
  stringCls.allMethods["primitiveAsSymbol"] = stringAsSymbolMethod

  let stringRepeatMethod = createCoreMethod("primitiveRepeat:")
  stringRepeatMethod.setNativeImpl(instStringRepeatImpl)
  stringCls.methods["primitiveRepeat:"] = stringRepeatMethod
  stringCls.allMethods["primitiveRepeat:"] = stringRepeatMethod

  # ============================================================================
  # Register Integer primitive selectors (used by lib/core/Integer.hrd)
  # ============================================================================

  # Register Integer arithmetic primitives
  let intPlusMethod = createCoreMethod("primitivePlus:")
  intPlusMethod.setNativeImpl(plusImpl)
  intCls.methods["primitivePlus:"] = intPlusMethod
  intCls.allMethods["primitivePlus:"] = intPlusMethod

  let intMinusMethod = createCoreMethod("primitiveMinus:")
  intMinusMethod.setNativeImpl(minusImpl)
  intCls.methods["primitiveMinus:"] = intMinusMethod
  intCls.allMethods["primitiveMinus:"] = intMinusMethod

  let intTimesMethod = createCoreMethod("primitiveTimes:")
  intTimesMethod.setNativeImpl(starImpl)
  intCls.methods["primitiveTimes:"] = intTimesMethod
  intCls.allMethods["primitiveTimes:"] = intTimesMethod

  let intDivideMethod = createCoreMethod("primitiveDivide:")
  intDivideMethod.setNativeImpl(slashImpl)
  intCls.methods["primitiveDivide:"] = intDivideMethod
  intCls.allMethods["primitiveDivide:"] = intDivideMethod

  let intIntDivMethod = createCoreMethod("primitiveIntDiv:")
  intIntDivMethod.setNativeImpl(intDivImpl)
  intCls.methods["primitiveIntDiv:"] = intIntDivMethod
  intCls.allMethods["primitiveIntDiv:"] = intIntDivMethod

  # Register Integer comparison primitives
  let intLessThanMethod = createCoreMethod("primitiveLessThan:")
  intLessThanMethod.setNativeImpl(ltImpl)
  intCls.methods["primitiveLessThan:"] = intLessThanMethod
  intCls.allMethods["primitiveLessThan:"] = intLessThanMethod

  let intGreaterThanMethod = createCoreMethod("primitiveGreaterThan:")
  intGreaterThanMethod.setNativeImpl(gtImpl)
  intCls.methods["primitiveGreaterThan:"] = intGreaterThanMethod
  intCls.allMethods["primitiveGreaterThan:"] = intGreaterThanMethod

  let intEqualsMethod = createCoreMethod("primitiveEquals:")
  intEqualsMethod.setNativeImpl(eqImpl)
  intCls.methods["primitiveEquals:"] = intEqualsMethod
  intCls.allMethods["primitiveEquals:"] = intEqualsMethod

  let intLessOrEqMethod = createCoreMethod("primitiveLessOrEq:")
  intLessOrEqMethod.setNativeImpl(leImpl)
  intCls.methods["primitiveLessOrEq:"] = intLessOrEqMethod
  intCls.allMethods["primitiveLessOrEq:"] = intLessOrEqMethod

  let intGreaterOrEqMethod = createCoreMethod("primitiveGreaterOrEq:")
  intGreaterOrEqMethod.setNativeImpl(geImpl)
  intCls.methods["primitiveGreaterOrEq:"] = intGreaterOrEqMethod
  intCls.allMethods["primitiveGreaterOrEq:"] = intGreaterOrEqMethod

  let intNotEqualsMethod = createCoreMethod("primitiveNotEquals:")
  intNotEqualsMethod.setNativeImpl(neImpl)
  intCls.methods["primitiveNotEquals:"] = intNotEqualsMethod
  intCls.allMethods["primitiveNotEquals:"] = intNotEqualsMethod

  # Register Integer other primitives
  let intSqrtMethod = createCoreMethod("primitiveSqrt")
  intSqrtMethod.setNativeImpl(sqrtImpl)
  intCls.methods["primitiveSqrt"] = intSqrtMethod
  intCls.allMethods["primitiveSqrt"] = intSqrtMethod

  let intPrintStringMethod = createCoreMethod("primitivePrintString")
  intPrintStringMethod.setNativeImpl(printStringImpl)
  intCls.methods["primitivePrintString"] = intPrintStringMethod
  intCls.allMethods["primitivePrintString"] = intPrintStringMethod

  let intBackslashModuloMethod = createCoreMethod("primitiveBackslashModulo:")
  intBackslashModuloMethod.setNativeImpl(backslashModuloImpl)
  intCls.methods["primitiveBackslashModulo:"] = intBackslashModuloMethod
  intCls.allMethods["primitiveBackslashModulo:"] = intBackslashModuloMethod

  # ============================================================================
  # Register Float primitive selectors (used by lib/core/Float.hrd)
  # Float uses the same primitive implementations as Integer
  # ============================================================================

  # Register Float arithmetic primitives
  let floatPlusMethod = createCoreMethod("primitivePlus:")
  floatPlusMethod.setNativeImpl(plusImpl)
  floatCls.methods["primitivePlus:"] = floatPlusMethod
  floatCls.allMethods["primitivePlus:"] = floatPlusMethod

  let floatMinusMethod = createCoreMethod("primitiveMinus:")
  floatMinusMethod.setNativeImpl(minusImpl)
  floatCls.methods["primitiveMinus:"] = floatMinusMethod
  floatCls.allMethods["primitiveMinus:"] = floatMinusMethod

  let floatTimesMethod = createCoreMethod("primitiveTimes:")
  floatTimesMethod.setNativeImpl(starImpl)
  floatCls.methods["primitiveTimes:"] = floatTimesMethod
  floatCls.allMethods["primitiveTimes:"] = floatTimesMethod

  let floatDivideMethod = createCoreMethod("primitiveDivide:")
  floatDivideMethod.setNativeImpl(slashImpl)
  floatCls.methods["primitiveDivide:"] = floatDivideMethod
  floatCls.allMethods["primitiveDivide:"] = floatDivideMethod

  # Register Float comparison primitives
  let floatLessThanMethod = createCoreMethod("primitiveLessThan:")
  floatLessThanMethod.setNativeImpl(ltImpl)
  floatCls.methods["primitiveLessThan:"] = floatLessThanMethod
  floatCls.allMethods["primitiveLessThan:"] = floatLessThanMethod

  let floatGreaterThanMethod = createCoreMethod("primitiveGreaterThan:")
  floatGreaterThanMethod.setNativeImpl(gtImpl)
  floatCls.methods["primitiveGreaterThan:"] = floatGreaterThanMethod
  floatCls.allMethods["primitiveGreaterThan:"] = floatGreaterThanMethod

  let floatEqualsMethod = createCoreMethod("primitiveEquals:")
  floatEqualsMethod.setNativeImpl(eqImpl)
  floatCls.methods["primitiveEquals:"] = floatEqualsMethod
  floatCls.allMethods["primitiveEquals:"] = floatEqualsMethod

  let floatLessOrEqMethod = createCoreMethod("primitiveLessOrEq:")
  floatLessOrEqMethod.setNativeImpl(leImpl)
  floatCls.methods["primitiveLessOrEq:"] = floatLessOrEqMethod
  floatCls.allMethods["primitiveLessOrEq:"] = floatLessOrEqMethod

  let floatGreaterOrEqMethod = createCoreMethod("primitiveGreaterOrEq:")
  floatGreaterOrEqMethod.setNativeImpl(geImpl)
  floatCls.methods["primitiveGreaterOrEq:"] = floatGreaterOrEqMethod
  floatCls.allMethods["primitiveGreaterOrEq:"] = floatGreaterOrEqMethod

  let floatNotEqualsMethod = createCoreMethod("primitiveNotEquals:")
  floatNotEqualsMethod.setNativeImpl(neImpl)
  floatCls.methods["primitiveNotEquals:"] = floatNotEqualsMethod
  floatCls.allMethods["primitiveNotEquals:"] = floatNotEqualsMethod

  # Register Float other primitives
  let floatSqrtMethod = createCoreMethod("primitiveSqrt")
  floatSqrtMethod.setNativeImpl(sqrtImpl)
  floatCls.methods["primitiveSqrt"] = floatSqrtMethod
  floatCls.allMethods["primitiveSqrt"] = floatSqrtMethod

  let floatPrintStringMethod = createCoreMethod("primitivePrintString")
  floatPrintStringMethod.setNativeImpl(printStringImpl)
  floatCls.methods["primitivePrintString"] = floatPrintStringMethod
  floatCls.allMethods["primitivePrintString"] = floatPrintStringMethod

  let floatBackslashModuloMethod = createCoreMethod("primitiveBackslashModulo:")
  floatBackslashModuloMethod.setNativeImpl(backslashModuloImpl)
  floatCls.methods["primitiveBackslashModulo:"] = floatBackslashModuloMethod
  floatCls.allMethods["primitiveBackslashModulo:"] = floatBackslashModuloMethod

  # Note: User-facing methods (+, -, *, /, =, <, //, \\, printString) are now defined in .hrd files:
  #   lib/core/Integer.hrd, lib/core/Float.hrd
  # These use <primitive selector> syntax which dispatches to the primitive selectors above.

  # Use existing Array class from initCoreClasses or create if needed
  var arrayCls: Class
  if arrayClass != nil:
    arrayCls = arrayClass
  else:
    arrayCls = newClass(superclasses = @[objectCls], name = "Array")
    arrayCls.tags = @["Array", "Collection"]
    arrayClass = arrayCls

  # Register Array primitive selectors (used by lib/core/Array.hrd)
  let arraySizeMethod = createCoreMethod("primitiveArraySize")
  arraySizeMethod.setNativeImpl(arraySizeImpl)
  arrayCls.methods["primitiveArraySize"] = arraySizeMethod
  arrayCls.allMethods["primitiveArraySize"] = arraySizeMethod

  let arrayAtMethod = createCoreMethod("primitiveArrayAt:")
  arrayAtMethod.setNativeImpl(arrayAtImpl)
  arrayCls.methods["primitiveArrayAt:"] = arrayAtMethod
  arrayCls.allMethods["primitiveArrayAt:"] = arrayAtMethod

  let arrayAtPutMethod = createCoreMethod("primitiveArrayAt:put:")
  arrayAtPutMethod.setNativeImpl(arrayAtPutImpl)
  arrayCls.methods["primitiveArrayAt:put:"] = arrayAtPutMethod
  arrayCls.allMethods["primitiveArrayAt:put:"] = arrayAtPutMethod

  let arrayAddMethod = createCoreMethod("primitiveArrayAdd:")
  arrayAddMethod.setNativeImpl(arrayAddImpl)
  arrayCls.methods["primitiveArrayAdd:"] = arrayAddMethod
  arrayCls.allMethods["primitiveArrayAdd:"] = arrayAddMethod

  let arrayRemoveAtMethod = createCoreMethod("primitiveArrayRemoveAt:")
  arrayRemoveAtMethod.setNativeImpl(arrayRemoveAtImpl)
  arrayCls.methods["primitiveArrayRemoveAt:"] = arrayRemoveAtMethod
  arrayCls.allMethods["primitiveArrayRemoveAt:"] = arrayRemoveAtMethod

  let arrayIncludesMethod = createCoreMethod("primitiveArrayIncludes:")
  arrayIncludesMethod.setNativeImpl(arrayIncludesImpl)
  arrayCls.methods["primitiveArrayIncludes:"] = arrayIncludesMethod
  arrayCls.allMethods["primitiveArrayIncludes:"] = arrayIncludesMethod

  let arrayReverseMethod = createCoreMethod("primitiveArrayReverse")
  arrayReverseMethod.setNativeImpl(arrayReverseImpl)
  arrayCls.methods["primitiveArrayReverse"] = arrayReverseMethod
  arrayCls.allMethods["primitiveArrayReverse"] = arrayReverseMethod

  let arrayDoMethod = createCoreMethod("primitiveDo:")
  arrayDoMethod.setNativeImpl(arrayDoImpl)
  arrayDoMethod.hasInterpreterParam = true
  arrayCls.methods["primitiveDo:"] = arrayDoMethod
  arrayCls.allMethods["primitiveDo:"] = arrayDoMethod

  # Register Array class new method
  proc arrayClassNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    # Create an Array instance
    var elements: seq[NodeValue] = @[]
    if args.len > 0:
      let (ok, size) = args[0].tryGetInt()
      if ok:
        for i in 0..<size:
          elements.add(nilValue())
    let inst = newArrayInstance(arrayClass, elements)
    return NodeValue(kind: vkInstance, instVal: inst)

  let arrayNewMethod = createCoreMethod("primitiveArrayNew")
  arrayNewMethod.setNativeImpl(arrayClassNewImpl)
  arrayNewMethod.hasInterpreterParam = true
  arrayCls.classMethods["primitiveArrayNew"] = arrayNewMethod
  arrayCls.allClassMethods["primitiveArrayNew"] = arrayNewMethod

  let arrayNewSizeMethod = createCoreMethod("primitiveArrayNew:")
  arrayNewSizeMethod.setNativeImpl(arrayClassNewImpl)
  arrayNewSizeMethod.hasInterpreterParam = true
  arrayCls.classMethods["primitiveArrayNew:"] = arrayNewSizeMethod
  arrayCls.allClassMethods["primitiveArrayNew:"] = arrayNewSizeMethod

  # Use existing Table class from initCoreClasses or create if needed
  var tableCls: Class
  if tableClass != nil:
    tableCls = tableClass
  else:
    tableCls = newClass(superclasses = @[objectCls], name = "Table")
    tableCls.tags = @["Table", "Dictionary", "Collection"]
    tableClass = tableCls

  # Register Table primitive selectors (used by lib/core/Table.hrd)
  let tableAtMethod = createCoreMethod("primitiveTableAt:")
  tableAtMethod.setNativeImpl(tableAtImpl)
  tableCls.methods["primitiveTableAt:"] = tableAtMethod
  tableCls.allMethods["primitiveTableAt:"] = tableAtMethod

  let tableAtPutMethod = createCoreMethod("primitiveTableAt:put:")
  tableAtPutMethod.setNativeImpl(tableAtPutImpl)
  tableCls.methods["primitiveTableAt:put:"] = tableAtPutMethod
  tableCls.allMethods["primitiveTableAt:put:"] = tableAtPutMethod

  let tableKeysMethod = createCoreMethod("primitiveKeys")
  tableKeysMethod.setNativeImpl(tableKeysImpl)
  tableCls.methods["primitiveKeys"] = tableKeysMethod
  tableCls.allMethods["primitiveKeys"] = tableKeysMethod

  let tableIncludesKeyMethod = createCoreMethod("primitiveIncludesKey:")
  tableIncludesKeyMethod.setNativeImpl(tableIncludesKeyImpl)
  tableCls.methods["primitiveIncludesKey:"] = tableIncludesKeyMethod
  tableCls.allMethods["primitiveIncludesKey:"] = tableIncludesKeyMethod

  let tableRemoveKeyMethod = createCoreMethod("primitiveRemoveKey:")
  tableRemoveKeyMethod.setNativeImpl(tableRemoveKeyImpl)
  tableCls.methods["primitiveRemoveKey:"] = tableRemoveKeyMethod
  tableCls.allMethods["primitiveRemoveKey:"] = tableRemoveKeyMethod

  # Register Table class new method (creates ikTable instance)
  # This is needed because Table new creates ikTable instances, not ikObject
  proc tableClassNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    # Create a Table instance with ikTable kind (not ikObject)
    # self.class is the class receiving the message (e.g., Table or a subclass)
    let targetClass = if self != nil and self.class != nil: self.class else: tableClass
    return newTableInstance(targetClass, initTable[NodeValue, NodeValue]()).toValue()

  let tableNewMethod = createCoreMethod("new")
  tableNewMethod.setNativeImpl(tableClassNewImpl)
  tableNewMethod.hasInterpreterParam = true
  tableCls.classMethods["new"] = tableNewMethod
  tableCls.allClassMethods["new"] = tableNewMethod
  # Also register primitiveTableNew for <primitive> syntax
  tableCls.classMethods["primitiveTableNew"] = tableNewMethod
  tableCls.allClassMethods["primitiveTableNew"] = tableNewMethod

  # ============================================================================
  # Register Library primitive selectors (used by lib/core/Library.hrd)
  # ============================================================================
  # Use existing Library class from initCoreClasses
  var libraryCls: Class
  if libraryClass != nil:
    libraryCls = libraryClass
  else:
    libraryCls = newClass(superclasses = @[objectCls],
                          slotNames = @["bindings", "imports", "name"],
                          name = "Library")
    libraryCls.tags = @["Library", "Namespace"]
    libraryClass = libraryCls

  # Register Library instance primitives (at:, at:put:, keys, etc.)
  let libraryAtMethod = createCoreMethod("primitiveLibraryAt:")
  libraryAtMethod.setNativeImpl(libraryAtImpl)
  libraryCls.methods["primitiveLibraryAt:"] = libraryAtMethod
  libraryCls.allMethods["primitiveLibraryAt:"] = libraryAtMethod

  let libraryAtPutMethod = createCoreMethod("primitiveLibraryAt:put:")
  libraryAtPutMethod.setNativeImpl(libraryAtPutImpl)
  libraryCls.methods["primitiveLibraryAt:put:"] = libraryAtPutMethod
  libraryCls.allMethods["primitiveLibraryAt:put:"] = libraryAtPutMethod

  let libraryKeysMethod = createCoreMethod("primitiveLibraryKeys")
  libraryKeysMethod.setNativeImpl(libraryKeysImpl)
  libraryCls.methods["primitiveLibraryKeys"] = libraryKeysMethod
  libraryCls.allMethods["primitiveLibraryKeys"] = libraryKeysMethod

  let libraryIncludesKeyMethod = createCoreMethod("primitiveLibraryIncludesKey:")
  libraryIncludesKeyMethod.setNativeImpl(libraryIncludesKeyImpl)
  libraryCls.methods["primitiveLibraryIncludesKey:"] = libraryIncludesKeyMethod
  libraryCls.allMethods["primitiveLibraryIncludesKey:"] = libraryIncludesKeyMethod

  let libraryNameMethod = createCoreMethod("primitiveLibraryName")
  libraryNameMethod.setNativeImpl(libraryNameImpl)
  libraryCls.methods["primitiveLibraryName"] = libraryNameMethod
  libraryCls.allMethods["primitiveLibraryName"] = libraryNameMethod

  let libraryNameSetMethod = createCoreMethod("primitiveLibraryName:")
  libraryNameSetMethod.setNativeImpl(libraryNameSetImpl)
  libraryCls.methods["primitiveLibraryName:"] = libraryNameSetMethod
  libraryCls.allMethods["primitiveLibraryName:"] = libraryNameSetMethod

  # Register primitiveLibraryBindings for bindings slot access
  let libraryBindingsMethod = createCoreMethod("primitiveLibraryBindings")
  libraryBindingsMethod.setNativeImpl(libraryBindingsImpl)
  libraryCls.methods["primitiveLibraryBindings"] = libraryBindingsMethod
  libraryCls.allMethods["primitiveLibraryBindings"] = libraryBindingsMethod

  # Register Library class new method (as class method primitive)
  let libraryNewPrimMethod = createCoreMethod("primitiveLibraryNew")
  libraryNewPrimMethod.setNativeImpl(libraryNewImpl)
  libraryNewPrimMethod.hasInterpreterParam = false  # libraryNewImpl doesn't take interpreter param
  libraryCls.classMethods["primitiveLibraryNew"] = libraryNewPrimMethod
  libraryCls.allClassMethods["primitiveLibraryNew"] = libraryNewPrimMethod

  # Also register user-facing 'new' as a class method that wraps the primitive
  let libraryNewMethod = createCoreMethod("new")
  libraryNewMethod.setNativeImpl(libraryNewImpl)
  libraryNewMethod.hasInterpreterParam = false  # libraryNewImpl doesn't take interpreter param
  libraryCls.classMethods["new"] = libraryNewMethod
  libraryCls.allClassMethods["new"] = libraryNewMethod

  # Create Boolean class (derives from Object)
  # Methods are defined in lib/core/Boolean.hrd
  let booleanCls = newClass(superclasses = @[objectCls], name = "Boolean")
  booleanCls.tags = @["Boolean"]
  booleanClass = booleanCls

  # Register Boolean primitive selectors
  let ifTrueMethod = createCoreMethod("primitiveIfTrue:")
  ifTrueMethod.setNativeImpl(ifTrueImpl)
  ifTrueMethod.hasInterpreterParam = true
  booleanCls.methods["primitiveIfTrue:"] = ifTrueMethod
  booleanCls.allMethods["primitiveIfTrue:"] = ifTrueMethod

  let ifFalseMethod = createCoreMethod("primitiveIfFalse:")
  ifFalseMethod.setNativeImpl(ifFalseImpl)
  ifFalseMethod.hasInterpreterParam = true
  booleanCls.methods["primitiveIfFalse:"] = ifFalseMethod
  booleanCls.allMethods["primitiveIfFalse:"] = ifFalseMethod

  # Create True class (singleton class for true value)
  let trueCls = newClass(superclasses = @[booleanCls], name = "True")
  trueCls.tags = @["True", "Boolean"]
  trueClassCache = trueCls

  # Create False class (singleton class for false value)
  let falseCls = newClass(superclasses = @[booleanCls], name = "False")
  falseCls.tags = @["False", "Boolean"]
  falseClassCache = falseCls

  # Create Block class (derives from Object)
  # Methods are defined in lib/core/Block.hrd using <primitive> syntax
  let blockCls = newClass(superclasses = @[objectCls], name = "Block")
  blockCls.tags = @["Block", "Closure"]
  blockClass = blockCls

  # Register Block primitive selectors (used by lib/core/Block.hrd)
  let whileTrueMethod = createCoreMethod("primitiveWhileTrue:")
  whileTrueMethod.setNativeImpl(whileTrueImpl)
  whileTrueMethod.hasInterpreterParam = true
  blockCls.methods["primitiveWhileTrue:"] = whileTrueMethod
  blockCls.allMethods["primitiveWhileTrue:"] = whileTrueMethod

  let whileFalseMethod = createCoreMethod("primitiveWhileFalse:")
  whileFalseMethod.setNativeImpl(whileFalseImpl)
  whileFalseMethod.hasInterpreterParam = true
  blockCls.methods["primitiveWhileFalse:"] = whileFalseMethod
  blockCls.allMethods["primitiveWhileFalse:"] = whileFalseMethod

  let primitiveValueMethod = createCoreMethod("primitiveValue")
  primitiveValueMethod.setNativeImpl(primitiveValueImpl)
  primitiveValueMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue"] = primitiveValueMethod
  blockCls.allMethods["primitiveValue"] = primitiveValueMethod

  let primitiveValueWithArgMethod = createCoreMethod("primitiveValue:")
  primitiveValueWithArgMethod.setNativeImpl(primitiveValueWithArgImpl)
  primitiveValueWithArgMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue:"] = primitiveValueWithArgMethod
  blockCls.allMethods["primitiveValue:"] = primitiveValueWithArgMethod

  let primitiveValueWithTwoArgsMethod = createCoreMethod("primitiveValue:value:")
  primitiveValueWithTwoArgsMethod.setNativeImpl(primitiveValueWithTwoArgsImpl)
  primitiveValueWithTwoArgsMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue:value:"] = primitiveValueWithTwoArgsMethod
  blockCls.allMethods["primitiveValue:value:"] = primitiveValueWithTwoArgsMethod

  let primitiveValueWithThreeArgsMethod = createCoreMethod("primitiveValue:value:value:")
  primitiveValueWithThreeArgsMethod.setNativeImpl(primitiveValueWithThreeArgsImpl)
  primitiveValueWithThreeArgsMethod.hasInterpreterParam = true
  blockCls.methods["primitiveValue:value:value:"] = primitiveValueWithThreeArgsMethod
  blockCls.allMethods["primitiveValue:value:value:"] = primitiveValueWithThreeArgsMethod

  # Register Block exception handling method (primitiveOnDo:do: for on:do: support)
  # The selector is primitiveOnDo:do: because the Harding method has two arguments:
  # Block>>on: exceptionClass do: handlerBlock <primitive primitiveOnDo: exceptionClass do: handlerBlock>
  let primitiveOnDoMethod = createCoreMethod("primitiveOnDo:do:")
  primitiveOnDoMethod.setNativeImpl(primitiveOnDoImpl)
  primitiveOnDoMethod.hasInterpreterParam = true
  blockCls.methods["primitiveOnDo:do:"] = primitiveOnDoMethod
  blockCls.allMethods["primitiveOnDo:do:"] = primitiveOnDoMethod

  # Register Set iteration method (primitiveSetDo: requires interpreter for block evaluation)
  # The Set class itself was created in initCoreClasses (objects.nim)
  if types.setClass != nil:
    let setDoMethod = createCoreMethod("primitiveSetDo:")
    setDoMethod.setNativeImpl(primitiveSetDoImpl)
    setDoMethod.hasInterpreterParam = true
    types.setClass.methods["primitiveSetDo:"] = setDoMethod
    types.setClass.allMethods["primitiveSetDo:"] = setDoMethod

  # Create UndefinedObject class (derives from Object) - the class of nil
  let undefinedObjCls = newClass(superclasses = @[objectCls], name = "UndefinedObject")
  undefinedObjCls.tags = @["UndefinedObject", "Object"]
  undefinedObjectClass = undefinedObjCls  # Set global variable in types module

  # Create the singleton nil instance (instance of UndefinedObject)
  let nilInst = Instance(kind: ikObject, class: undefinedObjCls, slots: @[])
  nilInstance = nilInst  # Set global variable in types module

  # Note: FileStream class and Stdout instance are created in loadStdlib after
  # loading FileStream.hrd. We avoid creating them here to prevent class
  # identity issues where the .hrd file would replace the Nim-created class.

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
  interp.globals[]["Set"] = types.setClass.toValue()
  interp.globals[]["Boolean"] = booleanCls.toValue()
  interp.globals[]["True"] = trueCls.toValue()
  interp.globals[]["False"] = falseCls.toValue()
  interp.globals[]["Block"] = blockCls.toValue()
  interp.globals[]["UndefinedObject"] = undefinedObjCls.toValue()
  interp.globals[]["Library"] = libraryClass.toValue()

  # Create Class class (metaclass) - derives from Object like all classes
  # This allows isKindOf: Class to work properly
  let classCls = newClass(superclasses = @[objectCls], name = "Class")
  classCls.tags = @["Class", "Object"]
  interp.globals[]["Class"] = classCls.toValue()

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

  # Protect Library global
  protectGlobal("Library")

  # Install Library methods that need interpreter access
  installLibraryMethods()

  # Initialize the Harding global - an instance of GlobalTable that wraps global namespace
  initHardingGlobal(interp)


proc loadStdlib*(interp: var Interpreter, bootstrapFile: string = "") =
  ## Load core library files
  ## If bootstrapFile is provided and exists, it will be loaded and should use
  ## Harding load: to load other files. Otherwise, uses the default Bootstrap.hrd.

  # Initialize Process, Scheduler, Monitor, SharedQueue, Semaphore classes
  # Use a callback to avoid circular import with scheduler module
  if interp.schedulerContextPtr != nil:
    # Scheduler is already initialized, classes should be available
    discard

  # Use lib/core/Bootstrap.hrd as default if no bootstrapFile provided
  let actualBootstrapFile = if bootstrapFile.len > 0 and fileExists(bootstrapFile):
                             bootstrapFile
                           else:
                             interp.hardingHome / "lib" / "core" / "Bootstrap.hrd"

  if fileExists(actualBootstrapFile):
    debug("Loading bootstrap file: ", actualBootstrapFile)
    let source = readFile(actualBootstrapFile)
    let (_, err) = interp.evalStatements(source)
    if err.len > 0:
      warn("Failed to load bootstrap file ", actualBootstrapFile, ": ", err)
    else:
      debug("Successfully loaded bootstrap: ", actualBootstrapFile)
  else:
    warn("Bootstrap file not found: ", actualBootstrapFile)

  # Set up class caches for primitive types
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

  if "Symbol" in interp.globals[]:
    let symVal = interp.globals[]["Symbol"]
    if symVal.kind == vkClass:
      symbolClassCache = symVal.classVal
      debug("Set symbolClassCache from Symbol global")

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

  # Set up FileStream class and Stdout instance
  proc findClassInLibraries(interp: Interpreter, name: string): Class =
    for lib in interp.importedLibraries:
      if lib.kind == ikObject and lib.class == libraryClass:
        let bindingsVal = lib.slots[0]
        if bindingsVal.kind == vkInstance and bindingsVal.instVal.kind == ikTable:
          let classVal = bindingsVal.instVal.entries[toValue(name)]
          if classVal.kind == vkClass:
            return classVal.classVal
    return nil

  let fileStreamCls = if "FileStream" in interp.globals[]:
                         let fsVal = interp.globals[]["FileStream"]
                         if fsVal.kind == vkClass: fsVal.classVal else: nil
                       else:
                         findClassInLibraries(interp, "FileStream")

  if fileStreamCls != nil:
    # Native builds: Use native implementations
    let fsWriteMethod = createCoreMethod("write:")
    fsWriteMethod.setNativeImpl(writeImpl)
    fileStreamCls.methods["write:"] = fsWriteMethod
    fileStreamCls.allMethods["write:"] = fsWriteMethod

    let fsWritelineMethod = createCoreMethod("writeline:")
    fsWritelineMethod.setNativeImpl(writelineImpl)
    fileStreamCls.methods["writeline:"] = fsWritelineMethod
    fileStreamCls.allMethods["writeline:"] = fsWritelineMethod
    debug("Registered native FileStream methods")

    let stdoutInstance = fileStreamCls.newInstance()
    interp.globals[]["Stdout"] = stdoutInstance.toValue()
    debug("Created Stdout instance from FileStream class")

  when defined(granite):
    # Register Granite compiler primitives
    let graniteCls = if "Granite" in interp.globals[]:
                       let gVal = interp.globals[]["Granite"]
                       if gVal.kind == vkClass: gVal.classVal else: nil
                     else:
                       nil

    if graniteCls != nil:
      # Register primitiveGraniteCompile: primitive (class method)
      # This is called when Granite class>>compile: sourceString <primitive primitiveGraniteCompile: sourceString>
      let primCompileMethod = createCoreMethod("primitiveGraniteCompile:")
      primCompileMethod.setNativeImpl(graniteCompileImpl)
      graniteCls.methods["primitiveGraniteCompile:"] = primCompileMethod
      graniteCls.allMethods["primitiveGraniteCompile:"] = primCompileMethod

      # Register primitiveGraniteBuild: primitive (class method)
      # This is called when Granite class>>build: anApplication <primitive primitiveGraniteBuild: anApplication>
      let primBuildMethod = createCoreMethod("primitiveGraniteBuild:")
      primBuildMethod.setNativeImpl(graniteBuildImpl)
      graniteCls.methods["primitiveGraniteBuild:"] = primBuildMethod
      graniteCls.allMethods["primitiveGraniteBuild:"] = primBuildMethod

      # Set interpreter reference for primitives
      compiler_primitives.currentInterpreter = interp

      debug("Registered native Granite compiler methods")

  # Register Exception primitive methods
  # First try to find Exception in globals or imported libraries
  var exceptionCls: Class = nil

  debug("Looking for Exception, importedLibraries.len = ", $interp.importedLibraries.len)

  # Check globals first
  if "Exception" in interp.globals[]:
    let exVal = interp.globals[]["Exception"]
    if exVal.kind == vkClass:
      exceptionCls = exVal.classVal
      debug("Found Exception in globals")

  # If not in globals, check imported libraries
  if exceptionCls == nil:
    for lib in interp.importedLibraries:
      debug("Checking imported library, class = ", lib.class.name)
      if lib.kind == ikObject and lib.class != nil and lib.class.name == "Library":
        # Try to get Exception from library bindings
        let bindingsVal = lib.slots[0]  # bindings table is first slot
        debug("Library bindings kind: ", $bindingsVal.kind)
        if bindingsVal.kind == vkInstance and bindingsVal.instVal.kind == ikTable:
          debug("Library has ", $bindingsVal.instVal.entries.len, " entries")
          let exKey = toValue("Exception")
          if exKey in bindingsVal.instVal.entries:
            let exVal = bindingsVal.instVal.entries[exKey]
            debug("Found Exception entry, kind: ", $exVal.kind)
            if exVal.kind == vkClass:
              exceptionCls = exVal.classVal
              debug("Found Exception in imported library")
              break

  if exceptionCls != nil:
    let primitiveSignalMethod = createCoreMethod("primitiveSignal")
    primitiveSignalMethod.setNativeImpl(primitiveSignalImpl)
    primitiveSignalMethod.hasInterpreterParam = true
    exceptionCls.methods["primitiveSignal"] = primitiveSignalMethod
    exceptionCls.allMethods["primitiveSignal"] = primitiveSignalMethod

    # Propagate to all subclasses (since allMethods was already copied)
    proc propagateToSubclasses(cls: Class, methodName: string, meth: BlockNode) =
      for sub in cls.subclasses:
        sub.allMethods[methodName] = meth
        propagateToSubclasses(sub, methodName, meth)
    propagateToSubclasses(exceptionCls, "primitiveSignal", primitiveSignalMethod)

    debug("Registered native Exception>>primitiveSignal method")
  else:
    debug("Exception class not found, cannot register primitiveSignal")

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
# GlobalTable Class and Harding Global
# ============================================================================

type
  GlobalTableProxy* = ref object
    globals*: ref Table[string, NodeValue]

# Keep GlobalTableProxy references alive - stored as raw pointer in nimValue,
# the GC needs to see actual Nim refs to prevent collection
var globalTableProxies: seq[GlobalTableProxy] = @[]

proc createGlobalTableClass*(): Class =
  ## Create the GlobalTable class - a subclass of Table that wraps the globals table
  ## The global globals table is accessible via the 'Harding' global

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
  globalTableClass.hardingType = "GlobalTable"

  # GlobalTable inherits all methods from Table (keys, at:, at:put:, includesKey:)
  # No additional methods needed - it just wraps the globals table

  return globalTableClass

proc initHardingGlobal*(interp: var Interpreter) =
  ## Initialize the Harding global - an instance of GlobalTable that wraps global namespace

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

  # Add to globals as 'Harding' (the global namespace accessor)
  interp.globals[]["Harding"] = globalTableInstance.toValue()

  # Also add the GlobalTable class itself to globals for reflection
  interp.globals[]["GlobalTable"] = globalTableClass.toValue()

  # Rebuild Object class descendants to ensure subclasses inherit class methods
  # added in this function (initGlobals adds methods directly to objectClass)
  rebuildAllDescendants(objectClass)

# Special handling for GlobalTable - modify Table methods to access globals
proc globalTableAtImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## GlobalTable at: - access global variable
  let proxy = if self.isNimProxy and self.class.hardingType == "GlobalTable" and nimValueIsSet(self.nimValue):
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
  let proxy = if self.isNimProxy and self.class.hardingType == "GlobalTable" and nimValueIsSet(self.nimValue):
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
  let proxy = if self.isNimProxy and self.class.hardingType == "GlobalTable" and nimValueIsSet(self.nimValue):
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
  let proxy = if self.isNimProxy and self.class.hardingType == "GlobalTable" and nimValueIsSet(self.nimValue):
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
  ## GlobalTable load: - load and evaluate a Harding file
  ## Resolves paths relative to HARDING_HOME if not absolute
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

  # Resolve path relative to hardingHome if not absolute
  let resolvedPath = if filePath.isAbsolute:
                       filePath
                     else:
                       interp.hardingHome / filePath

  # Check if file exists
  if not fileExists(resolvedPath):
    writeStderr("Error: File not found: " & resolvedPath)
    return nilValue()

  # Read and evaluate the file
  try:
    let source = readFile(resolvedPath)
    let (_, err) = interp.evalStatements(source)
    if err.len > 0:
      writeStderr("Error loading " & resolvedPath & ": " & err)
      return nilValue()
    debug("Successfully loaded: ", resolvedPath)
    return toValue(true)
  except Exception as e:
    writeStderr("Error reading " & resolvedPath & ": " & e.msg)
    return nilValue()

# ============================================================================
# Library methods (need interpreter access)
# ============================================================================

proc libraryLoadImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library load: - load and evaluate a file, capturing new globals into this Library's bindings
  if args.len < 1:
    return nilValue()

  let pathArg = args[0]
  let filePath = case pathArg.kind
    of vkString: pathArg.strVal
    of vkSymbol: pathArg.symVal
    else: ""

  if filePath.len == 0:
    return nilValue()

  let resolvedPath = if filePath.isAbsolute:
                       filePath
                     else:
                       interp.hardingHome / filePath

  if not fileExists(resolvedPath):
    writeStderr("Error: File not found: " & resolvedPath)
    return nilValue()

  # Save original globals and create a copy for capturing new definitions
  let originalGlobals = interp.globals
  var tempGlobals: ref Table[string, NodeValue]
  new(tempGlobals)
  tempGlobals[] = originalGlobals[]

  # Swap globals to temp table so new definitions go there
  interp.globals = tempGlobals

  try:
    let source = readFile(resolvedPath)
    let (_, err) = interp.evalStatements(source)
    if err.len > 0:
      writeStderr("Error loading " & resolvedPath & ": " & err)
      interp.globals = originalGlobals
      return nilValue()

    # Restore original globals
    interp.globals = originalGlobals

    # Copy new entries into the Library's bindings table
    let bindings = getLibraryBindings(self)
    if bindings != nil:
      for key, val in tempGlobals[]:
        if key notin originalGlobals[]:
          setTableValue(bindings, toValue(key), val)
          debug("Library captured: ", key)

    debug("Successfully loaded into library: ", resolvedPath)
    return toValue(true)
  except Exception as e:
    interp.globals = originalGlobals
    writeStderr("Error reading " & resolvedPath & ": " & e.msg)
    return nilValue()

proc globalTableImportImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Harding import: - add a Library to the interpreter's imported libraries list
  if args.len < 1:
    return nilValue()

  let libArg = args[0]
  if libArg.kind != vkInstance or libArg.instVal == nil:
    writeStderr("Error: import: argument must be a Library instance")
    return nilValue()

  let lib = libArg.instVal
  if lib.class != libraryClass:
    writeStderr("Error: import: argument must be a Library instance")
    return nilValue()

  interp.importedLibraries.add(lib)
  debug("Imported library, total imports: ", $interp.importedLibraries.len)
  return toValue(true)

proc installLibraryMethods*() =
  ## Install Library methods that need interpreter access
  if libraryClass == nil:
    return

  let loadMethod = createCoreMethod("load:")
  loadMethod.setNativeImpl(libraryLoadImpl)
  loadMethod.hasInterpreterParam = true
  addMethodToClass(libraryClass, "load:", loadMethod)

# Patch GlobalTable methods after class creation
proc installGlobalTableMethods*(globalTableClass: Class) =
  ## Install special GlobalTable methods that wrap the globals table
  if globalTableClass == nil:
    return

  # Override at: method
  let atMethod = createCoreMethod("at:")
  atMethod.setNativeImpl(globalTableAtImpl)
  atMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "at:", atMethod)

  # Override at:put: method
  let atPutMethod = createCoreMethod("at:put:")
  atPutMethod.setNativeImpl(globalTableAtPutImpl)
  atPutMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "at:put:", atPutMethod)

  # Override keys method
  let keysMethod = createCoreMethod("keys")
  keysMethod.setNativeImpl(globalTableKeysImpl)
  keysMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "keys", keysMethod)

  # Override includesKey: method
  let includesKeyMethod = createCoreMethod("includesKey:")
  includesKeyMethod.setNativeImpl(globalTableIncludesKeyImpl)
  includesKeyMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "includesKey:", includesKeyMethod)

  # Add load: method for loading Harding files
  let loadMethod = createCoreMethod("load:")
  loadMethod.setNativeImpl(globalTableLoadImpl)
  loadMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "load:", loadMethod)

  # Add import: method for importing Libraries into the interpreter
  let importMethod = createCoreMethod("import:")
  importMethod.setNativeImpl(globalTableImportImpl)
  importMethod.hasInterpreterParam = true
  addMethodToClass(globalTableClass, "import:", importMethod)

# ============================================================================
# Explicit Stack AST Interpreter (VM)
# ============================================================================

type
  VMStatus* = enum
    vmRunning     # Normal execution
    vmYielded     # Processor yielded, can be resumed
    vmCompleted   # Execution finished
    vmError       # Error occurred

  VMResult* = object
    status*: VMStatus
    value*: NodeValue
    error*: string

# Work frame constructors
proc newEvalFrame*(node: Node): WorkFrame =
  WorkFrame(kind: wfEvalNode, node: node)

proc newSendMessageFrame*(selector: string, argCount: int, msgNode: MessageNode = nil, isClassMethod: bool = false): WorkFrame =
  WorkFrame(kind: wfSendMessage, selector: selector, argCount: argCount, msgNode: msgNode, isClassMethod: isClassMethod)

proc newAfterReceiverFrame*(selector: string, args: seq[Node], isClassMethod: bool = false): WorkFrame =
  WorkFrame(kind: wfAfterReceiver, pendingSelector: selector, pendingArgs: args, currentArgIndex: 0, isClassMethod: isClassMethod)

proc newAfterArgFrame*(selector: string, args: seq[Node], currentIndex: int, isClassMethod: bool = false): WorkFrame =
  WorkFrame(kind: wfAfterArg, pendingSelector: selector, pendingArgs: args, currentArgIndex: currentIndex, isClassMethod: isClassMethod)

proc newApplyBlockFrame*(blockVal: BlockNode, argCount: int): WorkFrame =
  WorkFrame(kind: wfApplyBlock, blockVal: blockVal, argCount: argCount, blockArgs: @[])

proc newReturnValueFrame*(value: NodeValue): WorkFrame =
  WorkFrame(kind: wfReturnValue, returnValue: value)

proc newCascadeFrame*(messages: seq[MessageNode], receiver: NodeValue): WorkFrame =
  WorkFrame(kind: wfCascade, cascadeMessages: messages, cascadeReceiver: receiver)

proc newPopActivationFrame*(savedReceiver: Instance, isBlock: bool = false, evalStackDepth: int = 0): WorkFrame =
  WorkFrame(kind: wfPopActivation, savedReceiver: savedReceiver, isBlockActivation: isBlock, savedEvalStackDepth: evalStackDepth)

proc newIfBranchFrame*(condResult: bool, thenBlock, elseBlock: BlockNode): WorkFrame =
  ## Create a work frame for conditional branch (ifTrue:, ifFalse:)
  WorkFrame(kind: wfIfBranch, conditionResult: condResult, thenBlock: thenBlock, elseBlock: elseBlock)

proc newWhileLoopFrame*(loopKind: bool, conditionBlock, bodyBlock: BlockNode, loopState: LoopState): WorkFrame =
  ## Create a work frame for while loop (whileTrue:, whileFalse:)
  WorkFrame(kind: wfWhileLoop, loopKind: loopKind, conditionBlock: conditionBlock, bodyBlock: bodyBlock, loopState: loopState)

proc newPushHandlerFrame*(exceptionClass: Class, handlerBlock: BlockNode): WorkFrame =
  ## Create a work frame to push an exception handler
  WorkFrame(kind: wfPushHandler, exceptionClass: exceptionClass, handlerBlock: handlerBlock)

proc newPopHandlerFrame*(): WorkFrame =
  ## Create a work frame to pop an exception handler
  WorkFrame(kind: wfPopHandler)

proc newSignalExceptionFrame*(exceptionInstance: Instance): WorkFrame =
  ## Create a work frame to signal an exception
  WorkFrame(kind: wfSignalException, exceptionInstance: exceptionInstance)

# Stack operations
proc pushWorkFrame*(interp: var Interpreter, frame: WorkFrame) =
  interp.workQueue.add(frame)

proc popWorkFrame*(interp: var Interpreter): WorkFrame =
  if interp.workQueue.len == 0:
    raise newException(ValueError, "Work queue underflow")
  result = interp.workQueue.pop()

proc hasWorkFrames*(interp: Interpreter): bool =
  interp.workQueue.len > 0

proc pushValue*(interp: var Interpreter, value: NodeValue) =
  debug("VM: pushValue ", value.toString(), " (stack len will be ", interp.evalStack.len + 1, ")")
  interp.evalStack.add(value)

proc popValue*(interp: var Interpreter): NodeValue =
  if interp.evalStack.len == 0:
    raise newException(ValueError, "Eval stack underflow")
  result = interp.evalStack.pop()
  debug("VM: popValue ", result.toString(), " (stack len now ", interp.evalStack.len, ")")

proc peekValue*(interp: Interpreter): NodeValue =
  if interp.evalStack.len == 0:
    raise newException(ValueError, "Eval stack empty")
  interp.evalStack[^1]

proc popValues*(interp: var Interpreter, count: int): seq[NodeValue] =
  ## Pop multiple values in reverse order (first argument was pushed first)
  result = newSeq[NodeValue](count)
  for i in countdown(count - 1, 0):
    result[i] = interp.popValue()

# Clear VM state
proc clearVMState*(interp: var Interpreter) =
  interp.workQueue.setLen(0)
  interp.evalStack.setLen(0)

# Handle evaluation of simple nodes (Phase 2)
proc handleEvalNode(interp: var Interpreter, frame: WorkFrame): bool =
  ## Handle wfEvalNode work frame. Returns true if processing should continue.
  let node = frame.node
  if node == nil:
    interp.pushValue(nilValue())
    return true

  case node.kind
  of nkLiteral:
    let lit = cast[LiteralNode](node)
    interp.pushValue(lit.value)
    return true

  of nkIdent:
    let ident = cast[IdentNode](node)
    let value = lookupVariable(interp, ident.name)
    interp.pushValue(value)
    return true

  of nkPseudoVar:
    let pseudo = cast[PseudoVarNode](node)
    case pseudo.name
    of "self":
      if interp.currentReceiver == nil:
        interp.pushValue(nilValue())
      # For class methods, self should return the Class object
      # We track this via activation.isClassMethod rather than structural checks
      elif interp.currentActivation != nil and interp.currentActivation.isClassMethod:
        interp.pushValue(interp.currentReceiver.class.toValue())
      else:
        # Check if currentReceiver is a class wrapper (instance representing a class)
        # Class wrappers have kind=ikObject, empty slots, and nimValue=nil
        # When asSelfDo: sets self to a class, we need to return vkClass so method dispatch works
        if interp.currentReceiver.kind == ikObject and interp.currentReceiver.class != nil:
          # Class wrappers have empty slots and no nimValue
          if interp.currentReceiver.slots.len == 0 and not nimValueIsSet(interp.currentReceiver.nimValue):
            # This is a class wrapper - return the class as vkClass
            interp.pushValue(interp.currentReceiver.class.toValue())
          else:
            interp.pushValue(interp.currentReceiver.toValue().unwrap())
        else:
          interp.pushValue(interp.currentReceiver.toValue().unwrap())
    of "nil":
      interp.pushValue(nilValue())
    of "true":
      interp.pushValue(trueValue)
    of "false":
      interp.pushValue(falseValue)
    of "super":
      if interp.currentReceiver != nil:
        interp.pushValue(interp.currentReceiver.toValue().unwrap())
      else:
        interp.pushValue(nilValue())
    else:
      interp.pushValue(nilValue())
    return true

  of nkBlock:
    # Block literal - create a copy and capture environment
    let origBlock = cast[BlockNode](node)
    let blockNode = BlockNode(
      parameters: origBlock.parameters,
      temporaries: origBlock.temporaries,
      body: origBlock.body,
      isMethod: origBlock.isMethod,
      capturedEnv: initTable[string, MutableCell](),
      capturedEnvInitialized: true,
      homeActivation: interp.currentActivation
    )
    captureEnvironment(interp, blockNode)
    interp.pushValue(NodeValue(kind: vkBlock, blockVal: blockNode))
    return true

  of nkAssign:
    # Variable assignment: evaluate expression, then assign
    let assign = cast[AssignNode](node)
    # Push continuation frame to handle assignment after expression is evaluated
    interp.pushWorkFrame(WorkFrame(
      kind: wfAfterArg,  # Reuse for assignment continuation
      pendingSelector: "__assign__",  # Internal marker for assignment (not a valid selector)
      pendingArgs: @[],
      currentArgIndex: 0
    ))
    # Extend frame with variable name (store in selector field)
    interp.workQueue[^1].selector = assign.variable
    # Evaluate expression
    interp.pushWorkFrame(newEvalFrame(assign.expression))
    return true

  of nkSlotAccess:
    # Slot access - O(1) direct instance variable access by index
    let slotNode = cast[SlotAccessNode](node)
    if interp.currentReceiver != nil and interp.currentReceiver.kind == ikObject:
      let inst = interp.currentReceiver
      if slotNode.slotIndex >= 0 and slotNode.slotIndex < inst.slots.len:
        if slotNode.isAssignment:
          # Assignment: need to evaluate valueExpr first
          if slotNode.valueExpr != nil:
            # Push continuation to handle slot assignment
            interp.pushWorkFrame(WorkFrame(
              kind: wfAfterArg,
              pendingSelector: ":=",
              currentArgIndex: slotNode.slotIndex
            ))
            interp.pushWorkFrame(newEvalFrame(slotNode.valueExpr))
            return true
          else:
            interp.pushValue(nilValue())
            return true
        else:
          # Read slot value
          interp.pushValue(inst.slots[slotNode.slotIndex])
          return true
    interp.pushValue(nilValue())
    return true

  of nkMessage:
    # Message send - will be implemented in Phase 3
    # For now, push placeholder frames
    let msg = cast[MessageNode](node)

    # First evaluate receiver (or use self if nil)
    if msg.receiver != nil:
      interp.pushWorkFrame(newAfterReceiverFrame(msg.selector, msg.arguments))
      interp.pushWorkFrame(newEvalFrame(msg.receiver))
    else:
      # Implicit self as receiver
      if interp.currentReceiver == nil:
        interp.pushValue(nilValue())
      else:
        interp.pushValue(interp.currentReceiver.toValue().unwrap())
      # Now handle arguments
      if msg.arguments.len == 0:
        interp.pushWorkFrame(newSendMessageFrame(msg.selector, 0, msg))
      else:
        interp.pushWorkFrame(newAfterArgFrame(msg.selector, msg.arguments, 0))
        interp.pushWorkFrame(newEvalFrame(msg.arguments[0]))
    return true

  of nkReturn:
    # Return - evaluate expression and push return frame
    let ret = cast[ReturnNode](node)
    if ret.expression != nil:
      # Push placeholder with vkNil (NOT nilValue() which may be vkInstance)
      # This signals to wfReturnValue to pop the value from the stack
      interp.pushWorkFrame(WorkFrame(kind: wfReturnValue, returnValue: NodeValue(kind: vkNil)))
      interp.pushWorkFrame(newEvalFrame(ret.expression))
    else:
      # Return self
      if interp.currentReceiver != nil:
        interp.pushWorkFrame(newReturnValueFrame(interp.currentReceiver.toValue().unwrap()))
      else:
        interp.pushWorkFrame(WorkFrame(kind: wfReturnValue, returnValue: NodeValue(kind: vkNil)))
    return true

  of nkArray:
    # Array literal - evaluate elements
    let arr = cast[ArrayNode](node)
    if arr.elements.len == 0:
      if arrayClass != nil:
        interp.pushValue(newArrayInstance(arrayClass, @[]).toValue())
      else:
        interp.pushValue(NodeValue(kind: vkArray, arrayVal: @[]))
    else:
      # Push build-array frame first (will execute last)
      interp.pushWorkFrame(WorkFrame(kind: wfBuildArray, argCount: arr.elements.len))
      # Push element evaluation frames in reverse order
      for i in countdown(arr.elements.len - 1, 0):
        let elem = arr.elements[i]
        # Handle special cases for array literals (symbols, keywords)
        if elem.kind == nkIdent:
          let ident = cast[IdentNode](elem)
          case ident.name
          of "true":
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: PseudoVarNode(name: "true")))
          of "false":
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: PseudoVarNode(name: "false")))
          of "nil":
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: PseudoVarNode(name: "nil")))
          else:
            # Bare identifier in array literal is treated as symbol
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: LiteralNode(value: getSymbol(ident.name))))
        else:
          interp.pushWorkFrame(newEvalFrame(elem))
    return true

  of nkTable:
    # Table literal - evaluate key-value pairs and build table
    let tab = cast[TableNode](node)
    if tab.entries.len == 0:
      if tableClass != nil:
        interp.pushValue(newTableInstance(tableClass, initTable[NodeValue, NodeValue]()).toValue())
      else:
        interp.pushValue(NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]()))
    else:
      # Push build-table frame first (will execute last)
      interp.pushWorkFrame(WorkFrame(kind: wfBuildTable, argCount: tab.entries.len * 2))
      # Push key-value evaluation frames in reverse order (values first, then keys)
      for i in countdown(tab.entries.len - 1, 0):
        let entry = tab.entries[i]
        interp.pushWorkFrame(newEvalFrame(entry.value))  # Value
        interp.pushWorkFrame(newEvalFrame(entry.key))    # Key
    return true

  of nkCascade:
    # Cascade messages - evaluate receiver once, then send each message to same receiver
    let cascade = cast[CascadeNode](node)
    if cascade.messages.len == 0:
      # No messages, just evaluate receiver
      interp.pushWorkFrame(newEvalFrame(cascade.receiver))
    else:
      # Push cascade continuation frame to handle multiple messages
      interp.pushWorkFrame(newCascadeFrame(cascade.messages, nilValue()))
      # Evaluate receiver first
      interp.pushWorkFrame(newEvalFrame(cascade.receiver))
    return true

  of nkSuperSend:
    # Super send - lookup method in parent class
    let superNode = cast[SuperSendNode](node)

    if interp.currentReceiver == nil:
      raise newException(ValueError, "super send with no current receiver")

    # Get the defining class from the current activation
    var definingClass: Class = nil
    if interp.currentActivation != nil and interp.currentActivation.definingObject != nil:
      definingClass = interp.currentActivation.definingObject
    else:
      definingClass = interp.currentReceiver.class

    if definingClass == nil:
      raise newException(ValueError, "super send with no defining class")

    # Determine which parent to look in
    var targetParent: Class = nil
    if superNode.explicitParent.len > 0:
      # Qualified super<Parent>: find specific parent by name
      for parent in definingClass.superclasses:
        if parent.name == superNode.explicitParent:
          targetParent = parent
          break
      if targetParent == nil:
        raise newException(ValueError, "Parent class '" & superNode.explicitParent & "' not found in inheritance chain")
    else:
      # Unqualified super: use first parent of the defining class
      if definingClass.superclasses.len == 0:
        raise newException(ValueError, "super send in class with no parents")
      targetParent = definingClass.superclasses[0]

    # Look up method in target parent's allMethods
    let methodBlock = lookupInstanceMethod(targetParent, superNode.selector)
    if methodBlock == nil:
      raise newException(ValueError, "Method '" & superNode.selector & "' not found in super class " & targetParent.name)

    # Evaluate arguments using evalWithVM, then call executeMethod directly
    # This avoids wfSendMessage which doesn't carry super class context
    var arguments: seq[NodeValue] = @[]
    for argNode in superNode.arguments:
      arguments.add(interp.evalWithVM(argNode))

    let methodResult = executeMethod(interp, methodBlock, interp.currentReceiver, arguments, targetParent)
    interp.pushValue(methodResult)
    return true

  of nkObjectLiteral:
    # Object literal - create new Table instance with properties
    let objLit = cast[ObjectLiteralNode](node)
    if objLit.properties.len == 0:
      # Empty object literal
      if tableClass != nil:
        interp.pushValue(newTableInstance(tableClass, initTable[NodeValue, NodeValue]()).toValue())
      else:
        interp.pushValue(NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]()))
    else:
      # Push build-object-literal frame (reuses wfBuildTable with string keys)
      interp.pushWorkFrame(WorkFrame(kind: wfBuildTable, argCount: objLit.properties.len * 2))
      # Push property value evaluations in reverse order
      for i in countdown(objLit.properties.len - 1, 0):
        let prop = objLit.properties[i]
        # Property name as string value
        interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: LiteralNode(value: toValue(prop.name))))
        interp.pushWorkFrame(newEvalFrame(prop.value))
    return true

  of nkPrimitive:
    # Primitive - evaluate fallback
    let prim = cast[PrimitiveNode](node)
    if prim.fallback.len > 0:
      # Evaluate fallback statements
      for i in countdown(prim.fallback.len - 1, 0):
        if i < prim.fallback.len - 1:
          # Pop intermediate results (only keep last)
          interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
        interp.pushWorkFrame(newEvalFrame(prim.fallback[i]))
    else:
      interp.pushValue(nilValue())
    return true

  of nkPrimitiveCall:
    # Primitive call - dispatch via standard method lookup on currentReceiver
    let primCall = cast[PrimitiveCallNode](node)
    debug("VM: Primitive call #", primCall.selector, " with ", primCall.arguments.len, " args")
    debug("VM: currentReceiver=", if interp.currentReceiver != nil: interp.currentReceiver.class.name else: "nil")
    debug("VM: isClassMethod=", $primCall.isClassMethod)

    # Push currentReceiver as the receiver
    if interp.currentReceiver != nil:
      interp.pushValue(interp.currentReceiver.toValue().unwrap())
    else:
      interp.pushValue(nilValue())

    # Use the same continuation mechanism as message sends
    if primCall.arguments.len > 0:
      interp.pushWorkFrame(newAfterReceiverFrame(primCall.selector, primCall.arguments, primCall.isClassMethod))
    else:
      interp.pushWorkFrame(newSendMessageFrame(primCall.selector, 0, isClassMethod = primCall.isClassMethod))
    return true

# Handle continuation frames (what to do after subexpression)
proc handleContinuation(interp: var Interpreter, frame: WorkFrame): bool =
  case frame.kind
  of wfAfterReceiver:
    # Receiver is on stack, now evaluate arguments
    if frame.pendingArgs.len == 0:
      # No arguments - send message now
      interp.pushWorkFrame(newSendMessageFrame(frame.pendingSelector, 0, isClassMethod = frame.isClassMethod))
    else:
      # Evaluate first argument
      interp.pushWorkFrame(newAfterArgFrame(frame.pendingSelector, frame.pendingArgs, 0, frame.isClassMethod))
      interp.pushWorkFrame(newEvalFrame(frame.pendingArgs[0]))
    return true

  of wfAfterArg:
    # Special case: assignment continuation
    if frame.pendingSelector == "__assign__":
      let value = interp.popValue()
      setVariable(interp, frame.selector, value)
      interp.pushValue(value)
      return true

    # Special case: slot assignment continuation
    if frame.pendingSelector == ":=":
      let value = interp.popValue()
      if interp.currentReceiver != nil and interp.currentReceiver.kind == ikObject:
        let slotIndex = frame.currentArgIndex
        if slotIndex >= 0 and slotIndex < interp.currentReceiver.slots.len:
          interp.currentReceiver.slots[slotIndex] = value
      interp.pushValue(value)
      return true

    # Special case: discard continuation (for primitive fallback)
    if frame.pendingSelector == "discard":
      discard interp.popValue()
      return true

    # Argument evaluated, check if more
    let nextIndex = frame.currentArgIndex + 1
    if nextIndex < frame.pendingArgs.len:
      # More arguments to evaluate
      interp.pushWorkFrame(newAfterArgFrame(frame.pendingSelector, frame.pendingArgs, nextIndex, frame.isClassMethod))
      interp.pushWorkFrame(newEvalFrame(frame.pendingArgs[nextIndex]))
    else:
      # All arguments evaluated - send message
      interp.pushWorkFrame(newSendMessageFrame(frame.pendingSelector, frame.pendingArgs.len, isClassMethod = frame.isClassMethod))
    return true

  of wfSendMessage:
    # Pop args and receiver, send message
    let args = interp.popValues(frame.argCount)
    let receiverVal = interp.popValue()

    # Handle block invocation
    if receiverVal.kind == vkBlock:
      case frame.selector
      of "value", "value:", "value:value:", "value:value:value:", "value:value:value:value:":
        interp.pushWorkFrame(newApplyBlockFrame(receiverVal.blockVal, args.len))
        # Push args back for block application
        for arg in args:
          interp.pushValue(arg)
        return true
      else:
        discard  # Fall through to regular dispatch

    # ============================================================================
    # FAST PATH: Tagged Integer Operations
    # Skip Instance allocation for primitive integer operations
    # ============================================================================
    if receiverVal.kind == vkInt and args.len > 0 and args[0].kind == vkInt:
      let a = toTagged(receiverVal)
      let b = toTagged(args[0])
      var taggedResult: TaggedValue
      var boolResult: bool
      var isPrimitive = true
      var isComparison = false

      case frame.selector
      of "+":
        taggedResult = add(a, b)
      of "-":
        taggedResult = sub(a, b)
      of "*":
        taggedResult = mul(a, b)
      of "//":
        taggedResult = divInt(a, b)
      of "%":
        taggedResult = modInt(a, b)
      of "=":
        boolResult = intEquals(a, b)
        isComparison = true
      of "<":
        boolResult = lessThan(a, b)
        isComparison = true
      of "<=":
        boolResult = lessOrEqual(a, b)
        isComparison = true
      of ">":
        boolResult = greaterThan(a, b)
        isComparison = true
      of ">=":
        boolResult = greaterOrEqual(a, b)
        isComparison = true
      else:
        isPrimitive = false  # Not a primitive integer operation

      if isPrimitive:
        if isComparison:
          # Comparison returns boolean
          interp.pushValue(NodeValue(kind: vkBool, boolVal: boolResult))
        else:
          # Arithmetic returns integer
          interp.pushValue(toNodeValue(taggedResult))
        return true

    # Convert receiver to Instance for method lookup
    var receiver: Instance
    case receiverVal.kind
    of vkInstance:
      receiver = receiverVal.instVal
    of vkInt:
      receiver = newIntInstance(integerClass, receiverVal.intVal)
    of vkFloat:
      receiver = newFloatInstance(floatClass, receiverVal.floatVal)
    of vkString:
      receiver = newStringInstance(stringClass, receiverVal.strVal)
    of vkBool:
      # Boolean - create ikObject instance with nimValue
      var boolInst: Instance
      new(boolInst)
      boolInst.kind = ikObject
      boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
      boolInst.slots = @[]
      let p = cast[pointer](alloc(sizeof(bool)))
      cast[ptr bool](p)[] = receiverVal.boolVal
      boolInst.isNimProxy = true
      boolInst.nimValue = p
      receiver = boolInst
    of vkNil:
      receiver = nilInstance
    of vkArray:
      receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
    of vkTable:
      receiver = newTableInstance(tableClass, receiverVal.tableVal)
    of vkClass:
      # Class method lookup
      let cls = receiverVal.classVal
      let lookup = lookupClassMethod(cls, frame.selector)
      if lookup.found:
        let currentMethod = lookup.currentMethod

        # Handle native class methods
        if nativeImplIsSet(currentMethod):
          let savedReceiver = interp.currentReceiver
          # Create class receiver wrapper for consistent receiver handling
          let classReceiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)
          # Set currentReceiver for consistent method context
          interp.currentReceiver = classReceiver
          try:
            var resultVal: NodeValue
            if currentMethod.hasInterpreterParam:
              # Native method with interpreter - pass class receiver wrapper
              type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
              let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
              resultVal = nativeProc(interp, classReceiver, args)
            else:
              # Direct class method without interpreter param
              type ClassMethodProc = proc(self: Class, args: seq[NodeValue]): NodeValue {.nimcall.}
              let nativeProc = cast[ClassMethodProc](currentMethod.nativeImpl)
              resultVal = nativeProc(cls, args)
            interp.pushValue(resultVal)
          finally:
            interp.currentReceiver = savedReceiver
          return true

        # Interpreted class method - create activation with class wrapper as receiver
        let classReceiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)

        # Check parameter count
        if currentMethod.parameters.len != args.len:
          raise newException(ValueError,
            "Wrong number of arguments: expected " & $currentMethod.parameters.len &
            ", got " & $args.len)

        # Create activation (isClassMethod = true for class methods)
        let activation = newActivation(currentMethod, classReceiver, interp.currentActivation, lookup.definingClass, isClassMethod = true)

        # Bind parameters
        for i in 0..<currentMethod.parameters.len:
          activation.locals[currentMethod.parameters[i]] = args[i]

        # Initialize temporaries
        for tempName in currentMethod.temporaries:
          if tempName notin activation.locals:
            activation.locals[tempName] = nilValue()

        # Save current receiver
        let savedReceiver = interp.currentReceiver

        # Push activation
        interp.activationStack.add(activation)
        interp.currentActivation = activation
        interp.currentReceiver = classReceiver

        # Set home activation for methods
        if currentMethod.isMethod:
          currentMethod.homeActivation = activation

        # Push pop-activation frame (save eval stack depth for return unwinding)
        interp.pushWorkFrame(newPopActivationFrame(savedReceiver, isBlock = false, evalStackDepth = interp.evalStack.len))

        # Push method body
        if currentMethod.body.len > 0:
          for i in countdown(currentMethod.body.len - 1, 0):
            if i < currentMethod.body.len - 1:
              interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
            interp.pushWorkFrame(newEvalFrame(currentMethod.body[i]))
        else:
          interp.pushValue(nilValue())

        return true
      else:
        # Class method not found - try instance methods on the Class class
        # This allows methods like asSelfDo: to work on class receivers
        let classReceiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)
        let instanceLookup = lookupMethod(interp, classReceiver, frame.selector)

        if instanceLookup.found:
          let currentMethod = instanceLookup.currentMethod
          debug("VM: Found instance method '", frame.selector, "' on Class class")

          # Handle native implementations
          if nativeImplIsSet(currentMethod):
            let savedReceiver = interp.currentReceiver
            interp.currentReceiver = classReceiver
            try:
              var resultVal: NodeValue
              if currentMethod.hasInterpreterParam:
                type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
                let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
                resultVal = nativeProc(interp, classReceiver, args)
              else:
                type NativeProc = proc(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
                let nativeProc = cast[NativeProc](currentMethod.nativeImpl)
                resultVal = nativeProc(classReceiver, args)
              interp.pushValue(resultVal)
            finally:
              interp.currentReceiver = savedReceiver
            return true

          # Interpreted method - create activation
          if currentMethod.parameters.len != args.len:
            raise newException(ValueError,
              "Wrong number of arguments: expected " & $currentMethod.parameters.len &
              ", got " & $args.len)

          let activation = newActivation(currentMethod, classReceiver, interp.currentActivation, instanceLookup.definingClass)

          for i in 0..<currentMethod.parameters.len:
            activation.locals[currentMethod.parameters[i]] = args[i]

          for tempName in currentMethod.temporaries:
            if tempName notin activation.locals:
              activation.locals[tempName] = nilValue()

          let savedReceiver = interp.currentReceiver
          interp.activationStack.add(activation)
          interp.currentActivation = activation
          interp.currentReceiver = classReceiver

          if currentMethod.isMethod:
            currentMethod.homeActivation = activation

          interp.pushWorkFrame(newPopActivationFrame(savedReceiver, isBlock = false, evalStackDepth = interp.evalStack.len))

          if currentMethod.body.len > 0:
            for i in countdown(currentMethod.body.len - 1, 0):
              if i < currentMethod.body.len - 1:
                interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
              interp.pushWorkFrame(newEvalFrame(currentMethod.body[i]))
          else:
            interp.pushValue(nilValue())

          return true
        else:
          # Instance method not found - try class methods on the class itself and Object
          # This allows class methods like selector:put: to work when called via self in blocks
          # First try the class itself, then try Object's class methods (inherited)
          var classMethodToRun: BlockNode = nil
          var classMethodDefiningClass: Class = nil

          let classMethodLookup = lookupClassMethod(cls, frame.selector)
          if classMethodLookup.found:
            classMethodToRun = classMethodLookup.currentMethod
            classMethodDefiningClass = classMethodLookup.definingClass
          elif objectClass != nil:
            let objectClassMethodLookup = lookupClassMethod(objectClass, frame.selector)
            if objectClassMethodLookup.found:
              classMethodToRun = objectClassMethodLookup.currentMethod
              classMethodDefiningClass = objectClassMethodLookup.definingClass

          if classMethodToRun != nil:
            debug("VM: Found class method '", frame.selector, "' for class ", cls.name)

            # Create class receiver wrapper
            let classReceiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)

            # Handle native implementations
            if nativeImplIsSet(classMethodToRun):
              let savedReceiver = interp.currentReceiver
              interp.currentReceiver = classReceiver
              try:
                var resultVal: NodeValue
                if classMethodToRun.hasInterpreterParam:
                  type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
                  let nativeProc = cast[NativeProcWithInterp](classMethodToRun.nativeImpl)
                  resultVal = nativeProc(interp, classReceiver, args)
                else:
                  type ClassMethodProc = proc(self: Class, args: seq[NodeValue]): NodeValue {.nimcall.}
                  let nativeProc = cast[ClassMethodProc](classMethodToRun.nativeImpl)
                  resultVal = nativeProc(cls, args)
                interp.pushValue(resultVal)
              finally:
                interp.currentReceiver = savedReceiver
              return true

            # Interpreted class method - create activation with class wrapper as receiver
            if classMethodToRun.parameters.len != args.len:
              raise newException(ValueError,
                "Wrong number of arguments: expected " & $classMethodToRun.parameters.len &
                ", got " & $args.len)

            let activation = newActivation(classMethodToRun, classReceiver, interp.currentActivation, classMethodDefiningClass, isClassMethod = true)

            for i in 0..<classMethodToRun.parameters.len:
              activation.locals[classMethodToRun.parameters[i]] = args[i]

            for tempName in classMethodToRun.temporaries:
              if tempName notin activation.locals:
                activation.locals[tempName] = nilValue()

            let savedReceiver = interp.currentReceiver
            interp.activationStack.add(activation)
            interp.currentActivation = activation
            interp.currentReceiver = classReceiver

            if classMethodToRun.isMethod:
              classMethodToRun.homeActivation = activation

            interp.pushWorkFrame(newPopActivationFrame(savedReceiver, isBlock = false, evalStackDepth = interp.evalStack.len))

            if classMethodToRun.body.len > 0:
              for i in countdown(classMethodToRun.body.len - 1, 0):
                if i < classMethodToRun.body.len - 1:
                  interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
                interp.pushWorkFrame(newEvalFrame(classMethodToRun.body[i]))
            else:
              interp.pushValue(nilValue())

            return true
          else:
            raise newException(ValueError, "Method not found: " & frame.selector)
    of vkBlock:
      # Create Block instance with the BlockNode stored in nimValue
      var blockInst: Instance
      new(blockInst)
      blockInst.kind = ikObject
      blockInst.class = blockClass
      blockInst.slots = @[]
      blockInst.isNimProxy = false
      blockInst.nimValue = cast[pointer](receiverVal.blockVal)
      receiver = blockInst
    of vkSymbol:
      receiver = newStringInstance(symbolClassCache, receiverVal.symVal)

    # Special stackless handling for control flow primitives
    # Native builds only: nimValue pointer operations
    if receiver.isNimProxy and receiver.kind == ikObject and receiver.class != nil:
        # Boolean ifTrue:/ifFalse: - use stackless work frames
        if (receiver.class == trueClassCache or receiver.class == falseClassCache) and args.len > 0 and args[0].kind == vkBlock:
          case frame.selector
          of "ifTrue:":
            let boolVal = cast[ptr bool](receiver.nimValue)[]
            if boolVal:
              # True - execute then block
              interp.pushWorkFrame(newIfBranchFrame(true, args[0].blockVal, nil))
            else:
              # False - push nil result
              interp.pushValue(nilValue())
            return true
          of "ifFalse:":
            let boolVal = cast[ptr bool](receiver.nimValue)[]
            if not boolVal:
              # False - execute then block (the block passed to ifFalse:)
              interp.pushWorkFrame(newIfBranchFrame(true, args[0].blockVal, nil))
            else:
              # True - push nil result
              interp.pushValue(nilValue())
            return true
          else:
            discard  # Fall through to regular method dispatch

    # Special stackless handling for block whileTrue:/whileFalse:
    if receiver.kind == ikObject and receiver.class == blockClass and not receiver.isNimProxy and args.len > 0 and args[0].kind == vkBlock:
      let conditionBlock = cast[BlockNode](receiver.nimValue)
      let bodyBlock = args[0].blockVal
      case frame.selector
      of "whileTrue:":
        # Evaluate condition first, then body if true
        interp.pushWorkFrame(newWhileLoopFrame(true, conditionBlock, bodyBlock, lsEvaluateCondition))
        return true
      of "whileFalse:":
        # Evaluate condition first, then body if false
        interp.pushWorkFrame(newWhileLoopFrame(false, conditionBlock, bodyBlock, lsEvaluateCondition))
        return true
      else:
        discard  # Fall through to regular method dispatch

    if receiver == nil:
      printStackTrace(interp)
      raise newException(ValueError, "Cannot send message to nil receiver for message: " & frame.selector)

    # ============================================================================
    # POLYMORPHIC INLINE CACHE (PIC) CHECK
    # Fast path: check MIC first, then PIC entries
    # ============================================================================
    var currentMethod: BlockNode = nil
    var definingClass: Class = nil
    var cacheHit = false

    if frame.msgNode != nil and not frame.msgNode.megamorphic:
      # Check Monomorphic Inline Cache (MIC) first
      if frame.msgNode.cachedClass != nil and
         receiver.class == frame.msgNode.cachedClass and
         receiver.class.version == frame.msgNode.cachedVersion:
        # MIC hit! Use cached method
        currentMethod = frame.msgNode.cachedMethod
        definingClass = frame.msgNode.cachedClass
        cacheHit = true
        debug("VM: MIC cache hit for '", frame.selector, "' on ", receiver.class.name)
      else:
        # MIC miss - check Polymorphic Inline Cache (PIC)
        for i in 0..<frame.msgNode.picCount:
          if receiver.class == frame.msgNode.picEntries[i].cls and
             receiver.class.version == frame.msgNode.picEntries[i].version:
            # PIC hit - promote to MIC (swap for LRU behavior)
            let oldMIC = (
              cls: frame.msgNode.cachedClass,
              meth: frame.msgNode.cachedMethod,
              version: frame.msgNode.cachedVersion
            )
            currentMethod = frame.msgNode.picEntries[i].meth
            definingClass = frame.msgNode.picEntries[i].cls
            # Promote PIC entry to MIC
            frame.msgNode.cachedClass = frame.msgNode.picEntries[i].cls
            frame.msgNode.cachedMethod = frame.msgNode.picEntries[i].meth
            frame.msgNode.cachedVersion = frame.msgNode.picEntries[i].version
            # Move old MIC to vacated PIC slot
            if oldMIC.cls != nil:
              frame.msgNode.picEntries[i] = oldMIC
            cacheHit = true
            debug("VM: PIC cache hit for '", frame.selector, "' on ", receiver.class.name, " at index ", $i, " (promoted to MIC)")
            break

        if not cacheHit and frame.msgNode.cachedClass != nil:
          # Cache miss - will update cache after lookup
          debug("VM: PIC cache miss for '", frame.selector, "' expected ",
                frame.msgNode.cachedClass.name, " got ", receiver.class.name)

    if not cacheHit:
      # ============================================================================
      # SLOW PATH: Full method lookup
      # ============================================================================
      debug("VM: Looking up method '", frame.selector, "' on ", (if receiver.class != nil: receiver.class.name else: "nil"), " isClassMethod=", $frame.isClassMethod)

      var lookup: MethodResult
      if frame.isClassMethod:
        # For class method primitives, look in the receiver's class methods
        if receiver.class == nil:
          debug("VM: ERROR - receiver.class is nil for class method lookup")
          raise newException(ValueError, "Cannot lookup class method on receiver with nil class")
        lookup = lookupClassMethod(receiver.class, frame.selector)
      else:
        lookup = lookupMethod(interp, receiver, frame.selector)
      if not lookup.found:
        # Try doesNotUnderstand: before raising error
        debug("VM: Method not found, trying DNU for ", frame.selector)
        let dnuLookup = lookupMethod(interp, receiver, "doesNotUnderstand:")
        debug("VM: DNU lookup result: found=", $dnuLookup.found, " class=", (if dnuLookup.definingClass != nil: dnuLookup.definingClass.name else: "nil"))
        if dnuLookup.found:
          let selectorVal = NodeValue(kind: vkSymbol, symVal: frame.selector)
          let dnuResult = executeMethod(interp, dnuLookup.currentMethod, receiver, @[selectorVal], dnuLookup.definingClass)
          interp.pushValue(dnuResult)
          return true
        printStackTrace(interp)
        raise newException(ValueError, "Method not found: " & frame.selector & " on " &
          (if receiver.class != nil: receiver.class.name else: "unknown"))

      currentMethod = lookup.currentMethod
      definingClass = lookup.definingClass

      # Update inline cache for future calls (skip for megamorphic sites)
      if frame.msgNode != nil and not frame.msgNode.megamorphic:
        # If MIC already has a different class, move it to PIC (polymorphic cache)
        if frame.msgNode.cachedClass != nil and frame.msgNode.cachedClass != receiver.class:
          if frame.msgNode.picCount < frame.msgNode.picEntries.len:
            # Add old MIC entry to PIC
            frame.msgNode.picEntries[frame.msgNode.picCount] = (
              cls: frame.msgNode.cachedClass,
              meth: frame.msgNode.cachedMethod,
              version: frame.msgNode.cachedVersion
            )
            frame.msgNode.picCount += 1
            debug("VM: Added to PIC for '", frame.selector, "' ", frame.msgNode.cachedClass.name,
                  " (PIC count: ", $frame.msgNode.picCount, ")")
          else:
            # PIC is full - mark as megamorphic, skip all caching
            frame.msgNode.megamorphic = true
            debug("VM: PIC full for '", frame.selector, "', marked megamorphic")

        # Update MIC with new class/method
        if not frame.msgNode.megamorphic:
          frame.msgNode.cachedClass = receiver.class
          frame.msgNode.cachedMethod = currentMethod
          frame.msgNode.cachedVersion = receiver.class.version
          debug("VM: Updated MIC cache for '", frame.selector, "' with ", receiver.class.name)

    # Check for native implementation
    # currentMethod is set either from cache (cacheHit) or from lookup (slow path)
    debug("VM: Found method '", frame.selector, "', native=", nativeImplIsSet(currentMethod))
    if nativeImplIsSet(currentMethod):
      # Call native method
      debug("VM: Calling native method '", frame.selector, "'")
      let savedReceiver = interp.currentReceiver
      try:
        var resultVal: NodeValue
        if currentMethod.hasInterpreterParam:
          debug("VM: Native method has interpreter param, nativeImpl=", cast[int](currentMethod.nativeImpl))
          type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
          let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
          debug("VM: About to call nativeProc, receiver=", (if receiver != nil: receiver.class.name else: "nil"))
          resultVal = nativeProc(interp, receiver, args)
          debug("VM: Native method returned: ", resultVal.toString())
        else:
          type NativeProc = proc(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
          let nativeProc = cast[NativeProc](currentMethod.nativeImpl)
          resultVal = nativeProc(receiver, args)
        interp.pushValue(resultVal)
      finally:
        interp.currentReceiver = savedReceiver
      return true

    # Interpreted method - create activation and execute body
    debug("VM: Executing interpreted method '", frame.selector, "' with ", args.len, " args, body has ", currentMethod.body.len, " statements")

    # Check parameter count
    if currentMethod.parameters.len != args.len:
      raise newException(ValueError,
        "Wrong number of arguments: expected " & $currentMethod.parameters.len &
        ", got " & $args.len)

    # Create activation
    let activation = newActivation(currentMethod, receiver, interp.currentActivation, definingClass)

    # Bind parameters
    for i in 0..<currentMethod.parameters.len:
      activation.locals[currentMethod.parameters[i]] = args[i]

    # Save current receiver to restore after method completes
    let savedReceiver = interp.currentReceiver

    # Push activation
    interp.activationStack.add(activation)
    interp.currentActivation = activation
    interp.currentReceiver = receiver

    # Set home activation for methods
    if currentMethod.isMethod:
      currentMethod.homeActivation = activation

    # Push pop-activation frame FIRST (will execute LAST after body completes)
    interp.pushWorkFrame(newPopActivationFrame(savedReceiver, isBlock = false, evalStackDepth = interp.evalStack.len))

    # Push method body statements in reverse order
    if currentMethod.body.len > 0:
      for i in countdown(currentMethod.body.len - 1, 0):
        if i < currentMethod.body.len - 1:
          # Pop intermediate results (keep only last statement's result)
          interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
        interp.pushWorkFrame(newEvalFrame(currentMethod.body[i]))
    else:
      # Empty body returns nil
      interp.pushValue(nilValue())

    return true

  of wfApplyBlock:
    # Apply block with args on stack OR from pre-bound blockArgs
    let args = if frame.blockArgs.len > 0:
                 frame.blockArgs  # Use pre-bound args (e.g., from exception handler)
               else:
                 interp.popValues(frame.argCount)  # Pop from eval stack
    let blockNode = frame.blockVal

    # Check argument count
    if blockNode.parameters.len != args.len:
      raise newException(ValueError,
        "Wrong number of arguments to block: expected " & $blockNode.parameters.len &
        ", got " & $args.len)

    # Block's home activation determines 'self'
    let blockHome = blockNode.homeActivation
    let blockReceiver = if blockHome != nil and blockHome.receiver != nil:
                          blockHome.receiver
                        else:
                          interp.currentReceiver

    # Create activation
    let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

    # Bind captured environment
    if blockNode.capturedEnvInitialized and blockNode.capturedEnv.len > 0:
      for name, cell in blockNode.capturedEnv:
        activation.locals[name] = cell.value

    # Bind parameters
    for i in 0..<blockNode.parameters.len:
      activation.locals[blockNode.parameters[i]] = args[i]

    # Initialize temporaries
    for tempName in blockNode.temporaries:
      activation.locals[tempName] = nilValue()

    # Save current receiver to restore after block completes
    let savedReceiver = interp.currentReceiver

    # Push activation
    interp.activationStack.add(activation)
    interp.currentActivation = activation
    interp.currentReceiver = blockReceiver

    # Push pop-activation frame FIRST (will execute LAST after body completes)
    # Store the block in the frame so we can save captured vars back
    var popFrame = newPopActivationFrame(savedReceiver, isBlock = true, evalStackDepth = interp.evalStack.len)
    popFrame.blockVal = blockNode
    interp.pushWorkFrame(popFrame)

    # Push block body statements in reverse order
    if blockNode.body.len > 0:
      for i in countdown(blockNode.body.len - 1, 0):
        if i < blockNode.body.len - 1:
          interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
        interp.pushWorkFrame(newEvalFrame(blockNode.body[i]))
    else:
      # Empty body returns nil
      interp.pushValue(nilValue())

    return true

  of wfPopActivation:
    # Pop activation after method/block body completes
    # In Smalltalk, methods without explicit ^ return self
    # Blocks return the value of the last expression
    debug("VM: wfPopActivation, evalStack.len=", interp.evalStack.len, " isBlock=", $frame.isBlockActivation)

    # Check for non-local return first
    if interp.currentActivation != nil and interp.currentActivation.hasReturned:
      # Non-local return - propagate the return value
      let returnVal = interp.currentActivation.returnValue

      # Pop the activation
      discard interp.activationStack.pop()
      if interp.activationStack.len > 0:
        interp.currentActivation = interp.activationStack[^1]
        interp.currentReceiver = interp.currentActivation.receiver
      else:
        interp.currentActivation = nil
        interp.currentReceiver = frame.savedReceiver

      interp.pushValue(returnVal.unwrap())
    else:
      # Normal completion - get return value BEFORE popping activation
      var resultValue: NodeValue
      if frame.isBlockActivation:
        # Blocks return the value of the last expression
        if interp.evalStack.len > 0:
          resultValue = interp.popValue()
        else:
          resultValue = nilValue()
      else:
        # Methods without explicit ^ return self
        # Pop any leftover values from the stack (expressions that were evaluated)
        if interp.evalStack.len > frame.savedEvalStackDepth:
          discard interp.popValue()
        # Return self (the receiver of the method being popped)
        # Must get this BEFORE popping the activation
        if interp.currentActivation != nil and interp.currentActivation.receiver != nil:
          resultValue = interp.currentActivation.receiver.toValue().unwrap()
        else:
          resultValue = nilValue()

      # Now pop the activation
      discard interp.activationStack.pop()
      if interp.activationStack.len > 0:
        interp.currentActivation = interp.activationStack[^1]
        interp.currentReceiver = interp.currentActivation.receiver
      else:
        interp.currentActivation = nil
        interp.currentReceiver = frame.savedReceiver

      interp.pushValue(resultValue.unwrap())

    return true

  of wfReturnValue:
    # Handle return (^ expression) - must unwind work queue to target activation
    let value = if frame.returnValue.kind != vkNil:
                  frame.returnValue
                else:
                  interp.popValue()
    let returnVal = value.unwrap()

    # Find target activation for the return
    # For blocks, target is homeActivation (the enclosing method)
    # For methods, target is the current activation
    var targetActivation: Activation = nil
    if interp.currentActivation != nil and interp.currentActivation.currentMethod != nil:
      let currentMethod = interp.currentActivation.currentMethod
      if not currentMethod.isMethod and currentMethod.homeActivation != nil:
        targetActivation = currentMethod.homeActivation
      else:
        targetActivation = interp.currentActivation

    if targetActivation == nil:
      # No target - just push value (shouldn't happen in well-formed code)
      interp.pushValue(returnVal)
      return true

    # Check if target activation is still on the stack (handles escaped blocks
    # where the home method has already returned)
    var targetOnStack = false
    for i in 0..<interp.activationStack.len:
      if interp.activationStack[i] == targetActivation:
        targetOnStack = true
        break

    if not targetOnStack:
      # Target method already returned (escaped block with non-local return).
      # Treat as local return: set hasReturned on current activation so
      # wfPopActivation will propagate the value up correctly.
      if interp.currentActivation != nil:
        interp.currentActivation.hasReturned = true
        interp.currentActivation.returnValue = returnVal
      interp.pushValue(returnVal)
      return true

    # Unwind: pop work frames until we find and process the wfPopActivation
    # for the target activation. For each intermediate wfPopActivation (blocks),
    # pop the corresponding activation from the activation stack.
    debug("VM: wfReturnValue unwinding to target activation")
    var found = false
    var targetEvalStackDepth = 0
    while interp.workQueue.len > 0 and not found:
      let wf = interp.workQueue.pop()
      if wf.kind == wfPopActivation:
        # Check if the current activation is the target
        if interp.currentActivation == targetActivation:
          # Save the eval stack depth to restore to
          targetEvalStackDepth = wf.savedEvalStackDepth

          # Pop the target activation
          discard interp.activationStack.pop()
          if interp.activationStack.len > 0:
            interp.currentActivation = interp.activationStack[^1]
            interp.currentReceiver = interp.currentActivation.receiver
          else:
            interp.currentActivation = nil
            interp.currentReceiver = wf.savedReceiver
          found = true
        else:
          # Pop intermediate activation (block)
          if interp.activationStack.len > 0:
            discard interp.activationStack.pop()
            if interp.activationStack.len > 0:
              interp.currentActivation = interp.activationStack[^1]
              interp.currentReceiver = interp.currentActivation.receiver

    # Restore eval stack to the depth before the target activation was pushed
    if interp.evalStack.len > targetEvalStackDepth:
      interp.evalStack.setLen(targetEvalStackDepth)
    interp.pushValue(returnVal)
    return true

  of wfCascade:
    # Cascade - receiver is on stack, send each message to same receiver
    let receiverVal = interp.peekValue()  # Keep receiver on stack for next message
    let messages = frame.cascadeMessages

    if messages.len == 0:
      # No messages to send, just leave receiver on stack as result
      return true

    # Pop the receiver for processing (we'll push results back)
    discard interp.popValue()

    # Save original receiver and set cascade receiver
    let savedReceiver = interp.currentReceiver

    # Convert receiverVal to Instance
    var receiver: Instance
    case receiverVal.kind
    of vkInstance:
      receiver = receiverVal.instVal
    of vkInt:
      receiver = newIntInstance(integerClass, receiverVal.intVal)
    of vkFloat:
      receiver = newFloatInstance(floatClass, receiverVal.floatVal)
    of vkString:
      receiver = newStringInstance(stringClass, receiverVal.strVal)
    of vkArray:
      receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
    of vkTable:
      receiver = newTableInstance(tableClass, receiverVal.tableVal)
    of vkBool:
      var boolInst: Instance
      new(boolInst)
      boolInst.kind = ikObject
      boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
      boolInst.slots = @[]
      let p = cast[pointer](alloc(sizeof(bool)))
      cast[ptr bool](p)[] = receiverVal.boolVal
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
      var classInst: Instance
      new(classInst)
      classInst.kind = ikObject
      classInst.class = objectClass
      classInst.slots = @[]
      classInst.isNimProxy = false
      classInst.nimValue = cast[pointer](receiverVal.classVal)
      receiver = classInst
    else:
      raise newException(ValueError, "Cascade to unsupported value kind: " & $receiverVal.kind)

    # Set current receiver for message sends
    interp.currentReceiver = receiver

    # For now, handle single message (push result) or loop for all messages
    # To properly handle multiple messages without recursion, we need to:
    # 1. Push frames for each message in reverse order
    # 2. Each message will leave its result on stack
    # 3. Only keep the last result

    if messages.len == 1:
      # Single message - just send it
      let msg = messages[0]
      interp.pushWorkFrame(WorkFrame(
        kind: wfAfterReceiver,
        pendingSelector: msg.selector,
        pendingArgs: msg.arguments,
        currentArgIndex: 0
      ))
      interp.pushValue(receiverVal)  # Push receiver back for the message send
    else:
      # Multiple messages - push them in reverse order with cascade continuation
      # Push a final frame to restore receiver and keep only last result
      interp.pushWorkFrame(WorkFrame(kind: wfRestoreReceiver, savedReceiver: savedReceiver))

      # Push all message frames in reverse order
      for i in countdown(messages.len - 1, 0):
        let msg = messages[i]
        if i == messages.len - 1:
          # Last message - keep its result
          interp.pushWorkFrame(WorkFrame(
            kind: wfCascadeMessage,
            pendingSelector: msg.selector,
            pendingArgs: msg.arguments,
            currentArgIndex: 0,
            cascadeReceiver: receiverVal  # Store receiver for this message
          ))
        else:
          # Intermediate message - discard result, keep receiver
          interp.pushWorkFrame(WorkFrame(
            kind: wfCascadeMessageDiscard,
            pendingSelector: msg.selector,
            pendingArgs: msg.arguments,
            currentArgIndex: 0,
            cascadeReceiver: receiverVal
          ))

    return true

  of wfBuildArray:
    # Build array from N values on stack
    let count = frame.argCount
    var elements = newSeq[NodeValue](count)
    # Pop in reverse order to maintain original order
    for i in countdown(count - 1, 0):
      elements[i] = interp.popValue()
    if arrayClass != nil:
      interp.pushValue(newArrayInstance(arrayClass, elements).toValue())
    else:
      interp.pushValue(NodeValue(kind: vkArray, arrayVal: elements))
    return true

  of wfBuildTable:
    # Build table from key-value pairs on stack
    # Stack has: ... key1 value1 key2 value2 ... (in reverse order of pushing)
    # We need to pop values in pairs and build the table
    let pairCount = frame.argCount div 2
    var entries = initTable[NodeValue, NodeValue]()
    for i in 0..<pairCount:
      let value = interp.popValue()
      let key = interp.popValue()
      entries[key] = value
    if tableClass != nil:
      interp.pushValue(newTableInstance(tableClass, entries).toValue())
    else:
      interp.pushValue(NodeValue(kind: vkTable, tableVal: entries))
    return true

  of wfCascadeMessage, wfCascadeMessageDiscard:
    # Send a message in a cascade - receiver is stored in cascadeReceiver
    let receiverVal = frame.cascadeReceiver

    # Convert receiver to Instance
    var receiver: Instance
    case receiverVal.kind
    of vkInstance:
      receiver = receiverVal.instVal
    of vkInt:
      receiver = newIntInstance(integerClass, receiverVal.intVal)
    of vkFloat:
      receiver = newFloatInstance(floatClass, receiverVal.floatVal)
    of vkString:
      receiver = newStringInstance(stringClass, receiverVal.strVal)
    of vkArray:
      receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
    of vkTable:
      receiver = newTableInstance(tableClass, receiverVal.tableVal)
    of vkBool:
      var boolInst: Instance
      new(boolInst)
      boolInst.kind = ikObject
      boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
      boolInst.slots = @[]
      let p = cast[pointer](alloc(sizeof(bool)))
      cast[ptr bool](p)[] = receiverVal.boolVal
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
      var classInst: Instance
      new(classInst)
      classInst.kind = ikObject
      classInst.class = objectClass
      classInst.slots = @[]
      classInst.isNimProxy = false
      classInst.nimValue = cast[pointer](receiverVal.classVal)
      receiver = classInst
    else:
      raise newException(ValueError, "Cascade to unsupported value kind: " & $receiverVal.kind)

    # Set current receiver
    interp.currentReceiver = receiver

    # Push receiver value for message send
    interp.pushValue(receiverVal)

    # Now handle arguments and send message
    if frame.pendingArgs.len == 0:
      interp.pushWorkFrame(newSendMessageFrame(frame.pendingSelector, 0))
    else:
      interp.pushWorkFrame(newAfterArgFrame(frame.pendingSelector, frame.pendingArgs, 0))
      interp.pushWorkFrame(newEvalFrame(frame.pendingArgs[0]))
    return true

  of wfRestoreReceiver:
    # Restore original receiver after cascade completes
    interp.currentReceiver = frame.savedReceiver
    return true

  of wfIfBranch:
    # Handle conditional branch (ifTrue: or ifFalse:)
    if frame.conditionResult:
      # Condition is true - execute then block
      interp.pushWorkFrame(newApplyBlockFrame(frame.thenBlock, 0))
    elif frame.elseBlock != nil:
      # Condition is false - execute else block
      interp.pushWorkFrame(newApplyBlockFrame(frame.elseBlock, 0))
    else:
      # No else block - return nil
      interp.pushValue(nilValue())
    return true

  of wfWhileLoop:
    # Handle while loop (whileTrue: or whileFalse:)
    case frame.loopState
    of lsEvaluateCondition:
      # Push frame to check condition after it's evaluated
      interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                      conditionBlock: frame.conditionBlock,
                                      bodyBlock: frame.bodyBlock,
                                      loopState: lsCheckCondition))
      interp.pushWorkFrame(newApplyBlockFrame(frame.conditionBlock, 0))
      return true
    of lsCheckCondition:
      # Check the condition result on the stack
      let conditionResult = interp.peekValue()
      let condBool = conditionResult.isTruthy()
      let shouldContinue = if frame.loopKind: condBool else: not condBool
      discard interp.popValue()  # Clean up condition result
      if shouldContinue:
        # Continue loop - execute body
        interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                        conditionBlock: frame.conditionBlock,
                                        bodyBlock: frame.bodyBlock,
                                        loopState: lsExecuteBody))
        interp.pushWorkFrame(newApplyBlockFrame(frame.bodyBlock, 0))
      else:
        # Loop done - push nil result
        interp.pushValue(nilValue())
      return true
    of lsExecuteBody:
      # Transition to lsLoopBody state (will be used after body completes)
      interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                      conditionBlock: frame.conditionBlock,
                                      bodyBlock: frame.bodyBlock,
                                      loopState: lsLoopBody))
      return true
    of lsLoopBody:
      # Body completed - discard body result and loop back to condition
      discard interp.popValue()
      interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                      conditionBlock: frame.conditionBlock,
                                      bodyBlock: frame.bodyBlock,
                                      loopState: lsEvaluateCondition))
      return true
    of lsDone:
      return true

  of wfPushHandler:
    # Push exception handler onto handler stack
    # At this point, work queue has [...][wfPopHandler][wfApplyBlock(protected)]
    # We save depth excluding wfPopHandler+wfApplyBlock so we can unwind on exception
    let handler = ExceptionHandler(
      exceptionClass: frame.exceptionClass,
      handlerBlock: frame.handlerBlock,
      activation: interp.currentActivation,
      stackDepth: interp.activationStack.len,
      workQueueDepth: interp.workQueue.len - 2,  # Depth before wfPopHandler and wfApplyBlock
      evalStackDepth: interp.evalStack.len
    )
    interp.exceptionHandlers.add(handler)
    debug("VM: wfPushHandler pushed handler for ", frame.exceptionClass.name)
    return true

  of wfPopHandler:
    # Pop exception handler from handler stack
    # Remove handlers whose activation has exited (current depth < handler's depth)
    # Also remove handlers that were consumed (used to catch an exception)
    if interp.exceptionHandlers.len > 0:
      var i = 0
      while i < interp.exceptionHandlers.len:
        let handler = interp.exceptionHandlers[i]
        if handler.consumed:
          # Handler was used to catch an exception, remove it from stack
          interp.exceptionHandlers.del(i)
          debug("VM: wfPopHandler removed consumed handler")
        elif interp.activationStack.len < handler.stackDepth:
          # Handler's activation has exited, remove it
          interp.exceptionHandlers.del(i)
          debug("VM: wfPopHandler removed handler with exited activation, handlerDepth=", handler.stackDepth, " currentDepth=", interp.activationStack.len)
        else:
          i += 1
    return true

  of wfSignalException:
    # Signal exception - this is handled by primitiveSignalImpl
    # which schedules the handler block directly
    # This case should not normally be reached
    debug("VM: wfSignalException - should be handled by primitiveSignalImpl")
    return true

  of wfEvalNode:
    # Should not reach here - wfEvalNode is handled in handleEvalNode
    return handleEvalNode(interp, frame)

# Main execution loop
proc runASTInterpreter*(interp: var Interpreter): VMResult =
  ## Main execution loop for the explicit stack AST interpreter
  ## Returns when:
  ## - Work queue is empty (vmCompleted)
  ## - Processor yields (vmYielded)
  ## - Error occurs (vmError)

  {.computedGoto.}  # Optimize case statement dispatch
  while interp.hasWorkFrames():
    # Check for yield
    if interp.shouldYield:
      interp.shouldYield = false
      return VMResult(status: vmYielded, value: interp.peekValue())

    let frame = interp.popWorkFrame()
    debug("VM: Processing frame kind=", frame.kind)

    try:
      let shouldContinue = case frame.kind
        of wfEvalNode:
          handleEvalNode(interp, frame)
        else:
          handleContinuation(interp, frame)

      if not shouldContinue:
        break
    except ValueError as e:
      return VMResult(status: vmError, error: e.msg)
    except Exception as e:
      return VMResult(status: vmError, error: "VM error: " & e.msg)

  # Execution complete
  let resultValue = if interp.evalStack.len > 0:
                      interp.evalStack[^1]
                    else:
                      nilValue()

  return VMResult(status: vmCompleted, value: resultValue)

# Entry point to evaluate an expression using the new VM
proc evalWithVM*(interp: var Interpreter, node: Node): NodeValue =
  ## Evaluate an expression using the explicit stack VM
  ## Handles re-entrancy by saving/restoring VM state for nested calls
  if node == nil:
    return nilValue()

  # Save current VM state for re-entrancy support
  let savedWorkQueue = interp.workQueue
  let savedEvalStack = interp.evalStack

  # Initialize fresh VM state for this evaluation
  interp.workQueue = @[newEvalFrame(node)]
  interp.evalStack = @[]

  # Run the VM
  let vmResult = interp.runASTInterpreter()

  # Get result before restoring state
  let resultValue = case vmResult.status
    of vmCompleted, vmYielded:
      vmResult.value
    of vmError:
      raise newException(ValueError, vmResult.error)
    of vmRunning:
      nilValue()

  # Restore previous VM state
  interp.workQueue = savedWorkQueue
  interp.evalStack = savedEvalStack

  return resultValue

proc evalWithVMCleanContext*(interp: var Interpreter, node: Node): NodeValue =
  ## Evaluate an expression with a clean activation context.
  ## This saves and clears the activation stack before evaluation,
  ## then restores it afterwards. Use this for external callbacks
  ## (like GTK signals) that need isolated block execution.
  if node == nil:
    return nilValue()

  # Save activation context
  let savedActivationStack = interp.activationStack
  let savedCurrentActivation = interp.currentActivation
  let savedCurrentReceiver = interp.currentReceiver

  # Clear activation context for clean evaluation
  interp.activationStack = @[]
  interp.currentActivation = nil
  interp.currentReceiver = nil

  # Evaluate with clean context
  let result = interp.evalWithVM(node)

  # Restore activation context
  interp.activationStack = savedActivationStack
  interp.currentActivation = savedCurrentActivation
  interp.currentReceiver = savedCurrentReceiver

  return result

proc doit*(interp: var Interpreter, source: string, dumpAst = false): (NodeValue, string) =
  ## Parse and evaluate source code using the stackless VM
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

  # Evaluate all nodes using stackless VM, return last result
  try:
    var lastResult = nilValue()
    for node in nodes:
      lastResult = interp.evalWithVM(node)
    interp.lastResult = lastResult
    return (lastResult, "")
  except ValueError:
    raise
  except EvalError as e:
    return (nilValue(), "Runtime error: " & e.msg)
  except Exception as e:
    return (nilValue(), "Error: " & e.msg)

proc evalStatements*(interp: var Interpreter, source: string): (seq[NodeValue], string) =
  ## Parse and evaluate multiple statements using the stackless VM
  ## Creates a top-level activation so lowercase variables work as locals
  let tokens = lex(source)
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()

  if parser.hasError:
    return (@[], "Parse error: " & parser.errorMsg)

  var results = newSeq[NodeValue]()

  if nodes.len > 0:
    # Create a top-level block activation to hold local variables
    # This matches the old evalStatements behavior where lowercase names
    # are locals (not globals)
    let topLevelBlock = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: nodes,
      isMethod: true,  # Mark as method so non-local returns work correctly
      capturedEnv: initTable[string, MutableCell](),
      capturedEnvInitialized: true
    )
    let activation = newActivation(topLevelBlock, interp.currentReceiver, interp.currentActivation)
    interp.activationStack.add(activation)
    let savedActivation = interp.currentActivation
    interp.currentActivation = activation

    try:
      for node in nodes:
        let evalResult = interp.evalWithVM(node)
        results.add(evalResult)
    except ValueError as e:
      discard interp.activationStack.pop()
      interp.currentActivation = savedActivation
      return (@[], "Error: " & e.msg)
    except EvalError as e:
      discard interp.activationStack.pop()
      interp.currentActivation = savedActivation
      return (@[], "Runtime error: " & e.msg)
    except Exception as e:
      discard interp.activationStack.pop()
      interp.currentActivation = savedActivation
      return (@[], "Error: " & e.msg)

    discard interp.activationStack.pop()
    interp.currentActivation = savedActivation

  return (results, "")

proc evalScriptBlock*(interp: var Interpreter, source: string): (NodeValue, string) =
  ## Evaluate source as a block with self = nil (Smalltalk workspace convention)
  ## Source should be wrapped in [ ... ] by the caller
  ## This allows temporary variable declarations like | counter total |
  let tokens = lex(source)
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()

  if parser.hasError:
    return (nilValue(), "Parse error: " & parser.errorMsg)

  if nodes.len == 0:
    return (nilValue(), "No expression to evaluate")

  # We expect a single block node
  var blockNode: BlockNode
  if nodes.len == 1 and nodes[0].kind == nkBlock:
    blockNode = nodes[0].BlockNode
  else:
    return (nilValue(), "Expected a single block expression")

  try:
    let savedReceiver = interp.currentReceiver
    interp.currentReceiver = nilInstance

    let blockResult = interp.invokeBlock(blockNode, @[])

    interp.currentReceiver = savedReceiver

    return (blockResult, "")
  except EvalError as e:
    return (nilValue(), "Runtime error: " & e.msg)
  except Exception as e:
    return (nilValue(), "Error: " & e.msg)

proc evalForProcess*(interp: var Interpreter, node: Node): (NodeValue, VMStatus) =
  ## Evaluate a node for a process, preserving VM state across yields.
  ## This is used by the scheduler to execute one statement at a time,
  ## allowing proper yield/resume semantics.
  ##
  ## If node is nil and work queue has pending frames, continues from work queue.
  ## If node is not nil and work queue is empty, pushes node onto work queue.
  ##
  ## Returns (value, status) where status indicates if the VM yielded,
  ## completed, or encountered an error.
  if node == nil and interp.workQueue.len == 0:
    return (nilValue(), vmCompleted)

  # If work queue is empty, push the new node
  if interp.workQueue.len == 0:
    interp.workQueue.add(newEvalFrame(node))
  # If work queue has pending work (resuming from yield), continue execution
  # without pushing a new frame

  # Run the VM (continues from where it left off if resuming)
  let vmResult = interp.runASTInterpreter()

  return (vmResult.value, vmResult.status)
