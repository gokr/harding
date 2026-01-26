import std/tables

# ============================================================================
# Core Types for Nimtalk
# ============================================================================

# All type definitions in a single section to allow forward declarations
type
  Node* = ref object of RootObj
    line*, col*: int

  ProtoObject* = ref object of RootObj
    properties*: Table[string, NodeValue]  # instance variables
    methods*: Table[string, BlockNode]     # method dictionary
    parents*: seq[ProtoObject]             # prototype chain
    tags*: seq[string]                     # type tags
    isNimProxy*: bool                      # wraps Nim value
    nimValue*: pointer                     # proxied Nim value
    nimType*: string                       # Nim type name

  BlockNode* = ref object of Node
    parameters*: seq[string]   # method parameters
    temporaries*: seq[string]  # local variables
    body*: seq[Node]           # AST statements
    isMethod*: bool            # true if method definition
    nativeImpl*: pointer       # compiled implementation

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

  # Node type enum for pattern matching
  NodeKind* = enum
    nkLiteral, nkMessage, nkBlock, nkAssign, nkReturn,
    nkArray, nkTable, nkObjectLiteral

  # Root object (global singleton)
  RootObject* = ref object of ProtoObject
    ## Global root object - parent of all objects

  # Activation records for method execution
  Activation* = ref object of RootObj
    sender*: Activation       # calling context
    receiver*: ProtoObject    # 'self'
    currentMethod*: BlockNode # current method
    pc*: int                  # program counter
    locals*: Table[string, NodeValue]  # local variables
    returnValue*: NodeValue   # return value
    hasReturned*: bool        # non-local return flag

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
# Procs and utilities
# ============================================================================

# Node kind helper
proc kind*(node: Node): NodeKind =
  ## Get the node kind for pattern matching
  if node of LiteralNode: nkLiteral
  elif node of MessageNode: nkMessage
  elif node of BlockNode: nkBlock
  elif node of AssignNode: nkAssign
  elif node of ReturnNode: nkReturn
  elif node of ArrayNode: nkArray
  elif node of TableNode: nkTable
  elif node of ObjectLiteralNode: nkObjectLiteral
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

# Property and method helpers (will be fully implemented in objects.nim)
proc getProperty*(obj: ProtoObject, name: string): NodeValue =
  ## Get property value from object or its prototype chain
  ## NOTE: This is a stub - actual implementation in objects.nim
  nilValue()

proc setProperty*(obj: var ProtoObject, name: string, value: NodeValue) =
  ## Set property on object (not in prototypes)
  ## NOTE: This is a stub - actual implementation in objects.nim
  discard

proc lookupMethod*(obj: ProtoObject, selector: string): BlockNode =
  ## Look up method in object or prototype chain
  ## NOTE: This is a stub - actual implementation in objects.nim
  nil
