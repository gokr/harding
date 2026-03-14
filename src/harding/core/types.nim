import std/[tables, logging, hashes, strutils, options]
import ./tagged  # Tagged value support for VM performance

# ============================================================================
# Logging Templates
# debug/warn: eliminated in release builds, controlled by --loglevel in debug
# error: always active (errors should always be logged)
# These wrap std/logging so other modules don't need to import it directly.
# ============================================================================

when defined(release):
  template debug*(args: varargs[string, `$`]) = discard
  template warn*(args: varargs[string, `$`]) = discard
else:
  template debug*(args: varargs[string, `$`]) =
    logging.debug(args)
  template warn*(args: varargs[string, `$`]) =
    logging.warn(args)

template error*(args: varargs[string, `$`]) =
  logging.error(args)

# ============================================================================
# Core Types for Harding
# ============================================================================

# All type definitions in a single section to allow forward declarations
# Note: {.acyclic.} pragmas are used to prevent ORC cycle detection issues
# when objects form reference cycles (which is common in an interpreter).
# See CLAUDE.md for details on ORC issues.
type
  # Node kind enum - defined before Node for use as stored field
  NodeKind* = enum
    nkLiteral, nkIdent, nkMessage, nkBlock, nkAssign, nkReturn,
    nkArray, nkTable, nkObjectLiteral, nkPrimitive, nkPrimitiveCall, nkCascade,
    nkSlotAccess, nkNamedAccess, nkSuperSend, nkPseudoVar,
    nkIf, nkWhile  # Control flow specialization nodes

  Node* {.acyclic.} = ref object of RootObj
    line*, col*: int

  # ============================================================================
  # Object Model
  # ============================================================================

  InstanceKind* = enum
    ikObject       # Regular object with slots
    ikArray        # Array with dynamic element storage
    ikTable        # Table with key-value storage
    ikInt          # Integer instance (optimized)
    ikFloat        # Float instance (optimized)
    ikString       # String instance (optimized)

  Class* {.acyclic.} = ref object of RootObj
    ## Class object - defines structure and behavior for instances
    # Instance methods (methods that instances of this class will have)
    methods*: Table[string, BlockNode]      # Methods defined on this class only
    allMethods*: Table[string, BlockNode]   # All methods including inherited (for fast lookup)

    # Class methods (methods called on the class itself, like 'new', 'derive:')
    classMethods*: Table[string, BlockNode]     # Class methods defined on this class
    allClassMethods*: Table[string, BlockNode]  # All class methods including inherited

    # Slots
    slotNames*: seq[string]                 # Slot names defined on this class only
    allSlotNames*: seq[string]              # All slots including inherited (instance layout)
    readableSlotNames*: seq[string]         # Slots readable through direct access syntax
    writableSlotNames*: seq[string]         # Slots writable through direct access syntax

    # Inheritance
    superclasses*: seq[Class]               # Direct superclasses
    subclasses*: seq[Class]                 # Direct children (for efficient invalidation)

    # Metadata
    name*: string                           # Class name for debugging/reflection
    tags*: seq[string]                      # Type tags
    isNimProxy*: bool                       # Class wraps Nim type
    hardingType*: string                    # Nim type name for FFI
    hasSlots*: bool                         # Has any slots
    conflictSelectors*: seq[string]         # Instance selectors with parent conflicts
    classConflictSelectors*: seq[string]    # Class selectors with parent conflicts

    # Lazy rebuilding flag
    methodsDirty*: bool                     # True if method tables need rebuilding

    # Version counter for inline cache invalidation
    version*: int                           # Incremented when methods change

  Instance* = ref object of RootObj
    ## Instance object - pure data with reference to its class
    ## Using case object variant for memory efficiency - only allocate fields needed
    class*: Class                           # Reference to class
    case kind*: InstanceKind
    of ikObject:
      slots*: seq[NodeValue]                # Instance variables (size = class.allSlotNames.len)
    of ikArray:
      elements*: seq[NodeValue]             # Array elements
    of ikTable:
      entries*: Table[NodeValue, NodeValue]    # Table entries
    of ikInt:
      intVal*: int                          # Direct storage (no boxing)
    of ikFloat:
      floatVal*: float                      # Direct storage
    of ikString:
      strVal*: string                       # Direct storage
    isNimProxy*: bool                       # Instance wraps Nim value
    nimValue*: pointer                      # Pointer to actual Nim value (for FFI)

  # Mutable cell for captured variables (shared between closures)
  MutableCell* = ref object
    value*: NodeValue          # the captured value

  # Forward declarations to break circular dependency
  Activation* = ref ActivationObj

  # ============================================================================
  # Exception Context for Smalltalk-Style Debugging
  # Preserves full signal point state for debugging and resumption
  # ============================================================================

  ExceptionContext* = ref object
    ## Captures complete VM state at exception signal point
    ## Enables Smalltalk-style debugging with stack preservation
    signalActivation*: Activation       # Activation where signal was sent
    handlerActivation*: Activation      # Activation where handler is installed
    signaler*: Instance                 # self at signal point
    signalerContext*: Activation        # First non-Exception sender (for debugging)
    signalWorkQueue*: seq[WorkFrame]    # Work queue snapshot at signal
    signalEvalStack*: seq[NodeValue]    # Eval stack snapshot at signal
    signalActivationDepth*: int         # Activation stack depth at signal
    isResumable*: bool                  # Can this exception be resumed?
    hasBeenResumed*: bool               # Track if already resumed
    outerContext*: ExceptionContext     # For #outer message support
    exceptionInstance*: Instance        # The exception instance

  # Exception handler record for on:do: mechanism
  # Using ref object for proper ARC memory management with contained ref fields
  ExceptionHandler* = ref object
    exceptionClass*: Class    # The exception class to catch
    handlerBlock*: BlockNode        # Block to execute when caught
    activation*: Activation         # Activation where handler was installed
    stackDepth*: int                # Activation stack depth when handler installed
    workQueueDepth*: int            # Work queue depth to restore on exception (before wfPopHandler)
    evalStackDepth*: int            # Eval stack depth to restore on exception
    consumed*: bool                 # True if handler was already used to catch an exception
    protectedBlock*: BlockNode      # Protected block (for retry)
    exceptionInstance*: Instance    # Exception that activated this handler
    signalWorkQueueDepth*: int     # WQ depth at signal point
    signalEvalStackDepth*: int     # ES depth at signal point
    signalActivationDepth*: int    # AS depth at signal point
    exceptionContext*: ExceptionContext  # Full context for debugging

  # Exception thrown when Processor yield is called for immediate context switch
  YieldException* = object of CatchableError

  # Loop states for while loop work frames
  LoopState* = enum
    lsEvaluateCondition  # Evaluate the condition block
    lsCheckCondition      # Check the condition result
    lsExecuteBody         # Execute the loop body
    lsLoopBody            # After body, loop back to condition
    lsDone                # Loop completed

  # Work frame kinds for the explicit stack VM
  WorkFrameKind* = enum
    wfEvalNode        # Evaluate AST node, push result to evalStack
    wfSendMessage     # Send message (receiver and args on evalStack)
    wfApplyBlock      # Apply block with args from evalStack
    wfReturnValue     # Return value from current activation
    wfAfterReceiver   # After receiver eval, evaluate args
    wfAfterArg        # After arg N eval, evaluate arg N+1 or send
    wfCascade         # Cascade messages to same receiver
    wfPopActivation   # Pop activation after method/block body completes
    wfBuildArray      # Build array from N values on stack
    wfBuildTable      # Build table from N key-value pairs on stack
    wfCascadeMessage       # Send message in cascade (keeps receiver for next)
    wfCascadeMessageDiscard # Send message in cascade (discards result)
    wfRestoreReceiver      # Restore original receiver after cascade
    wfIfBranch            # Conditional branch (ifTrue:, ifFalse:)
    wfWhileLoop           # While loop (whileTrue:, whileFalse:)
    wfIfNodeContinuation  # IfNode specialization continuation (gets condition from stack)
    wfPushHandler         # Push exception handler onto handler stack
    wfPopHandler          # Pop exception handler from handler stack
    wfSignalException     # Signal exception and search for handler
    wfExceptionReturn     # Barrier: when handler completes, unwind to on:do: point

  # Work frame for explicit stack VM execution
  WorkFrame* = ref object
    kind*: WorkFrameKind
    skipRelease*: bool  # If true, frame was re-pushed onto queue and should not be released
    # For wfEvalNode
    node*: Node
    # For wfSendMessage
    selector*: string
    argCount*: int
    msgNode*: MessageNode  # Reference to AST node for inline cache
    isClassMethod*: bool   # For wfSendMessage/wfAfterReceiver: look in class methods
    # For wfApplyBlock
    blockVal*: BlockNode
    blockArgs*: seq[NodeValue]   # Pre-bound arguments for the block (used by exception handlers)
    # For wfAfterReceiver/wfAfterArg - what message to send
    pendingSelector*: string
    pendingArgs*: seq[Node]
    currentArgIndex*: int
    # For wfReturnValue
    returnValue*: NodeValue
    # For wfCascade
    cascadeMessages*: seq[Node]
    cascadeReceiver*: NodeValue
    # For wfPopActivation
    savedReceiver*: Instance
    isBlockActivation*: bool  # true for block, false for method
    savedEvalStackDepth*: int # eval stack depth before activation was pushed
    # For wfIfBranch
    conditionResult*: bool
    thenBlock*: BlockNode
    elseBlock*: BlockNode
    # For wfWhileLoop
    loopKind*: bool            # true = whileTrue, false = whileFalse
    conditionBlock*: BlockNode
    bodyBlock*: BlockNode
    loopState*: LoopState
    # For wfPushHandler/wfPopHandler
    exceptionClass*: Class     # The exception class to catch
    handlerBlock*: BlockNode   # Block to execute when exception is caught
    savedWorkQueueDepth*: int  # Work queue depth at handler installation point
    # For wfSignalException
    exceptionInstance*: Instance  # The exception instance being signaled
    # For wfExceptionReturn
    handlerIndex*: int               # Index into exceptionHandlers
    # For wfPushHandler (carry protected block for retry)
    protectedBlockForHandler*: BlockNode

  SourceEntry* = object
    found*: bool
    filePath*: string
    ownerClass*: string
    header*: string
    source*: string
    suffix*: string
    startLine*: int
    endLine*: int
    hasBlock*: bool
    selector*: string
    side*: string

  # Interpreter type defined here to avoid circular dependency between scheduler and evaluator
  Interpreter* = ref object
    globals*: ref Table[string, NodeValue]
    activationStack*: seq[Activation]
    currentActivation*: Activation
    currentReceiver*: Instance
    rootClass*: Class  # The root class for exception handling
    rootObject*: Instance  # The root object instance
    maxStackDepth*: int
    traceExecution*: bool
    lastResult*: NodeValue
    exceptionHandlers*: seq[ExceptionHandler]  # Stack of active exception handlers
    schedulerContextPtr*: pointer  # Scheduler context (cast to SchedulerContext when needed)
    hardingHome*: string  # Home directory for loading libraries
    shouldYield*: bool  # Set to true when Processor yield is called for immediate context switch
    nimChannelResult*: Option[NodeValue]  # Result delivered by scheduler polling a NimChannel
    methodTableDeferRebuild*: bool  # Defers method table rebuilds during batch loading
    implicitMethodDefinitionClassSide*: bool  # Treat `>>` definitions inside helper blocks as class-side methods
    # VM work queue and value stack
    workQueue*: seq[WorkFrame]  # Work queue for AST interpreter
    evalStack*: seq[NodeValue]  # Value stack for expression results
    # Library support
    importedLibraries*: seq[Instance]  # Stack of imported Library instances for namespace search
    commandLineArgs*: seq[string]  # Command-line arguments available to Harding code
    packageSources*: ref Table[string, string]  # Embedded source files keyed by virtual path
    sourceIndex*: ref Table[string, SourceEntry]  # Source entries keyed by class/side/selector
    sourceFileKeys*: ref Table[string, seq[string]]  # Reverse index for file invalidation
    # Debugger support
    when defined(debugger):
      debugMode*: bool              # Whether debugger is attached
      debuggerPaused*: bool         # Whether execution is paused
      debuggerStepMode*: int        # 0=none, 1=stepOver, 2=stepInto, 3=stepOut
      debuggerStepTarget*: int       # Target frame depth for step-out
    # Uncaught exception info (for debugger)
    uncaughtException*: Instance     # The uncaught exception instance
    uncaughtExceptionMessage*: string  # The exception message
    suppressUncaughtExit*: bool  # When true, uncaught exceptions raise EvalError instead of quitting

  BlockNode* = ref object of Node
    parameters*: seq[string]              # method parameters
    temporaries*: seq[string]             # local variables
    body*: seq[Node]                      # AST statements
    isMethod*: bool                       # true if method definition
    selector*: string                     # method selector (name) - set when method is registered
    primitiveSelector*: string            # for declarative primitives: selector of underlying primitive
    localCount*: int                      # total indexed locals: 1(self) + params.len + temps.len
    nativeImpl*: pointer                  # compiled implementation
    nativeValueImpl*: pointer             # NodeValue-oriented native implementation
    hasInterpreterParam*: bool            # true if native method needs interpreter parameter
    containsNestedBlocks*: bool           # true if body contains nkBlock nodes (needs closure capture)
    capturedEnv*: Table[string, MutableCell]  # captured variables from outer scope
    capturedEnvInitialized*: bool         # flag to track if capturedEnv has been initialized
    homeActivation*: Activation           # for non-local returns: method that created this block

  # Activation records for method execution (defined after BlockNode)
  ActivationObj* = object of RootObj
    sender*: Activation               # calling context
    receiver*: Instance               # 'self' (Instance type)
    currentMethod*: BlockNode         # current method
    definingObject*: Class            # class where method was found (for super)
    pc*: int                          # program counter
    locals*: Table[string, NodeValue] # local variables (fallback for non-indexed lookups)
    indexedLocals*: seq[NodeValue]    # fast indexed locals: [self, param0, param1, ..., temp0, temp1, ...]
    capturedVars*: Table[string, MutableCell]  # shared captured vars for sibling blocks
    returnValue*: NodeValue           # return value
    hasReturned*: bool                # non-local return flag
    nonLocalReturnTarget*: Activation # if set, return is non-local to this activation
    isClassMethod*: bool              # true if this is a class method activation
    wasCaptured*: bool                # true if stored as homeActivation or in ExceptionContext

  # Value types for AST nodes and runtime values
  ValueKind* = enum
    vkInt, vkFloat, vkString, vkSymbol, vkBool, vkNil, vkBlock,
    vkArray, vkTable, vkClass, vkInstance

  NodeValue* = object
    case kind*: ValueKind
    of vkInt: intVal*: int
    of vkFloat: floatVal*: float
    of vkString: strVal*: string
    of vkSymbol: symVal*: string
    of vkBool: boolVal*: bool
    of vkNil: discard
    of vkBlock: blockVal*: BlockNode
    of vkArray: arrayVal*: seq[NodeValue]
    of vkTable: tableVal*: Table[NodeValue, NodeValue]
    of vkClass: classVal*: Class
    of vkInstance: instVal*: Instance

  # AST Node specific types
  LiteralNode* = ref object of Node
    value*: NodeValue

  PICEntry* = tuple[cls: Class, meth: BlockNode, version: int]

  MessageNode* = ref object of Node
    receiver*: Node          # nil for implicit self
    selector*: string
    arguments*: seq[Node]
    isCascade*: bool
    # Monomorphic Inline Cache (MIC) fields
    cachedClass*: Class      # Last receiver class seen at this call site
    cachedMethod*: BlockNode # Cached method for cachedClass
    cachedVersion*: int      # Class version when MIC was populated
    # Polymorphic Inline Cache (PIC) fields
    picEntries*: array[3, PICEntry]  # Additional cache entries (total 4 with MIC)
    picCount*: int                   # Number of valid PIC entries (0-3)
    megamorphic*: bool               # True when PIC overflows; skip caching

  CascadeNode* = ref object of Node
    receiver*: Node
    messages*: seq[Node]

  AssignNode* = ref object of Node
    variable*: string
    expression*: Node
    localIndex*: int  # Index into activation.indexedLocals (-1 = not a local)

  ReturnNode* = ref object of Node
    expression*: Node        # nil for self-return

  ArrayNode* = ref object of Node
    elements*: seq[Node]

  TableNode* = ref object of Node
    entries*: seq[tuple[key: Node, value: Node]]

  ObjectLiteralNode* = ref object of Node
    properties*: seq[tuple[name: string, value: Node]]

  PrimitiveNode* = ref object of Node
    tag*: string                    # Raw tag content like "primitive" or "primitive name=\"clone\""
    nimCode*: string               # Raw Nim code between tags
    fallback*: seq[Node]           # Smalltalk AST after closing tag

  PrimitiveCallNode* = ref object of Node
    selector*: string          # The primitive selector (e.g., "primitiveClone", "primitiveAt:")
    arguments*: seq[Node]      # Arguments to the primitive
    isClassMethod*: bool       # True if this primitive should be looked up in class methods

  # Identifier node for variable lookup
  IdentNode* = ref object of Node
    name*: string
    localIndex*: int  # Index into activation.indexedLocals (-1 = not a local, use name-based fallback)

  # Slot access node for efficient slot access
  SlotAccessNode* = ref object of Node
    slotName*: string      # Name for debugging
    slotIndex*: int        # Index in allSlotNames (updated on layout change)
    isAssignment*: bool    # true for slot := value, false for slot read
    valueExpr*: Node       # Expression to evaluate for assignment (nil for reads)

  NamedAccessNode* = ref object of Node
    receiver*: Node
    memberName*: string
    isAssignment*: bool
    valueExpr*: Node

  # Super send node for calling parent class methods
  SuperSendNode* = ref object of Node
    selector*: string      # Method selector to lookup
    arguments*: seq[Node]  # Arguments to pass
    explicitParent*: string  # nil for unqualified super (first parent), else parent class name

  # Pseudo-variable node for self, nil, true, false
  PseudoVarNode* = ref object of Node
    name*: string          # "self", "nil", "true", "false"

  # Control flow specialization nodes
  IfNode* = ref object of Node
    condition*: Node        # Condition expression
    thenBranch*: Node       # True branch (BlockNode or statement)
    elseBranch*: Node       # Optional false branch (nil if no else)

  WhileNode* = ref object of Node
    condition*: Node        # Condition block or expression
    body*: Node             # Loop body (BlockNode)
    isWhileTrue*: bool      # true = whileTrue, false = whileFalse

  # Compiled method representation
  CompiledMethod* = ref object of RootObj
    selector*: string
    arity*: int
    nativeAddr*: pointer      # compiled function pointer
    symbolName*: string       # .so symbol name

  # Method entries (can be interpreted or compiled)
  MethodEntry* = object
    case isCompiled*: bool
    of false:
      interpreted*: BlockNode
    of true:
      compiled*: CompiledMethod

