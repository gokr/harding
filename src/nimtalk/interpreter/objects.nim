import std/[tables, strutils, sequtils, logging]
import ../core/types

# ============================================================================
# Object System for Nimtalk
# Prototype-based objects with delegation
# ============================================================================

# Forward declarations for core method implementations (exported for testing)
proc cloneImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc deriveImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc deriveWithIVarsImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc atImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc atPutImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc plusImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc printStringImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc writeImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc writelineImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc getSlotImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc setSlotValueImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc concatImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc atCollectionImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc sizeImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
proc atCollectionPutImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue
# doCollectionImpl is defined in evaluator.nim as it needs interpreter context

# Global root object (singleton)
var rootObject*: RootObject = nil

# Global Dictionary prototype (singleton)
var dictionaryPrototype*: DictionaryPrototype = nil

# Create a core method


proc createCoreMethod*(name: string): BlockNode =
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
  ## Add a method to an object's method dictionary using canonical symbol
  let sym = getSymbol(selector)
  obj.methods[sym.symVal] = blk

proc addDictionaryProperty*(dict: DictionaryObj, name: string, value: NodeValue) =
  ## Add a property to a Dictionary's property bag
  dict.properties[name] = value

# Global namespace for storing "classes" and constants
var globals*: Table[string, NodeValue]

# Initialize global namespace
proc initGlobals*() =
  ## Initialize the globals table for storing classes and constants
  if globals.len == 0:
    globals = initTable[string, NodeValue]()

# Add a value to globals (typically a "class")
proc addGlobal*(name: string, value: NodeValue) =
  ## Add a global binding (e.g., Person := Object derive)
  globals[name] = value

# Get a value from globals
proc getGlobal*(name: string): NodeValue =
  ## Get a global binding, return nil if not found
  if globals.hasKey(name):
    return globals[name]
  else:
    return nilValue()

# Check if a global exists
proc hasGlobal*(name: string): bool =
  ## Check if a global binding exists
  return globals.hasKey(name)

# Remove a global
proc removeGlobal*(name: string) =
  ## Remove a global binding
  if globals.hasKey(name):
    globals.del(name)

# Get all global names
proc globalNames*(): seq[string] =
  ## Return all global names
  return toSeq(globals.keys)

# Forward declaration for doesNotUnderstandImpl
proc doesNotUnderstandImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue

