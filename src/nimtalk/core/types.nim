import std/[tables, algorithm, hashes, logging]

# ============================================================================
# Core Types for Nimtalk
# ============================================================================

# All type definitions in a single section to allow forward declarations
# Note: {.acyclic.} pragmas are used to prevent ORC cycle detection issues
# when objects form reference cycles (which is common in an interpreter).
# See CLAUDE.md for details on ORC issues.
type
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
    ikMixin        # Mixin instance - no slots, only shared methods (can mix with any type)

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

    # Inheritance
    parents*: seq[Class]                    # Direct parent classes
    subclasses*: seq[Class]                 # Direct children (for efficient invalidation)

    # Metadata
    name*: string                           # Class name for debugging/reflection
    tags*: seq[string]                      # Type tags
    isNimProxy*: bool                       # Class wraps Nim type
    nimtalkType*: string                    # Nim type name for FFI
    hasSlots*: bool                         # Has any instance variables

  Instance* {.acyclic.} = ref object of RootObj
    ## Instance object - pure data with reference to its class
    ## Using case object variant for memory efficiency - only allocate fields needed
    class*: Class                           # Reference to class
    case kind*: InstanceKind
    of ikObject, ikMixin:
      slots*: seq[NodeValue]                # Instance variables (always empty for ikMixin)
    of ikArray:
      elements*: seq[NodeValue]             # Array elements
    of ikTable:
      entries*: Table[string, NodeValue]    # Table entries
    of ikInt:
      intVal*: int                          # Direct storage (no boxing)
    of ikFloat:
      floatVal*: float                      # Direct storage
    of ikString:
      strVal*: string                       # Direct storage
    isNimProxy*: bool                       # Instance wraps Nim value
    nimValue*: pointer                      # Pointer to actual Nim value (for FFI)

  # Mutable cell for captured variables (shared between closures)
  MutableCell* {.acyclic.} = ref object
    value*: NodeValue          # the captured value

  # Forward declarations to break circular dependency
  Activation* = ref ActivationObj

  BlockNode* {.acyclic.} = ref object of Node
    parameters*: seq[string]              # method parameters
    temporaries*: seq[string]             # local variables
    body*: seq[Node]                      # AST statements
    isMethod*: bool                       # true if method definition
    nativeImpl*: pointer                  # compiled implementation
    hasInterpreterParam*: bool            # true if native method needs interpreter parameter
    capturedEnv*: Table[string, MutableCell]  # captured variables from outer scope
    homeActivation*: Activation           # for non-local returns: method that created this block

  # Activation records for method execution (defined after BlockNode)
  ActivationObj* {.acyclic.} = object of RootObj
    sender*: Activation               # calling context
    receiver*: Instance               # 'self' (Instance type)
    currentMethod*: BlockNode         # current method
    definingObject*: Class            # class where method was found (for super)
    pc*: int                          # program counter
    locals*: Table[string, NodeValue] # local variables
    capturedVars*: Table[string, MutableCell]  # shared captured vars for sibling blocks
    returnValue*: NodeValue           # return value
    hasReturned*: bool                # non-local return flag

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
    of vkTable: tableVal*: Table[string, NodeValue]
    of vkClass: classVal*: Class
    of vkInstance: instVal*: Instance

  # AST Node specific types
  LiteralNode* = ref object of Node
    value*: NodeValue

  MessageNode* = ref object of Node
    receiver*: Node          # nil for implicit self
    selector*: string
    arguments*: seq[Node]
    isCascade*: bool

  CascadeNode* = ref object of Node
    receiver*: Node
    messages*: seq[MessageNode]

  AssignNode* = ref object of Node
    variable*: string
    expression*: Node

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

  # Identifier node for variable lookup
  IdentNode* = ref object of Node
    name*: string

  # Slot access node for efficient instance variable access
  SlotAccessNode* = ref object of Node
    slotName*: string      # Name for debugging
    slotIndex*: int        # Index in allSlotNames (updated on layout change)
    isAssignment*: bool    # true for slot := value, false for slot read
    valueExpr*: Node       # Expression to evaluate for assignment (nil for reads)

  # Super send node for calling parent class methods
  SuperSendNode* = ref object of Node
    selector*: string      # Method selector to lookup
    arguments*: seq[Node]  # Arguments to pass
    explicitParent*: string  # nil for unqualified super (first parent), else parent class name

  # Pseudo-variable node for self, nil, true, false
  PseudoVarNode* = ref object of Node
    name*: string          # "self", "nil", "true", "false"

  # Node type enum for pattern matching
  NodeKind* = enum
    nkLiteral, nkIdent, nkMessage, nkBlock, nkAssign, nkReturn,
    nkArray, nkTable, nkObjectLiteral, nkPrimitive, nkPrimitiveCall, nkCascade,
    nkSlotAccess, nkSuperSend, nkPseudoVar

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
# Node kind helper
# ============================================================================
proc kind*(node: Node): NodeKind =
  ## Get the node kind for pattern matching
  if node of LiteralNode: nkLiteral
  elif node of IdentNode: nkIdent
  elif node of MessageNode: nkMessage
  elif node of BlockNode: nkBlock
  elif node of AssignNode: nkAssign
  elif node of ReturnNode: nkReturn
  elif node of ArrayNode: nkArray
  elif node of TableNode: nkTable
  elif node of ObjectLiteralNode: nkObjectLiteral
  elif node of PrimitiveNode: nkPrimitive
  elif node of PrimitiveCallNode: nkPrimitiveCall
  elif node of CascadeNode: nkCascade
  elif node of SlotAccessNode: nkSlotAccess
  elif node of SuperSendNode: nkSuperSend
  elif node of PseudoVarNode: nkPseudoVar
  else: raise newException(ValueError, "Unknown node type")