# ============================================================================
# Global Class Variables (declared early for use in helper procs)
# ============================================================================

var
  rootClass*: Class = nil                      # Root class (zero methods)
  objectClass*: Class = nil                     # Object class, derives from Root
  mixinClass*: Class = nil                      # Mixin class, sibling to Object (slotless, can mix with any type)
  undefinedObjectClass*: Class = nil            # UndefinedObject class, inherits from Object (for nil)
  booleanClass*: Class = nil
  integerClass*: Class = nil
  floatClass*: Class = nil
  stringClass*: Class = nil
  bufferClass*: Class = nil
  arrayClass*: Class = nil
  tableClass*: Class = nil
  blockClass*: Class = nil
  libraryClass*: Class = nil                    # Library class for namespace management
  setClass*: Class = nil                        # Set class for hash set operations
  randomClass*: Class = nil                     # Random class for random number generation
  classClass*: Class = nil                      # Class class (metaclass)

# nil instance - singleton instance of UndefinedObject
# Initialized during initCoreClasses, used by nilValue()
var nilInstance*: Instance = nil

# ============================================================================
# Truthiness check for NodeValue
# ============================================================================
proc isTruthy*(val: NodeValue): bool =
  ## Smalltalk boolean semantics: only true/false are valid condition values.
  ## Any non-boolean in a conditional is a runtime error.
  case val.kind
  of vkBool: return val.boolVal
  else:
    raise newException(ValueError,
      "Conditional requires Boolean (true/false), got " & $val.kind)