# Initialize root object with core methods
proc initRootObject*(): RootObject =
  ## Initialize the global root object with core methods
  if rootObject == nil:
    # Initialize symbol table and globals first
    initSymbolTable()
    initGlobals()

    rootObject = RootObject()
    rootObject.methods = initTable[string, BlockNode]()
    rootObject.parents = @[]
    rootObject.tags = @["Object", "Proto"]
    rootObject.isNimProxy = false
    rootObject.nimValue = nil
    rootObject.nimType = ""
    rootObject.hasSlots = false
    rootObject.slots = @[]
    rootObject.slotNames = initTable[string, int]()

    # Add Object to globals immediately
    addGlobal("Object", NodeValue(kind: vkObject, objVal: rootObject))

    # Install core Object methods
    let cloneMethod = createCoreMethod("clone")
    cloneMethod.nativeImpl = cast[pointer](cloneImpl)
    addMethod(rootObject, "clone", cloneMethod)

    let deriveMethod = createCoreMethod("derive")
    deriveMethod.nativeImpl = cast[pointer](deriveImpl)
    addMethod(rootObject, "derive", deriveMethod)

    let deriveWithIVarsMethod = createCoreMethod("derive:")
    deriveWithIVarsMethod.nativeImpl = cast[pointer](deriveWithIVarsImpl)
    addMethod(rootObject, "derive:", deriveWithIVarsMethod)

    let getSlotMethod = createCoreMethod("getSlot:")
    getSlotMethod.nativeImpl = cast[pointer](getSlotImpl)
    addMethod(rootObject, "getSlot:", getSlotMethod)

    let setSlotValueMethod = createCoreMethod("setSlot:value:")
    setSlotValueMethod.nativeImpl = cast[pointer](setSlotValueImpl)
    addMethod(rootObject, "setSlot:value:", setSlotValueMethod)

    let printStringMethod = createCoreMethod("printString")
    printStringMethod.nativeImpl = cast[pointer](printStringImpl)
    addMethod(rootObject, "printString", printStringMethod)

    let dnuMethod = createCoreMethod("doesNotUnderstand:")
    dnuMethod.nativeImpl = cast[pointer](doesNotUnderstandImpl)
    addMethod(rootObject, "doesNotUnderstand:", dnuMethod)

    # Add arithmetic operators
    let plusMethod = createCoreMethod("+")
    plusMethod.nativeImpl = cast[pointer](plusImpl)
    addMethod(rootObject, "+", plusMethod)

    # Add string concatenation operator (, in Smalltalk)
    let concatMethod = createCoreMethod(",")
    concatMethod.nativeImpl = cast[pointer](concatImpl)
    addMethod(rootObject, ",", concatMethod)

    # Add collection access method
    let atCollectionMethod = createCoreMethod("at:")
    atCollectionMethod.nativeImpl = cast[pointer](atCollectionImpl)
    addMethod(rootObject, "at:", atCollectionMethod)

    # Add collection size method
    let sizeMethod = createCoreMethod("size")
    sizeMethod.nativeImpl = cast[pointer](sizeImpl)
    addMethod(rootObject, "size", sizeMethod)

    # Add collection write method
    let atPutMethod = createCoreMethod("at:put:")
    atPutMethod.nativeImpl = cast[pointer](atCollectionPutImpl)
    addMethod(rootObject, "at:put:", atPutMethod)

    # Initialize Dictionary prototype
    dictionaryPrototype = DictionaryPrototype()
    dictionaryPrototype.methods = initTable[string, BlockNode]()
    dictionaryPrototype.parents = @[rootObject.ProtoObject]
    dictionaryPrototype.tags = @["Dictionary", "Proto"]
    dictionaryPrototype.isNimProxy = false
    dictionaryPrototype.nimValue = nil
    dictionaryPrototype.nimType = ""
    dictionaryPrototype.hasSlots = false
    dictionaryPrototype.slots = @[]
    dictionaryPrototype.slotNames = initTable[string, int]()
    dictionaryPrototype.properties = initTable[string, NodeValue]()

    # Add Dictionary to globals
    addGlobal("Dictionary", NodeValue(kind: vkObject, objVal: dictionaryPrototype.ProtoObject))

    # Install Dictionary-specific methods (at: and at:put:)
    let dictAtMethod = createCoreMethod("at:")
    dictAtMethod.nativeImpl = cast[pointer](atImpl)
    addMethod(dictionaryPrototype.ProtoObject, "at:", dictAtMethod)

    let dictAtPutMethod = createCoreMethod("at:put:")
    dictAtPutMethod.nativeImpl = cast[pointer](atPutImpl)
    addMethod(dictionaryPrototype.ProtoObject, "at:put:", dictAtPutMethod)

  return rootObject

# Nim-level clone function for ProtoObject - returns NodeValue wrapper
proc clone*(self: ProtoObject): NodeValue =
  ## Shallow clone of ProtoObject (Nim-level clone) wrapped in NodeValue
  let objClone = ProtoObject()
  objClone.methods = initTable[string, BlockNode]()
  for key, value in self.methods:
    objClone.methods[key] = value
  objClone.parents = self.parents
  objClone.tags = self.tags
  objClone.isNimProxy = self.isNimProxy
  objClone.nimValue = self.nimValue
  objClone.nimType = self.nimType
  objClone.hasSlots = self.hasSlots
  objClone.slots = self.slots  # Copy slots by value (seq is value type)
  objClone.slotNames = self.slotNames
  result = NodeValue(kind: vkObject, objVal: objClone)

# Nim-level clone function for RootObject - returns NodeValue wrapper
proc clone*(self: RootObject): NodeValue =
  ## Shallow clone of RootObject (Nim-level clone) wrapped in NodeValue
  let objClone = RootObject()
  objClone.methods = initTable[string, BlockNode]()
  for key, value in self.methods:
    objClone.methods[key] = value
  objClone.parents = self.parents
  objClone.tags = self.tags
  objClone.isNimProxy = self.isNimProxy
  objClone.nimValue = self.nimValue
  objClone.nimType = self.nimType
  result = NodeValue(kind: vkObject, objVal: objClone)

