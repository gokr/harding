import std/[tables, strutils, sequtils]
import ../core/types
import ../parser/parser

# ============================================================================
# Object System for Nimtalk
# Prototype-based objects with delegation
# ============================================================================

# Global root object (singleton)
var rootObject*: RootObject = nil

# Create a core method
type CoreMethodProc = proc(self: ProtoObject, args: seq[NodeValue]): NodeValue {.nimcall.}

type CoreMutMethodProc = proc(self: var ProtoObject, args: seq[NodeValue]): NodeValue {.nimcall.}

proc createCoreMethod(name: string): BlockNode =
  ## Create a method stub
  let blk = BlockNode()
  blk.parameters = if ':' in name:
                      name.split(':').filterIt(it.len > 0)
                    else:
                      @[]
  blk.temporaries = @[]
  let placeholder: Node = LiteralNode(value: NodeValue(kind: vkNil))  # Placeholder
  blk.body = @[placeholder]
  blk.isMethod = true
  blk.nativeImpl = nil
  return blk

# Method installation
proc addMethod*(obj: ProtoObject, selector: string, blk: BlockNode) =
  ## Add a method to an object's method dictionary
  obj.methods[selector] = blk

proc addProperty*(obj: ProtoObject, name: string, value: NodeValue) =
  ## Add a property to an object's property dictionary
  obj.properties[name] = value

# Initialize root object with core methods
proc initRootObject*(): RootObject =
  ## Initialize the global root object with core methods
  if rootObject == nil:
    rootObject = RootObject()
    rootObject.properties = initTable[string, NodeValue]()
    rootObject.methods = initTable[string, BlockNode]()
    rootObject.parents = @[]
    rootObject.tags = @["Object", "Proto"]
    rootObject.isNimProxy = false
    rootObject.nimValue = nil
    rootObject.nimType = ""

    # Install core methods
    addMethod(rootObject, "clone", createCoreMethod("clone"))
    addMethod(rootObject, "derive", createCoreMethod("derive"))
    addMethod(rootObject, "at:", createCoreMethod("at:"))
    addMethod(rootObject, "at:put:", createCoreMethod("at:put:"))
    addMethod(rootObject, "printString", createCoreMethod("printString"))
    addMethod(rootObject, "doesNotUnderstand:", createCoreMethod("doesNotUnderstand:"))

  return rootObject

# Nim-level clone function for ProtoObject - returns NodeValue wrapper
proc clone*(self: ProtoObject): NodeValue =
  ## Shallow clone of ProtoObject (Nim-level clone) wrapped in NodeValue
  let objClone = ProtoObject()
  objClone.properties = self.properties
  objClone.methods = initTable[string, BlockNode]()
  for key, value in self.methods:
    objClone.methods[key] = value
  objClone.parents = self.parents
  objClone.tags = self.tags
  objClone.isNimProxy = self.isNimProxy
  objClone.nimValue = self.nimValue
  objClone.nimType = self.nimType
  result = NodeValue(kind: vkObject, objVal: objClone)

# Nim-level clone function for RootObject - returns NodeValue wrapper
proc clone*(self: RootObject): NodeValue =
  ## Shallow clone of RootObject (Nim-level clone) wrapped in NodeValue
  let objClone = RootObject()
  objClone.properties = self.properties
  objClone.methods = initTable[string, BlockNode]()
  for key, value in self.methods:
    objClone.methods[key] = value
  objClone.parents = self.parents
  objClone.tags = self.tags
  objClone.isNimProxy = self.isNimProxy
  objClone.nimValue = self.nimValue
  objClone.nimType = self.nimType
  result = NodeValue(kind: vkObject, objVal: objClone)

# Core method implementations
proc cloneImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Shallow clone of object
  let clone = ProtoObject()
  clone.properties = self.properties
  clone.methods = initTable[string, BlockNode]()
  clone.parents = self.parents
  clone.tags = self.tags
  clone.isNimProxy = false
  clone.nimValue = nil
  clone.nimType = ""
  return NodeValue(kind: vkObject, objVal: clone)

proc deriveImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Create child with self as parent (prototype delegation)
  let child = ProtoObject()
  child.properties = initTable[string, NodeValue]()
  child.methods = initTable[string, BlockNode]()
  child.parents = @[self]
  child.tags = self.tags & @["derived"]
  child.isNimProxy = false
  child.nimValue = nil
  child.nimType = ""
  return NodeValue(kind: vkObject, objVal: child)