# ============================================================================
# Node kind helper
# ============================================================================
proc kind*(node: Node): NodeKind {.inline.} =
  ## Get the node kind for pattern matching (ordered by frequency in hot loops)
  if node of IdentNode: nkIdent
  elif node of MessageNode: nkMessage
  elif node of LiteralNode: nkLiteral
  elif node of BlockNode: nkBlock
  elif node of AssignNode: nkAssign
  elif node of ReturnNode: nkReturn
  elif node of WhileNode: nkWhile
  elif node of IfNode: nkIf
  elif node of PseudoVarNode: nkPseudoVar
  elif node of SlotAccessNode: nkSlotAccess
  elif node of NamedAccessNode: nkNamedAccess
  elif node of PrimitiveCallNode: nkPrimitiveCall
  elif node of SuperSendNode: nkSuperSend
  elif node of CascadeNode: nkCascade
  elif node of ArrayNode: nkArray
  elif node of TableNode: nkTable
  elif node of ObjectLiteralNode: nkObjectLiteral
  elif node of PrimitiveNode: nkPrimitive
  else: raise newException(ValueError, "Unknown node type")

# ============================================================================
# Local Index Resolution
# Resolves IdentNode.localIndex for indexed locals fast path
# ============================================================================

proc resolveLocalIndices*(blk: BlockNode) =
  ## Walk a BlockNode's body and set localIndex on IdentNodes that
  ## reference parameters or temporaries. Layout:
  ##   0: self
  ##   1..N: parameters
  ##   N+1..M: temporaries
  ## Also sets blk.localCount.
  if blk == nil:
    return

  # Build name -> index mapping
  var nameToIndex: Table[string, int]
  nameToIndex["self"] = 0
  for i, p in blk.parameters:
    nameToIndex[p] = i + 1
  for i, t in blk.temporaries:
    nameToIndex[t] = blk.parameters.len + 1 + i
  blk.localCount = 1 + blk.parameters.len + blk.temporaries.len

  var foundNestedBlock = false

  proc resolveBranch(branch: Node) =
    ## Resolve an IfNode/WhileNode branch block without counting it as a
    ## standalone nested block. Propagate its containsNestedBlocks flag up.
    if branch == nil:
      return
    if branch of BlockNode:
      let branchBlk = cast[BlockNode](branch)
      resolveLocalIndices(branchBlk)
      if branchBlk.containsNestedBlocks:
        foundNestedBlock = true
    # Non-BlockNode branches are handled by the caller via resolveNode

  proc resolveNode(node: Node) =
    if node == nil:
      return
    if node of IdentNode:
      let ident = cast[IdentNode](node)
      if ident.name in nameToIndex:
        ident.localIndex = nameToIndex[ident.name]
      else:
        ident.localIndex = -1  # Not a local; use name-based fallback
    elif node of MessageNode:
      let msg = cast[MessageNode](node)
      resolveNode(msg.receiver)
      for arg in msg.arguments:
        resolveNode(arg)
    elif node of AssignNode:
      let assign = cast[AssignNode](node)
      if assign.variable in nameToIndex:
        assign.localIndex = nameToIndex[assign.variable]
      else:
        assign.localIndex = -1
      resolveNode(assign.expression)
    elif node of ReturnNode:
      let ret = cast[ReturnNode](node)
      resolveNode(ret.expression)
    elif node of BlockNode:
      # Standalone block in body - will create a closure at runtime
      foundNestedBlock = true
      resolveLocalIndices(cast[BlockNode](node))
    elif node of CascadeNode:
      let cascade = cast[CascadeNode](node)
      resolveNode(cascade.receiver)
      for msg in cascade.messages:
        resolveNode(msg)
    elif node of IfNode:
      let ifN = cast[IfNode](node)
      resolveNode(ifN.condition)
      # IfNode branches are not standalone blocks; resolve separately
      # and propagate containsNestedBlocks flag up
      if ifN.thenBranch of BlockNode:
        resolveBranch(ifN.thenBranch)
      else:
        resolveNode(ifN.thenBranch)
      if ifN.elseBranch of BlockNode:
        resolveBranch(ifN.elseBranch)
      else:
        resolveNode(ifN.elseBranch)
    elif node of WhileNode:
      let whileN = cast[WhileNode](node)
      # WhileNode condition/body are not standalone blocks
      if whileN.condition of BlockNode:
        resolveBranch(whileN.condition)
      else:
        resolveNode(whileN.condition)
      if whileN.body of BlockNode:
        resolveBranch(whileN.body)
      else:
        resolveNode(whileN.body)
    elif node of ArrayNode:
      let arr = cast[ArrayNode](node)
      for elem in arr.elements:
        resolveNode(elem)
    elif node of TableNode:
      let tbl = cast[TableNode](node)
      for entry in tbl.entries:
        resolveNode(entry.key)
        resolveNode(entry.value)
    elif node of SuperSendNode:
      let ss = cast[SuperSendNode](node)
      for arg in ss.arguments:
        resolveNode(arg)
    elif node of PrimitiveCallNode:
      let pc = cast[PrimitiveCallNode](node)
      for arg in pc.arguments:
        resolveNode(arg)
    elif node of SlotAccessNode:
      let sa = cast[SlotAccessNode](node)
      resolveNode(sa.valueExpr)
    elif node of NamedAccessNode:
      let na = cast[NamedAccessNode](node)
      resolveNode(na.receiver)
      resolveNode(na.valueExpr)
    # LiteralNode, PseudoVarNode, PrimitiveNode: no children to resolve

  for stmt in blk.body:
    resolveNode(stmt)
  blk.containsNestedBlocks = foundNestedBlock