# Value conversion utilities
proc toString*(val: NodeValue): string =
  ## Convert NodeValue to string for display
  case val.kind
  of vkInt: $val.intVal
  of vkFloat: $val.floatVal
  of vkString: val.strVal
  of vkSymbol: val.symVal
  of vkBool: $val.boolVal
  of vkNil: "nil"
  of vkClass: "<class " & val.classVal.name & ">"
  of vkInstance:
    if val.instVal == nil or val.instVal.class == nil:
      "<instance nil>"
    else:
      case val.instVal.kind
      of ikInt: $(val.instVal.intVal)
      of ikFloat: $(val.instVal.floatVal)
      of ikString: val.instVal.strVal
      of ikArray: "#(" & $val.instVal.elements.len & ")"
      of ikTable: "#{" & $val.instVal.entries.len & "}"
      of ikObject: "<instance of " & val.instVal.class.name & ">"
      of ikMixin: "<mixin " & val.instVal.class.name & ">"
  of vkBlock: "<block>"
  of vkArray: "#(" & $val.arrayVal.len & ")"
  of vkTable: "#{" & $val.tableVal.len & "}"

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
  NodeValue(kind: vkNil)

proc toValue*(arr: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkArray, arrayVal: arr)

proc toValue*(tab: Table[string, NodeValue]): NodeValue =
  NodeValue(kind: vkTable, tableVal: tab)

proc toValue*(blk: BlockNode): NodeValue =
  NodeValue(kind: vkBlock, blockVal: blk)

proc toValue*(cls: Class): NodeValue =
  NodeValue(kind: vkClass, classVal: cls)

proc toValue*(inst: Instance): NodeValue =
  NodeValue(kind: vkInstance, instVal: inst)

proc toBlock*(val: NodeValue): BlockNode =
  if val.kind != vkBlock:
    raise newException(ValueError, "Not a block: " & val.toString)
  val.blockVal

proc toClass*(val: NodeValue): Class =
  if val.kind != vkClass:
    raise newException(ValueError, "Not a class: " & val.toString)
  val.classVal

proc toInstance*(val: NodeValue): Instance =
  if val.kind != vkInstance:
    raise newException(ValueError, "Not an instance: " & val.toString)
  val.instVal

proc toArray*(val: NodeValue): seq[NodeValue] =
  if val.kind != vkArray:
    raise newException(ValueError, "Not an array: " & val.toString)
  val.arrayVal

proc toTable*(val: NodeValue): Table[string, NodeValue] =
  if val.kind != vkTable:
    raise newException(ValueError, "Not a table: " & val.toString)
  val.tableVal

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

var
  rootClass*: Class = nil                      # Root class (zero methods)
  objectClass*: Class = nil                     # Object class, derives from Root
  mixinClass*: Class = nil                      # Mixin class, sibling to Object (slotless, can mix with any type)
  booleanClass*: Class = nil
  integerClass*: Class = nil
  floatClass*: Class = nil
  stringClass*: Class = nil
  arrayClass*: Class = nil
  tableClass*: Class = nil
  blockClass*: Class = nil

# Forward declarations
proc newClass*(parents: seq[Class] = @[], slotNames: seq[string] = @[], name: string = ""): Class

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
    objectClass = newClass(parents = @[rootClass], name = "Object")
    objectClass.tags = @["Object"]
  return objectClass

proc initMixinClass*(): Class =
  ## Initialize the global Mixin class (inherits from Root, sibling to Object)
  ## Mixin is a slotless class that can be mixed into any other class type
  ## Use Mixin derive: methods: [...] to create reusable trait/mixin classes
  if mixinClass == nil:
    # Ensure Root exists first
    discard initRootClass()
    mixinClass = newClass(parents = @[rootClass], name = "Mixin")
    mixinClass.tags = @["Mixin", "Object"]  # Mark as Mixin for type compatibility
  return mixinClass

