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
  # Class-Based Object Model (New)
  # ============================================================================

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
    class*: Class                           # Reference to class
    slots*: seq[NodeValue]                  # Instance data only (indexed by allSlotNames position)
    isNimProxy*: bool                       # Instance wraps Nim value
    nimValue*: pointer                      # Pointer to actual Nim value (for FFI)

  # ============================================================================
  # Legacy Runtime Types (to be migrated to Class/Instance model)
  # ============================================================================

  RuntimeObject* {.acyclic.} = ref object of RootObj
    methods*: Table[string, BlockNode]     # method dictionary
    parents*: seq[RuntimeObject]           # inheritance chain
    tags*: seq[string]                     # type tags
    isNimProxy*: bool                      # wraps Nim value
    nimValue*: pointer                     # proxied Nim value
    nimType*: string                       # Nim type name
    hasSlots*: bool                        # true if object has declared instance variables
    slots*: seq[NodeValue]                 # instance variables (faster than property bag)
    slotNames*: Table[string, int]         # maps ivar names to slot indices

  DictionaryObj* = ref object of RuntimeObject
    ## Dictionary - runtime object with property bag for dynamic key-value storage
    properties*: Table[string, NodeValue]  # property bag for dynamic objects

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
    sender*: Activation       # calling context
    receiver*: RuntimeObject    # 'self'
    currentMethod*: BlockNode # current method
    definingObject*: RuntimeObject  # object where method was found (for super)
    pc*: int                  # program counter
    locals*: Table[string, NodeValue]  # local variables
    capturedVars*: Table[string, MutableCell]  # shared captured vars for sibling blocks
    returnValue*: NodeValue   # return value
    hasReturned*: bool        # non-local return flag

  # Value types for AST nodes and runtime values
  ValueKind* = enum
    vkInt, vkFloat, vkString, vkSymbol, vkBool, vkNil, vkObject, vkBlock,
    vkArray, vkTable, vkClass, vkInstance

  NodeValue* = object
    case kind*: ValueKind
    of vkInt: intVal*: int
    of vkFloat: floatVal*: float
    of vkString: strVal*: string
    of vkSymbol: symVal*: string
    of vkBool: boolVal*: bool
    of vkNil: discard
    of vkObject: objVal*: RuntimeObject
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

  # Identifier node for variable lookup
  IdentNode* = ref object of Node
    name*: string

  # Slot access node for efficient instance variable access
  SlotAccessNode* = ref object of Node
    slotName*: string      # Name for debugging
    slotIndex*: int        # Index in allSlotNames (updated on layout change)
    isAssignment*: bool    # true for slot: value, false for slot

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
    nkArray, nkTable, nkObjectLiteral, nkPrimitive, nkCascade, nkSlotAccess, nkSuperSend, nkPseudoVar

  # Root object (global singleton)
  RootObject* = ref object of RuntimeObject
    ## Global root object - parent of all objects

  # Dictionary prototype (singleton)
  DictionaryPrototype* = ref object of DictionaryObj
    ## Global Dictionary - provides property bag functionality

  # FileStream object for file I/O
  FileStreamObj* = ref object of RuntimeObject
    file*: File
    mode*: string
    isOpen*: bool

  # Exception object for error handling
  ExceptionObj* = ref object of RuntimeObject
    message*: string
    stackTrace*: string
    signaler*: RuntimeObject

  # Global registry object - shared between Nim and Nimtalk
  GlobalObj* = ref object of RuntimeObject
    tableRef*: ref Table[string, NodeValue]  # Shared heap-allocated table
    categories*: Table[string, seq[string]]  # category name -> global names

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
  of vkInstance: "<instance of " & val.instVal.class.name & ">"
  of vkObject: "<object>"
  of vkBlock: "<block>"
  of vkArray: "#(" & $val.arrayVal.len & ")"
  of vkTable: "#{" & $val.tableVal.len & "}"

proc toValue*(i: int): NodeValue =
  NodeValue(kind: vkInt, intVal: i)

proc toValue*(f: float): NodeValue =
  NodeValue(kind: vkFloat, floatVal: f)

proc toValue*(s: string): NodeValue =
  NodeValue(kind: vkString, strVal: s)

proc toValue*(b: bool): NodeValue =
  NodeValue(kind: vkBool, boolVal: b)

proc nilValue*(): NodeValue =
  NodeValue(kind: vkNil)

# ============================================================================
# Procs and utilities for slot-based instance variables
# ============================================================================

proc initSlotObject*(ivars: seq[string]): RuntimeObject =
  ## Create object with declared instance variables (slots)
  result = RuntimeObject()
  result.methods = initTable[string, BlockNode]()
  result.parents = @[]
  result.tags = @["slotted"]
  result.isNimProxy = false
  result.nimValue = nil
  result.nimType = ""
  result.hasSlots = true
  result.slots = newSeq[NodeValue](ivars.len)
  result.slotNames = initTable[string, int]()

  # Initialize all slots to nil
  for i in 0..<ivars.len:
    result.slots[i] = nilValue()
    result.slotNames[ivars[i]] = i

proc initDictionaryObject*(): DictionaryObj =
  ## Create a new Dictionary object with property bag
  result = DictionaryObj()
  result.methods = initTable[string, BlockNode]()
  result.parents = @[]
  result.tags = @["Dictionary"]
  result.isNimProxy = false
  result.nimValue = nil
  result.nimType = ""
  result.hasSlots = false
  result.slots = @[]
  result.slotNames = initTable[string, int]()
  result.properties = initTable[string, NodeValue]()