# Value conversion utilities
proc formatValue(val: NodeValue, quoteStrings: bool): string =
  ## Shared formatting logic for toString and formatLiteral.
  ## When quoteStrings is true, strings are quoted and arrays recurse with quoting.
  proc formatStr(s: string): string =
    if quoteStrings: '"' & s & '"' else: s

  proc formatSeq(elements: seq[NodeValue]): string =
    var parts: seq[string] = @[]
    for v in elements:
      parts.add(formatValue(v, quoteStrings))
    "#(" & parts.join(" ") & ")"

  proc formatTable(entries: Table[NodeValue, NodeValue]): string =
    var parts: seq[string] = @[]
    for k, v in entries:
      parts.add(formatValue(k, true) & " -> " & formatValue(v, true))
    "#{" & parts.join(" . ") & "}"

  case val.kind
  of vkInt: $val.intVal
  of vkFloat: $val.floatVal
  of vkString: formatStr(val.strVal)
  of vkSymbol: val.symVal
  of vkBool: $val.boolVal
  of vkNil: "nil"
  of vkClass: "<class " & val.classVal.name & ">"
  of vkInstance:
    if val.instVal == nil or val.instVal.class == nil:
      "<instance nil>"
    elif val.instVal == nilInstance or val.instVal.class == undefinedObjectClass:
      "nil"
    else:
      case val.instVal.kind
      of ikInt: $(val.instVal.intVal)
      of ikFloat: $(val.instVal.floatVal)
      of ikString: formatStr(val.instVal.strVal)
      of ikArray: formatSeq(val.instVal.elements)
      of ikTable: formatTable(val.instVal.entries)
      of ikObject: "<instance of " & val.instVal.class.name & ">"
  of vkBlock: "<block>"
  of vkArray: formatSeq(val.arrayVal)
  of vkTable: formatTable(val.tableVal)