# Nim-level clone function for DictionaryObj - returns NodeValue wrapper
proc clone*(self: DictionaryObj): NodeValue =
  ## Shallow clone of DictionaryObj (Nim-level clone) wrapped in NodeValue
  let objClone = DictionaryObj()
  objClone.methods = initTable[string, BlockNode]()
  for key, value in self.methods:
    objClone.methods[key] = value
  objClone.parents = self.parents
  objClone.tags = self.tags
  objClone.isNimProxy = self.isNimProxy
  objClone.nimValue = self.nimValue
  objClone.nimType = self.nimType
  objClone.hasSlots = self.hasSlots
  objClone.slots = self.slots
  objClone.slotNames = self.slotNames
  objClone.properties = self.properties  # Copy properties for Dictionary
  result = NodeValue(kind: vkObject, objVal: objClone.ProtoObject)

# Core method implementations
proc cloneImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Shallow clone of object
  # For Dictionary objects, use Dictionary-specific clone
  if self of DictionaryObj:
    let selfDict = cast[DictionaryObj](self)
    let clone = DictionaryObj()
    clone.properties = selfDict.properties
    clone.methods = selfDict.methods
    clone.parents = selfDict.parents
    clone.tags = selfDict.tags
    clone.isNimProxy = false
    clone.nimValue = nil
    clone.nimType = ""
    clone.hasSlots = selfDict.hasSlots
    clone.slots = selfDict.slots
    clone.slotNames = selfDict.slotNames
    return NodeValue(kind: vkObject, objVal: clone.ProtoObject)

  # Regular ProtoObject clone
  let clone = ProtoObject()
  clone.methods = self.methods  # Copy methods table, don't create empty one
  clone.parents = self.parents
  clone.tags = self.tags
  clone.isNimProxy = false
  clone.nimValue = nil
  clone.nimType = ""
  clone.hasSlots = self.hasSlots
  clone.slots = self.slots
  clone.slotNames = self.slotNames
  return NodeValue(kind: vkObject, objVal: clone)

proc deriveImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Create child with self as parent (prototype delegation)
  # If deriving from Dictionary, create a Dictionary child
  if self of DictionaryObj:
    let child = DictionaryObj()
    child.properties = initTable[string, NodeValue]()
    child.methods = initTable[string, BlockNode]()
    child.parents = @[self]
    child.tags = self.tags & @["derived"]
    child.isNimProxy = false
    child.nimValue = nil
    child.nimType = ""
    child.hasSlots = false
    child.slots = @[]
    child.slotNames = initTable[string, int]()
    return NodeValue(kind: vkObject, objVal: child.ProtoObject)

  # Regular ProtoObject derivation
  let child = ProtoObject()
  child.methods = initTable[string, BlockNode]()
  child.parents = @[self]
  child.tags = self.tags & @["derived"]
  child.isNimProxy = false
  child.nimValue = nil
  child.nimType = ""

  # Inherit slots if parent has them
  if self.hasSlots:
    child.hasSlots = true
    child.slots = newSeq[NodeValue](self.slots.len)
    child.slotNames = self.slotNames
    # Initialize all slots to nil (copy parent's structure but not values)
    for i in 0..<self.slots.len:
      child.slots[i] = nilValue()
  else:
    child.hasSlots = false
    child.slots = @[]
    child.slotNames = initTable[string, int]()

  return NodeValue(kind: vkObject, objVal: child)