proc getSlot*(obj: RuntimeObject, name: string): NodeValue =
  ## Get slot value by name (returns nil if not found)
  when not defined(release):
    debug "getSlot: looking up '", name, "'"
    debug "  hasSlots: ", obj.hasSlots
    debug "  slotNames: ", obj.slotNames
  if not obj.hasSlots or not obj.slotNames.hasKey(name):
    when not defined(release):
      debug "  not found, returning nil"
    return nilValue()
  when not defined(release):
    debug "  found at index ", obj.slotNames[name]
  let idx = obj.slotNames[name]
  return obj.slots[idx]

proc setSlot*(obj: RuntimeObject, name: string, value: NodeValue) =
  ## Set slot value by name (does nothing if slot doesn't exist)
  when not defined(release):
    debug "setSlot called: '", name, "' = ", value.toString()
    debug "  hasSlots: ", obj.hasSlots
    debug "  hasKey: ", obj.slotNames.hasKey(name)
  if not obj.hasSlots or not obj.slotNames.hasKey(name):
    when not defined(release):
      debug "  setSlot: returning early (no slots or key not found)"
    return
  let idx = obj.slotNames[name]
  when not defined(release):
    debug "  setting at index ", idx
  obj.slots[idx] = value

proc hasSlotIVars*(obj: RuntimeObject): bool =
  ## Check if object has declared instance variables (slots)
  return obj.hasSlots

proc getSlotNames*(obj: RuntimeObject): seq[string] =
  ## Get all instance variable names
  if not obj.hasSlots:
    return @[]
  # Create temp array of (index, name) pairs
  var pairs: seq[tuple[idx: int, name: string]] = @[]
  for name, idx in obj.slotNames:
    pairs.add((idx, name))
  # Sort by index
  pairs.sort(proc(a, b: tuple[idx: int, name: string]): int = a.idx - b.idx)
  # Extract just the names in order
  result = @[]
  for pair in pairs:
    result.add(pair.name)

proc toValue*(arr: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkArray, arrayVal: arr)

proc toValue*(tab: Table[string, NodeValue]): NodeValue =
  NodeValue(kind: vkTable, tableVal: tab)

proc toValue*(obj: RuntimeObject): NodeValue =
  NodeValue(kind: vkObject, objVal: obj)

proc toValue*(blk: BlockNode): NodeValue =
  NodeValue(kind: vkBlock, blockVal: blk)

proc toValue*(cls: Class): NodeValue =
  NodeValue(kind: vkClass, classVal: cls)

proc toValue*(inst: Instance): NodeValue =
  NodeValue(kind: vkInstance, instVal: inst)

proc toObject*(val: NodeValue): RuntimeObject =
  if val.kind != vkObject:
    raise newException(ValueError, "Not an object: " & val.toString)
  val.objVal

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

# Dictionary property helpers
proc getProperty*(dict: DictionaryObj, name: string): NodeValue =
  ## Get property value from dictionary or its class hierarchy
  if dict.properties.hasKey(name):
    return dict.properties[name]
  # Search class hierarchy for Dictionary parents
  for parent in dict.parents:
    if parent of DictionaryObj:
      let val = cast[DictionaryObj](parent).getProperty(name)
      if val.kind != vkNil:
        return val
  # Not found
  nilValue()

proc setProperty*(dict: DictionaryObj, name: string, value: NodeValue) =
  ## Set property on dictionary (not on parent classes)
  debug("setProperty for Dictionary: ", $dict.tags, " name: ", name, " = ", value.toString())
  dict.properties[name] = value

# Generic lookup that delegates to DictionaryObj if applicable
proc getPropertyGeneric*(obj: RuntimeObject, name: string): NodeValue =
  ## Get property value - works for Dictionary objects, returns nil for others
  if obj of DictionaryObj:
    return cast[DictionaryObj](obj).getProperty(name)
  return nilValue()

proc lookupMethod*(obj: RuntimeObject, selector: string): BlockNode =
  ## Look up method in object or class hierarchy
  ## NOTE: This is a stub - actual implementation in objects.nim
  nil


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
# Class and Instance Helpers
# ============================================================================

proc newClass*(parents: seq[Class] = @[], slotNames: seq[string] = @[], name: string = ""): Class =
  ## Create a new Class with given parents and slot names
  result = Class()
  result.methods = initTable[string, BlockNode]()
  result.allMethods = initTable[string, BlockNode]()
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

proc newInstance*(cls: Class): Instance =
  ## Create a new Instance of the given Class
  result = Instance()
  result.class = cls
  result.slots = newSeq[NodeValue](cls.allSlotNames.len)
  # Initialize all slots to nil
  for i in 0..<result.slots.len:
    result.slots[i] = nilValue()
  result.isNimProxy = false
  result.nimValue = nil

proc getSlotIndex*(cls: Class, name: string): int =
  ## Get slot index by name, returns -1 if not found
  for i, slotName in cls.allSlotNames:
    if slotName == name:
      return i
  return -1

proc getSlot*(inst: Instance, index: int): NodeValue =
  ## Get slot value by index
  if index < 0 or index >= inst.slots.len:
    return nilValue()
  return inst.slots[index]

proc setSlot*(inst: Instance, index: int, value: NodeValue) =
  ## Set slot value by index
  if index >= 0 and index < inst.slots.len:
    inst.slots[index] = value

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
