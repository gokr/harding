import std/[tables, algorithm, hashes, logging]

# ============================================================================
# Core Types for Nimtalk
# ============================================================================

# All type definitions in a single section to allow forward declarations
type
  Node* = ref object of RootObj
    line*, col*: int

  ProtoObject* = ref object of RootObj
    methods*: Table[string, BlockNode]     # method dictionary
    parents*: seq[ProtoObject]             # prototype chain
    tags*: seq[string]                     # type tags
    isNimProxy*: bool                      # wraps Nim value
    nimValue*: pointer                     # proxied Nim value
    nimType*: string                       # Nim type name
    hasSlots*: bool                        # true if object has declared instance variables
    slots*: seq[NodeValue]                 # instance variables (faster than property bag)
    slotNames*: Table[string, int]         # maps ivar names to slot indices

  DictionaryObj* = ref object of ProtoObject
    ## Dictionary - prototype with property bag for dynamic key-value storage
    properties*: Table[string, NodeValue]  # property bag for dynamic objects

  # Mutable cell for captured variables (shared between closures)
  MutableCell* = ref object
    value*: NodeValue          # the captured value

  # Forward declarations to break circular dependency
  Activation* = ref ActivationObj

  BlockNode* = ref object of Node
    parameters*: seq[string]              # method parameters
    temporaries*: seq[string]             # local variables
    body*: seq[Node]                      # AST statements
    isMethod*: bool                       # true if method definition
    nativeImpl*: pointer                  # compiled implementation
    hasInterpreterParam*: bool            # true if native method needs interpreter parameter
    capturedEnv*: Table[string, MutableCell]  # captured variables from outer scope
    homeActivation*: Activation           # for non-local returns: method that created this block

  # Activation records for method execution (defined after BlockNode)
  ActivationObj* = object of RootObj
    sender*: Activation       # calling context
    receiver*: ProtoObject    # 'self'
    currentMethod*: BlockNode # current method
    definingObject*: ProtoObject  # object where method was found (for super)
    pc*: int                  # program counter
    locals*: Table[string, NodeValue]  # local variables
    returnValue*: NodeValue   # return value
    hasReturned*: bool        # non-local return flag

  # Value types for AST nodes and runtime values
  ValueKind* = enum
    vkInt, vkFloat, vkString, vkSymbol, vkBool, vkNil, vkObject, vkBlock,
    vkArray, vkTable

  NodeValue* = object
    case kind*: ValueKind
    of vkInt: intVal*: int
    of vkFloat: floatVal*: float
    of vkString: strVal*: string
    of vkSymbol: symVal*: string
    of vkBool: boolVal*: bool
    of vkNil: discard
    of vkObject: objVal*: ProtoObject
    of vkBlock: blockVal*: BlockNode
    of vkArray: arrayVal*: seq[NodeValue]
    of vkTable: tableVal*: Table[string, NodeValue]

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

  # Node type enum for pattern matching
  NodeKind* = enum
    nkLiteral, nkIdent, nkMessage, nkBlock, nkAssign, nkReturn,
    nkArray, nkTable, nkObjectLiteral, nkPrimitive, nkCascade

  # Root object (global singleton)
  RootObject* = ref object of ProtoObject
    ## Global root object - parent of all objects

  # Dictionary prototype (singleton)
  DictionaryPrototype* = ref object of DictionaryObj
    ## Global Dictionary prototype - provides property bag functionality

  # FileStream object for file I/O
  FileStreamObj* = ref object of ProtoObject
    file*: File
    mode*: string
    isOpen*: bool

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

proc initSlotObject*(ivars: seq[string]): ProtoObject =
  ## Create object with declared instance variables (slots)
  result = ProtoObject()
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

proc getSlot*(obj: ProtoObject, name: string): NodeValue =
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

proc setSlot*(obj: ProtoObject, name: string, value: NodeValue) =
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

proc hasSlotIVars*(obj: ProtoObject): bool =
  ## Check if object has declared instance variables (slots)
  return obj.hasSlots

proc getSlotNames*(obj: ProtoObject): seq[string] =
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

proc toValue*(obj: ProtoObject): NodeValue =
  NodeValue(kind: vkObject, objVal: obj)

proc toValue*(blk: BlockNode): NodeValue =
  NodeValue(kind: vkBlock, blockVal: blk)

proc toObject*(val: NodeValue): ProtoObject =
  if val.kind != vkObject:
    raise newException(ValueError, "Not an object: " & val.toString)
  val.objVal

proc toBlock*(val: NodeValue): BlockNode =
  if val.kind != vkBlock:
    raise newException(ValueError, "Not a block: " & val.toString)
  val.blockVal

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
  ## Get property value from dictionary or its prototype chain
  if dict.properties.hasKey(name):
    return dict.properties[name]
  # Search prototype chain for Dictionary prototypes
  for parent in dict.parents:
    if parent of DictionaryObj:
      let val = cast[DictionaryObj](parent).getProperty(name)
      if val.kind != vkNil:
        return val
  # Not found
  nilValue()

proc setProperty*(dict: DictionaryObj, name: string, value: NodeValue) =
  ## Set property on dictionary (not in prototypes)
  debug("setProperty for Dictionary: ", $dict.tags, " name: ", name, " = ", value.toString())
  dict.properties[name] = value

# Generic lookup that delegates to DictionaryObj if applicable
proc getPropertyGeneric*(obj: ProtoObject, name: string): NodeValue =
  ## Get property value - works for Dictionary objects, returns nil for others
  if obj of DictionaryObj:
    return cast[DictionaryObj](obj).getProperty(name)
  return nilValue()

proc lookupMethod*(obj: ProtoObject, selector: string): BlockNode =
  ## Look up method in object or prototype chain
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