proc deriveWithIVarsImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Create child with self as parent and declared instance variables
  ## Also generates accessor methods for all instance variables
  if args.len < 1:
    raise newException(ValueError, "derive:: requires array of ivar names")

  # Extract ivar names from array (handle both raw arrays and wrapped array objects)
  var ivarArray: seq[NodeValue]
  if args[0].kind == vkArray:
    ivarArray = args[0].arrayVal
  elif args[0].kind == vkObject and args[0].objVal.isNimProxy and args[0].objVal.nimType == "array":
    # Unwrap proxy array - extract elements from properties
    if args[0].objVal of DictionaryObj:
      let dict = cast[DictionaryObj](args[0].objVal)
      # Get elements from properties (stored with numeric keys)
      var i = 0
      while true:
        let key = $i
        if not dict.properties.hasKey(key):
          break
        ivarArray.add(dict.properties[key])
        inc i
    else:
      raise newException(ValueError, "derive:: first argument must be array of strings")
  else:
    raise newException(ValueError, "derive:: first argument must be array of strings, got: " & $args[0].kind)
  var childIvars: seq[string] = @[]
  for ivarVal in ivarArray:
    if ivarVal.kind != vkSymbol:
      raise newException(ValueError, "derive:: all ivar names must be symbols")
    childIvars.add(ivarVal.symVal)

  # If parent has slots, inherit them first
  var allIvars: seq[string] = @[]
  if self.hasSlots:
    # Inherit parent's ivars
    allIvars = self.getSlotNames()

  # Add child's new ivars (checking for duplicates)
  for ivar in childIvars:
    if ivar in allIvars:
      raise newException(ValueError, "Instance variable conflict: " & ivar & " already defined in parent")
    allIvars.add(ivar)

  # Determine if parent is a Dictionary
  let parentIsDictionary = self of DictionaryObj

  # Create object with combined slots
  var child: ProtoObject
  if parentIsDictionary:
    # Create Dictionary-derived object with slots
    let dictChild = DictionaryObj()
    dictChild.methods = initTable[string, BlockNode]()
    dictChild.parents = @[self]
    dictChild.tags = self.tags & @["derived"]
    dictChild.isNimProxy = false
    dictChild.nimValue = nil
    dictChild.nimType = ""
    dictChild.properties = initTable[string, NodeValue]()

    if allIvars.len > 0:
      dictChild.hasSlots = true
      dictChild.slots = newSeq[NodeValue](allIvars.len)
      dictChild.slotNames = initTable[string, int]()
      for i in 0..<allIvars.len:
        dictChild.slots[i] = nilValue()
        dictChild.slotNames[allIvars[i]] = i
    else:
      dictChild.hasSlots = false
      dictChild.slots = @[]
      dictChild.slotNames = initTable[string, int]()

    child = dictChild.ProtoObject
  else:
    if allIvars.len > 0:
      child = initSlotObject(allIvars)
    else:
      # Fallback to empty object if no ivars
      child = ProtoObject()
      child.methods = initTable[string, BlockNode]()
      child.parents = @[]
      child.tags = @[]
      child.isNimProxy = false
      child.nimValue = nil
      child.nimType = ""
      child.hasSlots = false
      child.slots = @[]
      child.slotNames = initTable[string, int]()

    child.parents = @[self]
  child.tags = self.tags & @["derived", "slotted"]

  # Generate accessor methods for all instance variables
  for ivar in allIvars:
    # Generate getter: ivar -> slots[slotNames[ivar]]
    var getterBody: seq[Node] = @[]
    var msgArgs: seq[Node] = @[]
    msgArgs.add(LiteralNode(value: getSymbol(ivar)))
    getterBody.add(ReturnNode(
      expression: MessageNode(
        receiver: nil,  # implicit self
        selector: "getSlot:",
        arguments: msgArgs
      )
    ))

    let getterBlock = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: getterBody,
      isMethod: true
    )
    child.methods[ivar] = getterBlock

    # Generate setter: ivar: value -> slots[slotNames[ivar]] := value
    var setterBody: seq[Node] = @[]
    var setterArgs: seq[Node] = @[]
    setterArgs.add(LiteralNode(value: getSymbol(ivar)))
    setterArgs.add(IdentNode(name: "newValue"))  # Variable reference for parameter
    setterBody.add(AssignNode(
      variable: "<ignore>",  # Assignment to slot via setSlot
      expression: MessageNode(
        receiver: nil,
        selector: "setSlot:value:",
        arguments: setterArgs
      )
    ))
    setterBody.add(ReturnNode(
      expression: IdentNode(name: "newValue")  # Variable reference for parameter
    ))

    let setterBlock = BlockNode(
      parameters: @["newValue"],
      temporaries: @[],
      body: setterBody,
      isMethod: true
    )
    child.methods[ivar & ":"] = setterBlock

  return NodeValue(kind: vkObject, objVal: child)

proc atImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Get property value from Dictionary: dict at: 'key'
  if args.len < 1:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()  # at: only works on Dictionary objects

  let keyVal = args[0]
  var key: string
  case keyVal.kind
  of vkSymbol:
    key = keyVal.symVal
  of vkString:
    key = keyVal.strVal
  else:
    return nilValue()

  let dict = cast[DictionaryObj](self)
  return getProperty(dict, key)