proc toString*(val: NodeValue): string =
  ## Convert NodeValue to string for display
  formatValue(val, quoteStrings = false)

proc formatLiteral*(val: NodeValue): string =
  ## Format a literal value for display (quoted strings, bare numbers/symbols/booleans)
  formatValue(val, quoteStrings = true)

# Equality operator for NodeValue
proc `==`*(a, b: NodeValue): bool =
  ## Compare two NodeValues for equality
  if a.kind != b.kind:
    return false
  case a.kind
  of vkInt: a.intVal == b.intVal
  of vkFloat: a.floatVal == b.floatVal
  of vkString: a.strVal == b.strVal
  of vkSymbol: a.symVal == b.symVal
  of vkBool: a.boolVal == b.boolVal
  of vkNil: true
  of vkBlock: unsafeAddr(a.blockVal) == unsafeAddr(b.blockVal)
  of vkInstance: a.instVal == b.instVal
  of vkArray:
    if a.arrayVal.len != b.arrayVal.len: return false
    for i in 0..<a.arrayVal.len:
      if a.arrayVal[i] != b.arrayVal[i]: return false
    return true
  of vkTable:
    if a.tableVal.len != b.tableVal.len: return false
    for k, v in a.tableVal:
      var found = false
      for k2, v2 in b.tableVal:
        if k == k2:
          if v != v2: return false
          found = true
          break
      if not found: return false
    return true
  of vkClass: a.classVal == b.classVal

# Hash functions for ref types (needed for table hashing)
proc hash*(val: BlockNode): Hash = cast[int](val)
proc hash*(val: Instance): Hash = cast[int](val)
proc hash*(val: Class): Hash = cast[int](val)

# Hash function for NodeValue (enables use as Table keys)
proc hash*(val: NodeValue): Hash =
  ## Hash a NodeValue for use as a hash table key
  case val.kind
  of vkInt:
    result = hash(val.intVal)
  of vkFloat:
    result = hash(val.floatVal.uint64)
  of vkString:
    result = hash(val.strVal)
  of vkSymbol:
    result = hash(val.symVal)
  of vkBool:
    result = hash(val.boolVal.uint8)
  of vkNil:
    result = 0
  of vkBlock:
    result = cast[int](val.blockVal)
  of vkInstance:
    result = cast[int](val.instVal)
  of vkArray:
    result = val.arrayVal.len
    for item in val.arrayVal:
      result = result xor hash(item)
  of vkTable:
    result = val.tableVal.len
    for k, v in val.tableVal:
      result = result xor hash(k)
      result = result xor hash(v)
  of vkClass:
    result = cast[int](val.classVal)

proc toValue*(i: int): NodeValue =
  NodeValue(kind: vkInt, intVal: i)

proc toValue*(f: float): NodeValue =
  NodeValue(kind: vkFloat, floatVal: f)

proc toValue*(s: string): NodeValue =
  NodeValue(kind: vkString, strVal: s)

proc toSymbol*(s: string): NodeValue =
  NodeValue(kind: vkSymbol, symVal: s)

proc toValue*(b: bool): NodeValue =
  NodeValue(kind: vkBool, boolVal: b)

proc nilValue*(): NodeValue =
  ## Return the nil value (singleton instance of UndefinedObject)
  ## During early bootstrap, nilInstance may not be set yet,
  ## so we fall back to vkNil temporarily
  if nilInstance != nil:
    return NodeValue(kind: vkInstance, instVal: nilInstance)
  else:
    # Fallback during early bootstrap before UndefinedObject is created
    return NodeValue(kind: vkNil)

proc isNilValue*(val: NodeValue): bool =
  ## Check if a value is nil (either vkNil or the nil instance)
  if val.kind == vkNil:
    return true
  if val.kind == vkInstance and val.instVal != nil:
    # Check if this is the singleton nil instance
    if val.instVal == nilInstance:
      return true
    # Also check by class - if it's an instance of UndefinedObject, it's nil
    if val.instVal.class != nil and val.instVal.class == undefinedObjectClass:
      return true
  return false

proc classOfValue*(val: NodeValue): Class =
  ## Resolve the runtime class for a NodeValue without materializing wrappers.
  case val.kind
  of vkInstance:
    if val.instVal != nil:
      return val.instVal.class
    return nil
  of vkInt:
    return integerClass
  of vkFloat:
    return floatClass
  of vkString:
    return stringClass
  of vkBool:
    return booleanClass
  of vkNil:
    return undefinedObjectClass
  of vkArray:
    return arrayClass
  of vkTable:
    return tableClass
  of vkBlock:
    return blockClass
  of vkClass:
    return val.classVal
  of vkSymbol:
    return nil

proc toValue*(arr: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkArray, arrayVal: arr)

proc toValue*(tab: Table[NodeValue, NodeValue]): NodeValue =
  NodeValue(kind: vkTable, tableVal: tab)

proc toValue*(blk: BlockNode): NodeValue =
  NodeValue(kind: vkBlock, blockVal: blk)

proc toValue*(cls: Class): NodeValue =
  NodeValue(kind: vkClass, classVal: cls)

proc toValue*(inst: Instance): NodeValue =
  NodeValue(kind: vkInstance, instVal: inst)

proc unwrap*(val: NodeValue): NodeValue =
  ## Unwrap primitive values from Instance wrappers
  # If the value is vkInstance with kind ikInt, ikFloat, or ikString,
  # convert it to the corresponding primitive NodeValue.
  # For ikString, check if it's a Symbol (class = symbolClassCache) or String.
  if val.kind == vkInstance and val.instVal != nil:
    case val.instVal.kind
    of ikInt:
      return NodeValue(kind: vkInt, intVal: val.instVal.intVal)
    of ikFloat:
      return NodeValue(kind: vkFloat, floatVal: val.instVal.floatVal)
    of ikString:
      # Check if this is a Symbol instance by checking class name
      # Symbol instances have class.name == "Symbol"
      if val.instVal.class != nil and val.instVal.class.name == "Symbol":
        return NodeValue(kind: vkSymbol, symVal: val.instVal.strVal)
      return NodeValue(kind: vkString, strVal: val.instVal.strVal)
    of ikArray, ikTable, ikObject:
      # These stay wrapped as vkInstance
      return val
  return val

# ============================================================================
# Symbol Table for Canonicalization
# ============================================================================

var symbolTable*: Table[string, NodeValue]

proc initSymbolTable*() =
  ## Initialize symbol table if not already
  if symbolTable.len == 0:
    symbolTable = initTable[string, NodeValue]()

proc getSymbol*(name: string): NodeValue =
  ## Get or create a canonical symbol
  if symbolTable.hasKey(name):
    return symbolTable[name]
  else:
    let sym = NodeValue(kind: vkSymbol, symVal: name)
    symbolTable[name] = sym
    return sym

proc symbolEquals*(a, b: NodeValue): bool =
  ## Check if two symbols are identical (object identity for canonical symbols)
  if a.kind != vkSymbol or b.kind != vkSymbol:
    return false
  return a.symVal == b.symVal

