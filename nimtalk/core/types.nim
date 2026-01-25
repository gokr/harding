import std/[tables, strutils]

# ============================================================================
# Core Types for NimTalk
# ============================================================================

# Forward declarations
type
  Node* = ref object of RootObj
    line*, col*: int

  ProtoObject = ref object of RootObj
  BlockNode = ref object of Node

# Value types for AST nodes and runtime values
type
  ValueKind* = enum
    vkInt, vkFloat, vkString, vkSymbol, vkBool, vkNil, vkObject, vkBlock

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

  # BlockNode already complete

# AST Node specific types (Node already declared above as ref object of RootObj)
    parameters*: seq[string]
    temporaries*: seq[string]
    body*: seq[Node]
    isMethod*: bool
    nativeImpl*: pointer

# AST Node specific types (Node already declared above as ref object of RootObj)
type
  LiteralNode* = ref object of Node
    value*: NodeValue

  MessageNode* = ref object of Node
    receiver*: Node          # nil for implicit self
    selector*: string
    arguments*: seq[Node]
    isCascade*: bool

  # BlockNode already declared above, just continue to next type

  AssignNode* = ref object of Node
    variable*: string
    expression*: Node

  ReturnNode* = ref object of Node
    expression*: Node        # nil for self-return

  NodeKind* = enum
    nkLiteral, nkMessage, nkBlock, nkAssign, nkReturn

# Root object (global singleton) - ProtoObject already declared above
  RootObject* = ref object of ProtoObject      # Global root object

# Activation records for method execution
type
  Activation* = ref object of RootObj
    sender*: Activation       # calling context
    receiver*: ProtoObject    # 'self'
    currentMethod*: BlockNode        # current method
    pc*: int                  # program counter
    locals*: Table[string, NodeValue]  # local variables
    returnValue*: NodeValue   # return value
    hasReturned*: bool        # non-local return flag

# Compiled method representation
type
  CompiledMethod* = ref object of RootObj
    selector*: string
    arity*: int
    nativeAddr*: pointer      # compiled function pointer
    symbolName*: string       # .so symbol name

# Method entries (can be interpreted or compiled)
type
  MethodEntry* = object
    case isCompiled*: bool
    of false:
      interpreted*: BlockNode
    of true:
      compiled*: CompiledMethod

# Node conversion helpers
proc kind*(node: Node): NodeKind =
  ## Get the node kind for pattern matching
  if node of LiteralNode: nkLiteral
  elif node of MessageNode: nkMessage
  elif node of BlockNode: nkBlock
  elif node of AssignNode: nkAssign
  elif node of ReturnNode: nkReturn
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

# Object conversion utilities
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

# Property access helpers
proc getProperty*(obj: ProtoObject, name: string): NodeValue =
  ## Get property value from object or its prototype chain
  if name in obj.properties:
    return obj.properties[name]

  # Search parent chain
  for parent in obj.parents:
    let result = getProperty(parent, name)
    if result.kind != vkNil:
      return result

  return nilValue()

proc setProperty*(obj: var ProtoObject, name: string, value: NodeValue) =
  ## Set property on object (not in prototypes)
  obj.properties[name] = value

# Method lookup helper
proc lookupMethod*(obj: ProtoObject, selector: string): BlockNode =
  ## Look up method in object or prototype chain
  if selector in obj.methods:
    return obj.methods[selector]

  # Search parent chain
  for parent in obj.parents:
    let result = lookupMethod(parent, selector)
    if result != nil:
      return result

  return nil