proc atPutImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Set property value on Dictionary: dict at: 'key' put: value
  if args.len < 2:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()  # at:put: only works on Dictionary objects

  let keyVal = args[0]
  var key: string
  case keyVal.kind
  of vkSymbol:
    key = keyVal.symVal
  of vkString:
    key = keyVal.strVal
  else:
    return nilValue()

  let value = args[1]
  debug("Setting property: ", key, " = ", value.toString())
  let dict = cast[DictionaryObj](self)
  setProperty(dict, key, value)
  return value

proc plusImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Add two numbers: a + b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  if self.isNimProxy and self.nimType == "int" and other.kind == vkInt:
    # Both are integers, add them
    let a = cast[ptr int](self.nimValue)[]
    let b = other.intVal
    return NodeValue(kind: vkInt, intVal: a + b)

  return nilValue()

proc printStringImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Default print representation
  if self.isNimProxy and self.nimType == "int":
    let val = cast[ptr int](self.nimValue)[]
    return NodeValue(kind: vkString, strVal: $val)
  elif self.isNimProxy:
    return NodeValue(kind: vkString, strVal: "<Nim " & self.nimType & ">")
  elif "Object" in self.tags:
    return NodeValue(kind: vkString, strVal: "<object>")
  else:
    return NodeValue(kind: vkString, strVal: "<unknown>")

proc writeImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Write string to stdout without newline (Stdout write: 'text')
  if args.len < 1:
    return nilValue()
  let strVal = args[0]
  if strVal.kind == vkString:
    stdout.write(strVal.strVal)
    flushFile(stdout)
  return strVal  ## Return the string written

proc writelineImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Write string or integer to stdout with newline (Stdout writeline: value)
  if args.len < 1:
    stdout.write("\n")
  else:
    let value = args[0]
    case value.kind
    of vkString:
      echo value.strVal  ## echo adds newline
    of vkInt:
      echo value.intVal
    else:
      echo value.toString()
  return nilValue()

proc getSlotImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Get slot value: obj getSlot: 'key'
  if args.len < 1:
    return nilValue()
  let keyVal = args[0]
  var key: string
  case keyVal.kind
  of vkSymbol:
    key = keyVal.symVal
  of vkString:
    key = keyVal.strVal
  else:
    return nilValue()
  return getSlot(self, key)

proc setSlotValueImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Set slot value: obj setSlot: 'key' value: value
  if args.len < 2:
    return nilValue()
  let keyVal = args[0]
  var key: string
  case keyVal.kind
  of vkSymbol:
    key = keyVal.symVal
  of vkString:
    key = keyVal.strVal
  else:
    return nilValue()
  let value = args[1]
  setSlot(self, key, value)
  return value

proc doesNotUnderstandImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Default handler for unknown messages
  if args.len < 1 or args[0].kind != vkSymbol:
    raise newException(ValueError, "doesNotUnderstand: requires message symbol")

  let selector = args[0].symVal
  raise newException(ValueError, "Message not understood: " & selector)

proc concatImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Concatenate strings: a , b (Smalltalk style using , operator)
  if args.len < 1:
    return nilValue()

  let other = args[0]

  # Handle string concatenation
  if self.isNimProxy and self.nimType == "string":
    # Get self string value from properties
    if self of DictionaryObj:
      let dict = cast[DictionaryObj](self)
      let selfVal = dict.properties.getOrDefault("__value")
      if selfVal.kind == vkString:
        let selfStr = selfVal.strVal
        # Get other string value
        if other.kind == vkString:
          return NodeValue(kind: vkString, strVal: selfStr & other.strVal)
        elif other.kind == vkObject and other.objVal.isNimProxy and other.objVal.nimType == "string":
          if other.objVal of DictionaryObj:
            let otherDict = cast[DictionaryObj](other.objVal)
            let otherVal = otherDict.properties.getOrDefault("__value")
            if otherVal.kind == vkString:
              return NodeValue(kind: vkString, strVal: selfStr & otherVal.strVal)

  return nilValue()