proc clearSymbolTable*() =
  ## Clear all symbols (useful for testing)
  symbolTable.clear()

# ============================================================================
# Global Logging Configuration
# ============================================================================

var globalLogLevel* = lvlError  ## Default log level for the application

proc setLogLevel*(level: Level) =
  ## Set the global log level programmatically (e.g., in tests)
  globalLogLevel = level
  # Update all existing handlers
  for handler in getHandlers():
    handler.levelThreshold = level

proc configureLogging*(level: Level = lvlError) =
  ## Configure logging with the specified level
  globalLogLevel = level
  if getHandlers().len == 0:
    # No logger configured yet, add console logger
    addHandler(logging.newConsoleLogger(levelThreshold = level, useStderr = true))
  else:
    # Update existing handlers
    for handler in getHandlers():
      handler.levelThreshold = level

# ============================================================================
# Root Class
# ============================================================================
# SchedulerContext type definition
# Defined in types.nim to avoid circular import between types.nim and scheduler.nim
import ./process

type
  SchedulerContext* = ref object
    ## Full scheduler context with interpreter integration
    theScheduler*: Scheduler  ## 'theScheduler' to avoid naming conflict with scheduler module
    mainProcess*: Process  ## The initial/main process

# Forward declarations
proc newClass*(superclasses: seq[Class] = @[], slotNames: seq[string] = @[], name: string = "",
               readableSlotNames: seq[string] = @[], writableSlotNames: seq[string] = @[]): Class

proc initRootClass*(): Class =
  ## Initialize the global root class
  ## Root has zero methods - used as base for DNU wrappers/proxies
  if rootClass == nil:
    rootClass = newClass(name = "Root")
    rootClass.tags = @["Root"]
  return rootClass

proc initObjectClass*(): Class =
  ## Initialize the global Object class (inherits from Root)
  ## Object is the normal Smalltalk base class with all core methods
  if objectClass == nil:
    # Ensure Root exists first
    discard initRootClass()
    objectClass = newClass(superclasses = @[rootClass], name = "Object")
    objectClass.tags = @["Object"]
  return objectClass

proc initMixinClass*(): Class =
  ## Initialize the global Mixin class (inherits from Object)
  ## Mixin is a slotless class that can be mixed into any other class type
  ## Use Mixin derive: methods: [...] to create reusable trait/mixin classes
  if mixinClass == nil:
    mixinClass = newClass(superclasses = @[objectClass], name = "Mixin")
    mixinClass.tags = @["Mixin", "Object"]
  return mixinClass

# ============================================================================
# Class and Instance Helpers
# ============================================================================

proc isMixin*(cls: Class): bool =
  ## Check if a class is a mixin class.
  ## A class is considered a mixin when it is tagged as Mixin or when its
  ## primary superclass chain reaches Mixin (e.g., Comparable := Mixin derive).
  ## This excludes regular classes that only include mixins as additional parents.
  if cls == nil:
    return false
  if "Mixin" in cls.tags:
    return true

  var current = cls
  while current != nil:
    if current.name == "Mixin":
      return true
    if current.superclasses.len > 0:
      current = current.superclasses[0]
    else:
      break
  return false

proc newClass*(superclasses: seq[Class] = @[], slotNames: seq[string] = @[], name: string = "",
               readableSlotNames: seq[string] = @[], writableSlotNames: seq[string] = @[]): Class =
  ## Create a new Class with given superclasses and slot names
  ## Pre-size method tables to avoid enlargement overhead
  let expectedMethods = max(superclasses.len * 4, 8)  # Expect at least 8 methods for typical classes
  result = Class()
  result.methods = initTable[string, BlockNode](expectedMethods)
  result.allMethods = initTable[string, BlockNode](expectedMethods)
  result.classMethods = initTable[string, BlockNode](expectedMethods)
  result.allClassMethods = initTable[string, BlockNode](expectedMethods)
  result.slotNames = slotNames
  result.allSlotNames = @[]
  result.readableSlotNames = readableSlotNames
  result.writableSlotNames = writableSlotNames
  result.superclasses = superclasses
  result.subclasses = @[]
  result.name = name
  result.tags = @["Class"]
  result.isNimProxy = false
  result.hardingType = ""
  result.hasSlots = slotNames.len > 0
  result.conflictSelectors = @[]
  result.classConflictSelectors = @[]

  # Check for slot name conflicts from superclasses
  var seenSlotNames: seq[string] = @[]
  for parent in superclasses:
    for slotName in parent.allSlotNames:
      if slotName in seenSlotNames:
        raise newException(ValueError, "Slot name conflict: '" & slotName & "' exists in multiple superclasses")
      seenSlotNames.add(slotName)

  # Check for slot name conflicts between new slots and parent slots
  for slotName in slotNames:
    if slotName in seenSlotNames:
      raise newException(ValueError, "Slot name conflict: '" & slotName & "' already exists in parent class")

  # Add new slot names to seen list for checking among new slots
  for slotName in slotNames:
    if slotName in seenSlotNames:
      raise newException(ValueError, "Slot name conflict: '" & slotName & "' declared multiple times")
    seenSlotNames.add(slotName)

  # Add to superclasses' subclasses lists and inherit methods
  for parent in superclasses:
    parent.subclasses.add(result)
    # If parent is dirty, trigger rebuild to get latest methods before inheriting
    # This ensures new subclasses pick up methods added after parent was marked dirty
    if parent.methodsDirty:
      # Rebuild parent's method tables by re-inheriting from its parents
      # Use a simple approach: copy parent's allMethods to ensure we have latest
      var updatedMethods = parent.methods
      for superParent in parent.superclasses:
        for sel, meth in superParent.allMethods:
          if sel notin updatedMethods:
            updatedMethods[sel] = meth
      parent.allMethods = updatedMethods
      parent.methodsDirty = false
    # Inherit instance methods (unless child overrides)
    for selector, methodBlock in parent.allMethods:
      if selector in result.allMethods and selector notin result.methods:
        if selector in parent.methods and selector notin result.conflictSelectors:
          result.conflictSelectors.add(selector)
      elif selector notin result.methods:  # Only inherit if not overridden
        result.allMethods[selector] = methodBlock
    # Inherit class methods
    for selector, methodBlock in parent.allClassMethods:
      if selector in result.allClassMethods and selector notin result.classMethods:
        if selector in parent.classMethods and selector notin result.classConflictSelectors:
          result.classConflictSelectors.add(selector)
      elif selector notin result.classMethods:
        result.allClassMethods[selector] = methodBlock
    # Inherit slot names
    for slotName in parent.allSlotNames:
      if slotName notin result.allSlotNames:
        result.allSlotNames.add(slotName)
    # Inherit readable/writable slot permissions
    for slotName in parent.readableSlotNames:
      if slotName notin result.readableSlotNames:
        result.readableSlotNames.add(slotName)
    for slotName in parent.writableSlotNames:
      if slotName notin result.writableSlotNames:
        result.writableSlotNames.add(slotName)

  var allowMethodConflicts = true
  for parent in superclasses:
    if not parent.isMixin:
      allowMethodConflicts = false
      break
  if not allowMethodConflicts and result.conflictSelectors.len > 0:
    raise newException(ValueError,
      "Method conflict: '" & result.conflictSelectors[0] & "' exists in multiple superclasses")
  if not allowMethodConflicts and result.classConflictSelectors.len > 0:
    raise newException(ValueError,
      "Class method conflict: '" & result.classConflictSelectors[0] & "' exists in multiple superclasses")

  # Add own slot names
  for slotName in slotNames:
    if slotName notin result.allSlotNames:
      result.allSlotNames.add(slotName)

  for slotName in result.readableSlotNames:
    if slotName notin result.allSlotNames:
      raise newException(ValueError, "Readable slot '" & slotName & "' is not declared on class '" & name & "'")

  for slotName in result.writableSlotNames:
    if slotName notin result.allSlotNames:
      raise newException(ValueError, "Writable slot '" & slotName & "' is not declared on class '" & name & "'")