# ============================================================================
# Class and Instance Helpers
# ============================================================================

proc isMixin*(cls: Class): bool =
  ## Check if a class is a mixin (has no slots at all, can't define slots)
  ## A mixin can be used as additional parent classes without affecting instance type
  return "Mixin" in cls.tags or cls.allSlotNames.len == 0

proc newClass*(parents: seq[Class] = @[], slotNames: seq[string] = @[], name: string = ""): Class =
  ## Create a new Class with given parents and slot names
  result = Class()
  result.methods = initTable[string, BlockNode]()
  result.allMethods = initTable[string, BlockNode]()
  result.classMethods = initTable[string, BlockNode]()
  result.classMethods = initTable[string, BlockNode]()
  result.allClassMethods = initTable[string, BlockNode]()
  result.slotNames = slotNames
  result.allSlotNames = @[]
  result.parents = parents
  result.subclasses = @[]
  result.name = name
  result.tags = @["Class"]
  result.isNimProxy = false
  result.nimtalkType = ""
  result.hasSlots = slotNames.len > 0

  # Check for slot name conflicts from parents
  var seenSlotNames: seq[string] = @[]
  for parent in parents:
    for slotName in parent.allSlotNames:
      if slotName in seenSlotNames:
        raise newException(ValueError, "Slot name conflict: '" & slotName & "' exists in multiple parents")
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

  # Check for method selector conflicts between parents (only for directly-defined methods)
  # Inherited methods should not cause conflicts
  # Note: use derive:parents:ivarArray:methods: to specify method overrides
  var seenInstanceMethods: seq[string] = @[]
  var seenClassMethods: seq[string] = @[]
  for parent in parents:
    for selector in parent.methods.keys:  # Only check directly-defined instance methods
      if selector in seenInstanceMethods:
        raise newException(ValueError, "Method selector conflict: '" & selector & "' exists in multiple parents (use derive:parents:ivarArray:methods: to specify method overrides)")
      seenInstanceMethods.add(selector)
    for selector in parent.classMethods.keys:  # Only check directly-defined class methods
      if selector in seenClassMethods:
        raise newException(ValueError, "Class method selector conflict: '" & selector & "' exists in multiple parents")
      seenClassMethods.add(selector)

  # Add to parents' subclasses lists and inherit methods
  for parent in parents:
    parent.subclasses.add(result)
    # Inherit instance methods (unless child overrides)
    for selector, methodBlock in parent.allMethods:
      if selector notin result.methods:  # Only inherit if not overridden
        result.allMethods[selector] = methodBlock
    # Inherit class methods
    for selector, methodBlock in parent.allClassMethods:
      result.allClassMethods[selector] = methodBlock
    # Inherit slot names
    for slotName in parent.allSlotNames:
      if slotName notin result.allSlotNames:
        result.allSlotNames.add(slotName)
  # Add own slot names
  for slotName in slotNames:
    if slotName notin result.allSlotNames:
      result.allSlotNames.add(slotName)

proc addParent*(cls: Class, parent: Class) =
  ## Add a parent to an existing class
  ## Useful for resolving method conflicts by adding parent after overriding methods
  if parent in cls.parents:
    return  # Already has this parent

  # Check for slot name conflicts (only for directly-defined slots on this parent)
  for slotName in parent.slotNames:
    if slotName in cls.allSlotNames and slotName notin cls.slotNames:
      raise newException(ValueError, "Slot name conflict: '" & slotName & "' already exists in existing parent hierarchy")

  # Check for method selector conflicts (only for directly-defined methods on this parent)
  # Only error if child doesn't override
  for selector in parent.methods.keys:  # Only check directly-defined instance methods
    if selector in cls.allMethods and selector notin cls.methods:
      # Child inherits this method from another parent but it conflicts with this parent's directly-defined method
      raise newException(ValueError, "Method selector conflict: '" & selector & "' exists in existing parent (override in child class first)")

  for selector in parent.classMethods.keys:  # Only check directly-defined class methods
    if selector in cls.allClassMethods and selector notin cls.classMethods:
      # Child inherits this class method from another parent but it conflicts with this parent's directly-defined method
      raise newException(ValueError, "Class method selector conflict: '" & selector & "' exists in existing parent (override in child class first)")

  # Add parent
  cls.parents.add(parent)
  parent.subclasses.add(cls)

  # Inherit instance methods (unless child overrides)
  for selector, methodBlock in parent.allMethods:
    if selector notin cls.methods and selector notin cls.allMethods:
      cls.allMethods[selector] = methodBlock

  # Inherit class methods
  for selector, methodBlock in parent.allClassMethods:
    if selector notin cls.classMethods and selector notin cls.allClassMethods:
      cls.allClassMethods[selector] = methodBlock

  # Inherit slot names
  for slotName in parent.allSlotNames:
    if slotName notin cls.allSlotNames:
      cls.allSlotNames.add(slotName)

  # Update hasSlots flag if needed
  if cls.allSlotNames.len > 0:
    cls.hasSlots = true