proc atImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Get property value: obj at: 'key'
  if args.len < 1:
    return nilValue()
  if args[0].kind != vkSymbol:
    return nilValue()

  let key = args[0].symVal
  return getProperty(self, key)

proc atPutImpl(self: var ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Set property value: obj at: 'key' put: value
  if args.len < 2:
    return nilValue()
  if args[0].kind != vkSymbol:
    return nilValue()

  let key = args[0].symVal
  let value = args[1]
  setProperty(self, key, value)
  return value

proc printStringImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Default print representation
  if self.isNimProxy:
    return NodeValue(kind: vkString, strVal: "<Nim " & self.nimType & ">")
  elif "Object" in self.tags:
    return NodeValue(kind: vkString, strVal: "<object>")
  else:
    return NodeValue(kind: vkString, strVal: "<unknown>")

proc doesNotUnderstandImpl(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Default handler for unknown messages
  if args.len < 1 or args[0].kind != vkSymbol:
    raise newException(ValueError, "doesNotUnderstand: requires message symbol")

  let selector = args[0].symVal
  raise newException(ValueError, "Message not understood: " & selector)

# Map method names to implementations (not currently used)
# var coreMethods: Table[string, CoreMethodProc]
#
# proc initCoreMethods() =
#   if coreMethods.len == 0:
#     coreMethods = {
#       "clone": cloneImpl,
#       "derive": deriveImpl,
#       "at:": atImpl,
#       "at:put:": atPutImpl,
#       "printString": printStringImpl,
#       "doesNotUnderstand:": doesNotUnderstandImpl
#     }.toTable

# Object creation helpers
proc newObject*(properties = initTable[string, NodeValue]()): ProtoObject =
  ## Create a new object with optional properties
  let obj = ProtoObject()
  obj.properties = properties
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]  # Convert to base type
  obj.tags = @["derived"]
  obj.isNimProxy = false
  obj.nimValue = nil
  obj.nimType = ""
  return obj

# Object comparison
proc isSame*(obj1, obj2: ProtoObject): bool =
  ## Check if two objects are the same (identity)
  return obj1 == obj2

proc inheritsFrom*(obj: ProtoObject, parent: ProtoObject): bool =
  ## Check if object inherits from parent in prototype chain
  if obj.isSame(parent):
    return true

  for p in obj.parents:
    if inheritsFrom(p, parent):
      return true

  return false

# Display helpers
proc printObject*(obj: ProtoObject, indent: int = 0): string =
  ## Pretty print object structure
  let spaces = repeat(' ', indent * 2)
  var result = spaces & "Object"

  if obj.tags.len > 0:
    result.add(" [" & obj.tags.join(", ") & "]")
  result.add("\n")

  if obj.properties.len > 0:
    result.add(spaces & "  properties:\n")
    for key, val in obj.properties:
      result.add(spaces & "    " & key & ": " & val.toString() & "\n")

  if obj.methods.len > 0:
    result.add(spaces & "  methods:\n")
    for selector in obj.methods.keys:
      result.add(spaces & "    " & selector & "\n")

  if obj.parents.len > 0:
    result.add(spaces & "  parents:\n")
    for parent in obj.parents:
      result.add(printObject(parent, indent + 2))

  return result

# String interpolation and formatting
proc formatString*(tmpl: string, args: Table[string, NodeValue]): string =
  ## Simple string formatting with placeholders
  result = tmpl
  for key, val in args:
    let placeholder = "{" & key & "}"
    result = result.replace(placeholder, val.toString())

# Create a simple test object hierarchy (commented out - needs proper method invocation)
# proc makeTestObjects*(): (RootObject, ProtoObject, ProtoObject) =
#   ## Create test object hierarchy for testing
#   let root = initRootObject()
#
#   # Create Animal prototype
#   let animal = newObject()
#   animal.tags = @["Animal"]
#   animal.properties = {
#     "species": NodeValue(kind: vkString, strVal: "unknown"),
#     "sound": NodeValue(kind: vkString, strVal: "silence")
#   }.toTable
#
#   # Add makeSound method
#   let makeSoundBlock = BlockNode(
#     parameters: @[],
#     temporaries: @[],
#     body: @[LiteralNode(
#       value: NodeValue(kind: vkNil)
#     )],
#     isMethod: true
#   )
#   addMethod(animal, "makeSound", makeSoundBlock)
#
#   # Create Dog instance
#   let dog = newObject()
#   dog.parents = @[animal]
#   dog.properties["species"] = NodeValue(kind: vkString, strVal: "dog")
#   dog.properties["breed"] = NodeValue(kind: vkString, strVal: "golden retriever")
#
#   return (root, animal, dog)