proc addSuperclass*(cls: Class, parent: Class) =
  ## Add a parent to an existing class
  ## Useful for resolving method conflicts by adding parent after overriding methods
  if parent in cls.superclasses:
    return  # Already has this parent

  # Check for slot name conflicts (only for directly-defined slots on this parent)
  for slotName in parent.slotNames:
    if slotName in cls.allSlotNames and slotName notin cls.slotNames:
      raise newException(ValueError, "Slot name conflict: '" & slotName & "' already exists in existing parent hierarchy")

  # Add parent
  cls.superclasses.add(parent)
  parent.subclasses.add(cls)

  # Inherit instance methods (unless child overrides)
  for selector, methodBlock in parent.allMethods:
    if selector in cls.allMethods and selector notin cls.methods:
      if selector in parent.methods and selector notin cls.conflictSelectors:
        cls.conflictSelectors.add(selector)
    elif selector notin cls.methods and selector notin cls.allMethods:
      cls.allMethods[selector] = methodBlock

  # Inherit class methods
  for selector, methodBlock in parent.allClassMethods:
    if selector in cls.allClassMethods and selector notin cls.classMethods:
      if selector in parent.classMethods and selector notin cls.classConflictSelectors:
        cls.classConflictSelectors.add(selector)
    elif selector notin cls.classMethods and selector notin cls.allClassMethods:
      cls.allClassMethods[selector] = methodBlock

  # Inherit slot names
  for slotName in parent.allSlotNames:
    if slotName notin cls.allSlotNames:
      cls.allSlotNames.add(slotName)
  # Inherit readable/writable slot permissions
  for slotName in parent.readableSlotNames:
    if slotName notin cls.readableSlotNames:
      cls.readableSlotNames.add(slotName)
  for slotName in parent.writableSlotNames:
    if slotName notin cls.writableSlotNames:
      cls.writableSlotNames.add(slotName)

  # Update hasSlots flag if needed
  if cls.allSlotNames.len > 0:
    cls.hasSlots = true

# Helper for nimValue initialization and comparison
const NimValueDefault* = nil
template nimValueIsSet*(nv: pointer): bool = nv != nil
template nimValueIsNil*(nv: pointer): bool = nv == nil

proc newInstance*(cls: Class): Instance =
  ## Create a new Instance of the given Class (ikObject variant)
  result = Instance(kind: ikObject, class: cls)
  result.slots = newSeq[NodeValue](cls.allSlotNames.len)
  # Initialize all slots to nil
  for i in 0..<result.slots.len:
    result.slots[i] = nilValue()
  result.isNimProxy = false
  result.nimValue = NimValueDefault

proc newIntInstance*(cls: Class, value: int): Instance =
  ## Create a new Integer instance with direct value storage
  Instance(kind: ikInt, class: cls, intVal: value, isNimProxy: false, nimValue: NimValueDefault)

proc newFloatInstance*(cls: Class, value: float): Instance =
  ## Create a new Float instance with direct value storage
  Instance(kind: ikFloat, class: cls, floatVal: value, isNimProxy: false, nimValue: NimValueDefault)

proc newStringInstance*(cls: Class, value: string): Instance =
  ## Create a new String instance with direct value storage
  Instance(kind: ikString, class: cls, strVal: value, isNimProxy: false, nimValue: NimValueDefault)

proc newArrayInstance*(cls: Class, elements: seq[NodeValue]): Instance =
  ## Create a new Array instance
  Instance(kind: ikArray, class: cls, elements: elements, isNimProxy: false, nimValue: NimValueDefault)

proc newTableInstance*(cls: Class, entries: Table[NodeValue, NodeValue]): Instance =
  ## Create a new Table instance
  Instance(kind: ikTable, class: cls, entries: entries, isNimProxy: false, nimValue: NimValueDefault)

proc getSlotIndex*(cls: Class, name: string): int =
  ## Get slot index by name, returns -1 if not found
  for i, slotName in cls.allSlotNames:
    if slotName == name:
      return i
  return -1


proc getSlot*(inst: Instance, index: int): NodeValue =
  ## Get slot value by index (only for ikObject instances)
  if inst.kind != ikObject:
    return nilValue()
  if index < 0 or index >= inst.slots.len:
    return nilValue()
  return inst.slots[index]

proc setSlot*(inst: Instance, index: int, value: NodeValue) =
  ## Set slot value by index (only for ikObject instances)
  if inst.kind != ikObject:
    return
  if index >= 0 and index < inst.slots.len:
    inst.slots[index] = value

# Helper procs for getting values from Instance variants
proc getIntValue*(inst: Instance): int =
  if inst.kind != ikInt:
    raise newException(ValueError, "Not an int instance")
  inst.intVal

proc getFloatValue*(inst: Instance): float =
  if inst.kind != ikFloat:
    raise newException(ValueError, "Not a float instance")
  inst.floatVal

proc getStringValue*(inst: Instance): string =
  if inst.kind != ikString:
    raise newException(ValueError, "Not a string instance")
  inst.strVal

proc getArrayElements*(inst: Instance): seq[NodeValue] =
  if inst.kind != ikArray:
    raise newException(ValueError, "Not an array instance")
  inst.elements

proc getTableEntries*(inst: Instance): Table[NodeValue, NodeValue] =
  if inst.kind != ikTable:
    raise newException(ValueError, "Not a table instance")
  inst.entries

proc getTableValue*(inst: Instance, key: NodeValue): NodeValue =
  ## Get a value from a table instance
  if inst.kind != ikTable:
    return nilValue()
  if key in inst.entries:
    return inst.entries[key]
  return nilValue()

proc setTableValue*(inst: Instance, key: NodeValue, value: NodeValue) =
  ## Set a value in a table instance
  if inst.kind == ikTable:
    inst.entries[key] = value

proc lookupInstanceMethod*(cls: Class, selector: string): BlockNode =
  ## Look up instance method in class (fast O(1) lookup)
  if selector in cls.allMethods:
    return cls.allMethods[selector]
  return nil