proc newInstance*(cls: Class): Instance =
  ## Create a new Instance of the given Class (ikObject variant)
  result = Instance(kind: ikObject, class: cls)
  result.slots = newSeq[NodeValue](cls.allSlotNames.len)
  # Initialize all slots to nil
  for i in 0..<result.slots.len:
    result.slots[i] = nilValue()
  result.isNimProxy = false
  result.nimValue = nil

proc newIntInstance*(cls: Class, value: int): Instance =
  ## Create a new Integer instance with direct value storage
  Instance(kind: ikInt, class: cls, intVal: value, isNimProxy: false, nimValue: nil)

proc newFloatInstance*(cls: Class, value: float): Instance =
  ## Create a new Float instance with direct value storage
  Instance(kind: ikFloat, class: cls, floatVal: value, isNimProxy: false, nimValue: nil)

proc newStringInstance*(cls: Class, value: string): Instance =
  ## Create a new String instance with direct value storage
  Instance(kind: ikString, class: cls, strVal: value, isNimProxy: false, nimValue: nil)

proc newArrayInstance*(cls: Class, elements: seq[NodeValue]): Instance =
  ## Create a new Array instance
  Instance(kind: ikArray, class: cls, elements: elements, isNimProxy: false, nimValue: nil)

proc newTableInstance*(cls: Class, entries: Table[string, NodeValue]): Instance =
  ## Create a new Table instance
  Instance(kind: ikTable, class: cls, entries: entries, isNimProxy: false, nimValue: nil)

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

# Helper procs for Instance variant checking
proc isInt*(inst: Instance): bool = inst.kind == ikInt
proc isFloat*(inst: Instance): bool = inst.kind == ikFloat
proc isString*(inst: Instance): bool = inst.kind == ikString
proc isArray*(inst: Instance): bool = inst.kind == ikArray
proc isTable*(inst: Instance): bool = inst.kind == ikTable
proc isObject*(inst: Instance): bool = inst.kind == ikObject

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

proc getTableEntries*(inst: Instance): Table[string, NodeValue] =
  if inst.kind != ikTable:
    raise newException(ValueError, "Not a table instance")
  inst.entries

proc getTableValue*(inst: Instance, key: string): NodeValue =
  ## Get a value from a table instance
  if inst.kind != ikTable:
    return nilValue()
  if key in inst.entries:
    return inst.entries[key]
  return nilValue()

proc setTableValue*(inst: Instance, key: string, value: NodeValue) =
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
      return Instance(kind: ikInt, class: nil, intVal: val.intVal, isNimProxy: false, nimValue: nil)
  of vkFloat:
    if floatClass != nil:
      return newFloatInstance(floatClass, val.floatVal)
    else:
      return Instance(kind: ikFloat, class: nil, floatVal: val.floatVal, isNimProxy: false, nimValue: nil)
  of vkString:
    if stringClass != nil:
      return newStringInstance(stringClass, val.strVal)
    else:
      return Instance(kind: ikString, class: nil, strVal: val.strVal, isNimProxy: false, nimValue: nil)
  of vkArray:
    if arrayClass != nil:
      return newArrayInstance(arrayClass, val.arrayVal)
    else:
      return Instance(kind: ikArray, class: nil, elements: val.arrayVal, isNimProxy: false, nimValue: nil)
  of vkTable:
    if tableClass != nil:
      return newTableInstance(tableClass, val.tableVal)
    else:
      return Instance(kind: ikTable, class: nil, entries: val.tableVal, isNimProxy: false, nimValue: nil)
  of vkBool:
    # Boolean values - store in nimValue for compatibility
    let p = cast[pointer](alloc(sizeof(bool)))
    cast[ptr bool](p)[] = val.boolVal
    return Instance(kind: ikObject, class: booleanClass, slots: @[], isNimProxy: true, nimValue: p)
  of vkBlock:
    # Blocks are passed as-is, created as ikObject instances
    return Instance(kind: ikObject, class: blockClass, slots: @[], isNimProxy: false, nimValue: nil)
  of vkClass, vkNil, vkSymbol:
    raise newException(ValueError, "Cannot convert " & $val.kind & " to Instance")