proc atCollectionImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Get element from array or table: arr at: index OR table at: key
  if args.len < 1:
    return nilValue()

  let key = args[0]

  # Handle array access (1-based indexing like Smalltalk)
  # Arrays are stored as DictionaryObj with numeric keys
  if self.isNimProxy and self.nimType == "array":
    if key.kind == vkInt:
      let idx = key.intVal - 1  # Convert to 0-based
      if self of DictionaryObj:
        let dict = cast[DictionaryObj](self)
        let keyStr = $idx
        if dict.properties.hasKey(keyStr):
          return dict.properties[keyStr]
    return nilValue()

  # Handle table access
  # Tables are stored as DictionaryObj with string keys
  if self.isNimProxy and self.nimType == "table":
    var keyStr: string
    if key.kind == vkString:
      keyStr = key.strVal
    elif key.kind == vkSymbol:
      keyStr = key.symVal
    else:
      return nilValue()
    if self of DictionaryObj:
      let dict = cast[DictionaryObj](self)
      if dict.properties.hasKey(keyStr):
        return dict.properties[keyStr]
    return nilValue()

  return nilValue()

proc sizeImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Get size of array: arr size
  # Handle array size
  if self.isNimProxy and self.nimType == "array":
    if self of DictionaryObj:
      let dict = cast[DictionaryObj](self)
      # Count contiguous elements starting from indices 0, 1, 2, ...
      var size = 0
      while dict.properties.hasKey($size):
        size += 1
      return NodeValue(kind: vkInt, intVal: size)
  return nilValue()

proc atCollectionPutImpl*(self: ProtoObject, args: seq[NodeValue]): NodeValue =
  ## Set element in array: arr at: index put: value
  if args.len < 2:
    return nilValue()

  let key = args[0]
  let value = args[1]

  # Handle array write (1-based indexing like Smalltalk)
  if self.isNimProxy and self.nimType == "array":
    if key.kind == vkInt:
      let idx = key.intVal - 1  # Convert to 0-based
      if idx >= 0 and self of DictionaryObj:
        let dict = cast[DictionaryObj](self)
        let keyStr = $idx
        dict.properties[keyStr] = value
        return value
  return nilValue()

proc wrapIntAsObject*(value: int): NodeValue =
  ## Wrap an integer as a Nim proxy object that can receive messages
  let obj = ProtoObject()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[rootObject.ProtoObject]
  obj.tags = @["Integer", "Number"]
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](alloc(sizeof(int)))
  cast[ptr int](obj.nimValue)[] = value
  obj.nimType = "int"
  obj.hasSlots = false
  obj.slots = @[]
  obj.slotNames = initTable[string, int]()
  return NodeValue(kind: vkObject, objVal: obj)

proc wrapBoolAsObject*(value: bool): NodeValue =
  ## Wrap a boolean as a Nim proxy object that can receive messages
  let obj = ProtoObject()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[rootObject.ProtoObject]
  obj.tags = @["Boolean"]
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](alloc(sizeof(bool)))
  cast[ptr bool](obj.nimValue)[] = value
  obj.nimType = "bool"
  obj.hasSlots = false
  obj.slots = @[]
  obj.slotNames = initTable[string, int]()
  return NodeValue(kind: vkObject, objVal: obj)

proc newObject*(): ProtoObject =
  ## Create a new lightweight object (no property bag)
  let obj = ProtoObject()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["derived"]
  obj.isNimProxy = false
  obj.nimValue = nil
  obj.nimType = ""
  obj.hasSlots = false
  obj.slots = @[]
  obj.slotNames = initTable[string, int]()
  return obj

proc newDictionary*(properties = initTable[string, NodeValue]()): DictionaryObj =
  ## Create a new Dictionary object with property bag
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().ProtoObject]
  obj.tags = @["Dictionary", "derived"]
  obj.isNimProxy = false
  obj.nimValue = nil
  obj.nimType = ""
  obj.hasSlots = false
  obj.slots = @[]
  obj.slotNames = initTable[string, int]()
  obj.properties = properties
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
  var output = spaces & "Object"

  if obj.tags.len > 0:
    output.add(" [" & obj.tags.join(", ") & "]")
  output.add("\n")

  if obj of DictionaryObj:
    let dictObj = cast[DictionaryObj](obj)
    if dictObj.properties.len > 0:
      output.add(spaces & "  properties:\n")
      for key, val in dictObj.properties:
        output.add(spaces & "    " & key & ": " & val.toString() & "\n")

  if obj.methods.len > 0:
    output.add(spaces & "  methods:\n")
    for selector in obj.methods.keys:
      output.add(spaces & "    " & selector & "\n")

  if obj.parents.len > 0:
    output.add(spaces & "  parents:\n")
    for parent in obj.parents:
      output.add(printObject(parent, indent + 2))

  return output

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