proc lookupClassMethod*(cls: Class, selector: string): BlockNode =
  ## Look up class method (fast O(1) lookup)
  if selector in cls.allClassMethods:
    return cls.allClassMethods[selector]
  return nil

# ============================================================================
# NodeValue to Instance conversion (for transition from legacy to new model)
# ============================================================================

proc valueToInstance*(val: NodeValue): Instance =
  ## Convert a NodeValue to an Instance variant
  ## Used during migration to handle both legacy and new values
  case val.kind
  of vkInstance:
    return val.instVal
  of vkInt:
    if integerClass != nil:
      return newIntInstance(integerClass, val.intVal)
    else:
      # Fallback during initialization
      return Instance(kind: ikInt, class: nil, intVal: val.intVal, isNimProxy: false, nimValue: NimValueDefault)
  of vkFloat:
    if floatClass != nil:
      return newFloatInstance(floatClass, val.floatVal)
    else:
      return Instance(kind: ikFloat, class: nil, floatVal: val.floatVal, isNimProxy: false, nimValue: NimValueDefault)
  of vkString:
    if stringClass != nil:
      return newStringInstance(stringClass, val.strVal)
    else:
      return Instance(kind: ikString, class: nil, strVal: val.strVal, isNimProxy: false, nimValue: NimValueDefault)
  of vkArray:
    if arrayClass != nil:
      return newArrayInstance(arrayClass, val.arrayVal)
    else:
      return Instance(kind: ikArray, class: nil, elements: val.arrayVal, isNimProxy: false, nimValue: NimValueDefault)
  of vkTable:
    if tableClass != nil:
      return newTableInstance(tableClass, val.tableVal)
    else:
      return Instance(kind: ikTable, class: nil, entries: val.tableVal, isNimProxy: false, nimValue: NimValueDefault)
  of vkBool:
    # Boolean values - allocate on GC heap for ARC compatibility
    let p = cast[pointer](new(bool))
    cast[ptr bool](p)[] = val.boolVal
    return Instance(kind: ikObject, class: booleanClass, slots: @[], isNimProxy: true, nimValue: p)
  of vkBlock:
    # Blocks are passed as-is, created as ikObject instances
    return Instance(kind: ikObject, class: blockClass, slots: @[], isNimProxy: false, nimValue: NimValueDefault)
  of vkClass, vkNil, vkSymbol:
    raise newException(ValueError, "Cannot convert " & $val.kind & " to Instance")

# ============================================================================
# Scheduler Context Type
# ============================================================================

# Note: SchedulerContext is defined earlier in this file (line ~382)
# to avoid circular dependencies between scheduler and evaluator

# ============================================================================
# Tagged Value Conversions (for VM performance)
# ============================================================================

proc toTagged*(val: NodeValue): tagged.Value =
  ## Convert NodeValue to tagged Value (fast path for primitives)
  case val.kind
  of vkInt:
    tagged.toValue(val.intVal)
  of vkBool:
    tagged.toValue(val.boolVal)
  of vkNil:
    tagged.nilValue()
  of vkInstance:
    # Convert Instance to HeapObject pointer
    tagged.toValue(cast[tagged.HeapObject](val.instVal))
  else:
    # Other types not yet supported for tagged values
    raise newException(ValueError, "Cannot convert " & $val.kind & " to tagged Value")

proc toNodeValue*(val: tagged.Value): NodeValue =
  ## Convert tagged Value to NodeValue
  if tagged.isInt(val):
    NodeValue(kind: vkInt, intVal: tagged.asInt(val))
  elif tagged.isBool(val):
    NodeValue(kind: vkBool, boolVal: tagged.asBool(val))
  elif tagged.isNil(val):
    nilValue()
  elif tagged.isHeapObject(val):
    let heapObj = tagged.asHeapObject(val)
    if heapObj == nil:
      nilValue()
    else:
      # Cast HeapObject back to Instance
      NodeValue(kind: vkInstance, instVal: cast[Instance](heapObj))
  else:
    raise newException(ValueError, "Unknown tagged value type")

# Re-export tagged Value type for convenience
type TaggedValue* = tagged.Value

# Wrapper procs for tagged value operations (avoiding ambiguity with stdlib)
proc add*(a, b: TaggedValue): TaggedValue {.inline.} = tagged.add(a, b)
proc sub*(a, b: TaggedValue): TaggedValue {.inline.} = tagged.sub(a, b)
proc mul*(a, b: TaggedValue): TaggedValue {.inline.} = tagged.mul(a, b)
proc divInt*(a, b: TaggedValue): TaggedValue {.inline.} = tagged.divInt(a, b)
proc modInt*(a, b: TaggedValue): TaggedValue {.inline.} = tagged.modInt(a, b)

# Wrapper procs for comparison operations
proc intEquals*(a, b: TaggedValue): bool {.inline.} = tagged.equals(a, b)
proc lessThan*(a, b: TaggedValue): bool {.inline.} = tagged.lessThan(a, b)
proc lessOrEqual*(a, b: TaggedValue): bool {.inline.} = tagged.lessOrEqual(a, b)
proc greaterThan*(a, b: TaggedValue): bool {.inline.} = tagged.greaterThan(a, b)
proc greaterOrEqual*(a, b: TaggedValue): bool {.inline.} = tagged.greaterOrEqual(a, b)

# ============================================================================
# BlockNode Registry for ARC Compatibility
# ============================================================================
# When storing BlockNodes in Instance.nimValue (as raw pointers), ARC doesn't
# know about these references and may collect the BlockNodes prematurely.
# This registry keeps BlockNodes alive by storing them in a global seq that
# ARC can track.

var blockNodeRegistry*: seq[BlockNode] = @[]
  ## Global registry of BlockNodes to prevent ARC from collecting them

proc registerBlockNode*(blk: BlockNode) =
  ## Register a BlockNode to keep it alive for ARC
  if blk != nil and blk notin blockNodeRegistry:
    blockNodeRegistry.add(blk)

proc unregisterBlockNode*(blk: BlockNode) =
  ## Unregister a BlockNode (if it was explicitly registered)
  for i in 0..<blockNodeRegistry.len:
    if blockNodeRegistry[i] == blk:
      blockNodeRegistry.delete(i)
      break

proc initBlockNodeRegistry*() =
  ## Initialize the BlockNode registry (called at startup)
  blockNodeRegistry = @[]

# ============================================================================
# ExceptionContext Registry for ARC Compatibility
# ============================================================================

var exceptionContextRegistry*: seq[ExceptionContext] = @[]
  ## Global registry of ExceptionContext to prevent ARC from collecting them

proc registerExceptionContext*(ctx: ExceptionContext) =
  ## Register an ExceptionContext to keep it alive for ARC
  if ctx != nil and ctx notin exceptionContextRegistry:
    exceptionContextRegistry.add(ctx)

proc unregisterExceptionContext*(ctx: ExceptionContext) =
  ## Unregister an ExceptionContext
  for i in 0..<exceptionContextRegistry.len:
    if exceptionContextRegistry[i] == ctx:
      exceptionContextRegistry.delete(i)
      break
