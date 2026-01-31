import std/[tables, strutils, sequtils, logging, math, os]
import ../core/types

# ============================================================================
# Object System for Nimtalk
# Class-based objects with delegation/inheritance
# ============================================================================

# Forward declarations for core method implementations (exported for testing)
proc cloneImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc deriveImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc deriveWithIVarsImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc atImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc atPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc selectorPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc wrapBoolAsObject*(value: bool): NodeValue
proc plusImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc minusImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc starImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc slashImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc sqrtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc ltImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc gtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc eqImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc leImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc geImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc neImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc intDivImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc backslashModuloImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc moduloImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc printStringImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc writeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc writelineImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc getSlotImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc setSlotValueImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc concatImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc atCollectionImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc sizeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc atCollectionPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc randomNextImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc randomNewImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
# Collection primitives
proc arrayNewImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc arraySizeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc arrayAddImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc arrayRemoveAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc arrayIncludesImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc arrayReverseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc arrayAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc arrayAtPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc tableNewImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc tableKeysImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc tableIncludesKeyImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc tableRemoveKeyImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc tableAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc tableAtPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
# String primitives
proc stringConcatImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringSizeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringFromToImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringIndexOfImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringIncludesSubStringImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringReplaceWithImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringUppercaseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringLowercaseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringTrimImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc stringSplitImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
# File primitives
proc fileOpenImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc fileCloseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc fileReadLineImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc fileWriteImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc fileAtEndImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc fileReadAllImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
# doCollectionImpl is defined in evaluator.nim as it needs interpreter context

# ============================================================================
# Helper: Extract integer value from NodeValue or wrapped object
# ============================================================================

proc tryGetInt*(value: NodeValue): (bool, int) =
  ## Try to extract an integer from a NodeValue
  ## Returns (true, value) if successful, (false, 0) otherwise
  case value.kind
  of vkInt:
    return (true, value.intVal)
  of vkObject:
    let obj = value.objVal
    if obj.isNimProxy and obj.nimType == "int":
      return (true, cast[ptr int](obj.nimValue)[])
  else:
    discard
  return (false, 0)

# ============================================================================
# Class-Based Object System (New)
# ============================================================================

# Forward declarations for class-based methods
proc classDeriveImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classNewImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classAddMethodImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classAddClassMethodImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc invalidateSubclasses*(cls: Class)
proc rebuildAllTables*(cls: Class)

# Global root class (singleton) - the new class-based root
var rootClass*: Class = nil

# Global root object (singleton) - legacy prototype-based root
var rootObject*: RootObject = nil

# Global Dictionary prototype (singleton)
var dictionaryPrototype*: DictionaryPrototype = nil

# Global Random prototype (singleton) - uses DictionaryObj for properties
var randomPrototype*: DictionaryObj = nil

# Global true/false values for comparison operators
var trueValue*: NodeValue = nilValue()
var falseValue*: NodeValue = nilValue()

# Class caches for wrapped primitives (set by loadStdlib)
var booleanClassCache*: RuntimeObject = nil
var trueClassCache*: RuntimeObject = nil
var falseClassCache*: RuntimeObject = nil
var numberClassCache*: RuntimeObject = nil
var integerClassCache*: RuntimeObject = nil
var stringClassCache*: RuntimeObject = nil
var arrayClassCache*: RuntimeObject = nil
var blockClassCache*: RuntimeObject = nil

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
proc addMethod*(obj: RuntimeObject, selector: string, blk: BlockNode) =
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

# Forward declarations for primitive implementations
proc doesNotUnderstandImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc propertiesImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc methodsImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue
proc isKindOfImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue

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
    rootObject.tags = @["Object"]
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

    # Register primitives with internal names for perform:with: support
    let primitiveCloneMethod = createCoreMethod("primitiveClone")
    primitiveCloneMethod.nativeImpl = cast[pointer](cloneImpl)
    addMethod(rootObject, "primitiveClone", primitiveCloneMethod)

    let primitiveDeriveMethod = createCoreMethod("primitiveDerive")
    primitiveDeriveMethod.nativeImpl = cast[pointer](deriveImpl)
    addMethod(rootObject, "primitiveDerive", primitiveDeriveMethod)

    let primitiveDeriveWithIVarsMethod = createCoreMethod("primitiveDeriveWithIVars:")
    primitiveDeriveWithIVarsMethod.nativeImpl = cast[pointer](deriveWithIVarsImpl)
    addMethod(rootObject, "primitiveDeriveWithIVars:", primitiveDeriveWithIVarsMethod)

    let primitiveAtMethod = createCoreMethod("primitiveAt:")
    primitiveAtMethod.nativeImpl = cast[pointer](atImpl)
    addMethod(rootObject, "primitiveAt:", primitiveAtMethod)

    let primitiveAtPutMethod = createCoreMethod("primitiveAt:put:")
    primitiveAtPutMethod.nativeImpl = cast[pointer](atPutImpl)
    addMethod(rootObject, "primitiveAt:put:", primitiveAtPutMethod)

    let primitiveHasPropertyMethod = createCoreMethod("primitiveHasProperty:")
    primitiveHasPropertyMethod.nativeImpl = cast[pointer](atImpl)  # atImpl handles property check
    addMethod(rootObject, "primitiveHasProperty:", primitiveHasPropertyMethod)

    let primitiveRespondsToMethod = createCoreMethod("primitiveRespondsTo:")
    primitiveRespondsToMethod.nativeImpl = cast[pointer](atImpl)  # Reuse atImpl for lookup
    addMethod(rootObject, "primitiveRespondsTo:", primitiveRespondsToMethod)

    let primitiveEqualsMethod = createCoreMethod("primitiveEquals:")
    primitiveEqualsMethod.nativeImpl = cast[pointer](eqImpl)
    addMethod(rootObject, "primitiveEquals:", primitiveEqualsMethod)

    let primitiveErrorMethod = createCoreMethod("primitiveError:")
    primitiveErrorMethod.nativeImpl = cast[pointer](doesNotUnderstandImpl)
    addMethod(rootObject, "primitiveError:", primitiveErrorMethod)

    # Register additional primitives for Object.nt methods
    let primitivePropertiesMethod = createCoreMethod("primitiveProperties")
    primitivePropertiesMethod.nativeImpl = cast[pointer](propertiesImpl)
    addMethod(rootObject, "primitiveProperties", primitivePropertiesMethod)

    let primitiveMethodsMethod = createCoreMethod("primitiveMethods")
    primitiveMethodsMethod.nativeImpl = cast[pointer](methodsImpl)
    addMethod(rootObject, "primitiveMethods", primitiveMethodsMethod)

    let primitiveIsKindOfMethod = createCoreMethod("primitiveIsKindOf:")
    primitiveIsKindOfMethod.nativeImpl = cast[pointer](isKindOfImpl)
    addMethod(rootObject, "primitiveIsKindOf:", primitiveIsKindOfMethod)

    let getSlotMethod = createCoreMethod("getSlot:")
    getSlotMethod.nativeImpl = cast[pointer](getSlotImpl)
    addMethod(rootObject, "getSlot:", getSlotMethod)

    let setSlotValueMethod = createCoreMethod("setSlot:value:")
    setSlotValueMethod.nativeImpl = cast[pointer](setSlotValueImpl)
    addMethod(rootObject, "setSlot:value:", setSlotValueMethod)

    # Add class-based method definition support
    # These are aliases for at:put: in the runtime system
    # In full class-based implementation, they would use the Class system

    let selectorPutMethod = createCoreMethod("selector:put:")
    selectorPutMethod.nativeImpl = cast[pointer](selectorPutImpl)
    addMethod(rootObject, "selector:put:", selectorPutMethod)

    let classSelectorPutMethod = createCoreMethod("classSelector:put:")
    classSelectorPutMethod.nativeImpl = cast[pointer](atPutImpl)
    addMethod(rootObject, "classSelector:put:", classSelectorPutMethod)

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

    let minusMethod = createCoreMethod("-")
    minusMethod.nativeImpl = cast[pointer](minusImpl)
    addMethod(rootObject, "-", minusMethod)

    let starMethod = createCoreMethod("*")
    starMethod.nativeImpl = cast[pointer](starImpl)
    addMethod(rootObject, "*", starMethod)

    let slashMethod = createCoreMethod("/")
    slashMethod.nativeImpl = cast[pointer](slashImpl)
    addMethod(rootObject, "/", slashMethod)

    let sqrtMethod = createCoreMethod("sqrt")
    sqrtMethod.nativeImpl = cast[pointer](sqrtImpl)
    addMethod(rootObject, "sqrt", sqrtMethod)

    # Add comparison operators
    let ltMethod = createCoreMethod("<")
    ltMethod.nativeImpl = cast[pointer](ltImpl)
    addMethod(rootObject, "<", ltMethod)

    let gtMethod = createCoreMethod(">")
    gtMethod.nativeImpl = cast[pointer](gtImpl)
    addMethod(rootObject, ">", gtMethod)

    let eqMethod = createCoreMethod("=")
    eqMethod.nativeImpl = cast[pointer](eqImpl)
    addMethod(rootObject, "=", eqMethod)

    let leMethod = createCoreMethod("<=")
    leMethod.nativeImpl = cast[pointer](leImpl)
    addMethod(rootObject, "<=", leMethod)

    let geMethod = createCoreMethod(">=")
    geMethod.nativeImpl = cast[pointer](geImpl)
    addMethod(rootObject, ">=", geMethod)

    let neMethod = createCoreMethod("~=")
    neMethod.nativeImpl = cast[pointer](neImpl)
    addMethod(rootObject, "~=", neMethod)

    let intDivMethod = createCoreMethod("//")
    intDivMethod.nativeImpl = cast[pointer](intDivImpl)
    addMethod(rootObject, "//", intDivMethod)

    let backslashModuloMethod = createCoreMethod("\\")
    backslashModuloMethod.nativeImpl = cast[pointer](backslashModuloImpl)
    addMethod(rootObject, "\\", backslashModuloMethod)

    let moduloMethod = createCoreMethod("%")
    moduloMethod.nativeImpl = cast[pointer](moduloImpl)
    addMethod(rootObject, "%", moduloMethod)

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
    dictionaryPrototype.parents = @[rootObject.RuntimeObject]
    dictionaryPrototype.tags = @["Dictionary"]
    dictionaryPrototype.isNimProxy = false
    dictionaryPrototype.nimValue = nil
    dictionaryPrototype.nimType = ""
    dictionaryPrototype.hasSlots = false
    dictionaryPrototype.slots = @[]
    dictionaryPrototype.slotNames = initTable[string, int]()
    dictionaryPrototype.properties = initTable[string, NodeValue]()

    # Add Dictionary to globals
    addGlobal("Dictionary", NodeValue(kind: vkObject, objVal: dictionaryPrototype.RuntimeObject))

    # Install Dictionary-specific methods (at: and at:put:)
    let dictAtMethod = createCoreMethod("at:")
    dictAtMethod.nativeImpl = cast[pointer](atImpl)
    addMethod(dictionaryPrototype.RuntimeObject, "at:", dictAtMethod)

    let dictAtPutMethod = createCoreMethod("at:put:")
    dictAtPutMethod.nativeImpl = cast[pointer](atPutImpl)
    addMethod(dictionaryPrototype.RuntimeObject, "at:put:", dictAtPutMethod)

    # Initialize Random prototype (uses DictionaryObj for properties)
    randomPrototype = DictionaryObj()
    randomPrototype.methods = initTable[string, BlockNode]()
    randomPrototype.parents = @[rootObject.RuntimeObject]
    randomPrototype.tags = @["Random"]
    randomPrototype.isNimProxy = false
    randomPrototype.nimValue = nil
    randomPrototype.nimType = ""
    randomPrototype.hasSlots = false
    randomPrototype.slots = @[]
    randomPrototype.slotNames = initTable[string, int]()
    randomPrototype.properties = initTable[string, NodeValue]()
    randomPrototype.properties["seed"] = NodeValue(kind: vkInt, intVal: 74755)

    # Add next method for Random
    let randomNextMethod = createCoreMethod("next")
    randomNextMethod.nativeImpl = cast[pointer](randomNextImpl)
    addMethod(randomPrototype, "next", randomNextMethod)

    # Add new method for Random
    let randomNewMethod = createCoreMethod("new")
    randomNewMethod.nativeImpl = cast[pointer](randomNewImpl)
    addMethod(randomPrototype, "new", randomNewMethod)

    # Add Random to globals
    addGlobal("Random", NodeValue(kind: vkObject, objVal: randomPrototype))

  return rootObject

# Nim-level clone function for RuntimeObject - returns NodeValue wrapper
proc clone*(self: RuntimeObject): NodeValue =
  ## Shallow clone of RuntimeObject (Nim-level clone) wrapped in NodeValue
  let objClone = RuntimeObject()
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
  # Deep copy properties, especially for blocks that have captured environments
  objClone.properties = initTable[string, NodeValue]()
  for key, value in self.properties:
    if value.kind == vkBlock:
      # Create a copy of the block with a fresh captured environment
      let origBlock = value.blockVal
      let newBlock = BlockNode(
        parameters: origBlock.parameters,
        temporaries: origBlock.temporaries,
        body: origBlock.body,
        isMethod: origBlock.isMethod,
        homeActivation: origBlock.homeActivation
      )
      # Copy captured environment (each clone gets its own cells)
      newBlock.capturedEnv = initTable[string, MutableCell]()
      for name, cell in origBlock.capturedEnv:
        newBlock.capturedEnv[name] = MutableCell(value: cell.value)
      objClone.properties[key] = NodeValue(kind: vkBlock, blockVal: newBlock)
    else:
      objClone.properties[key] = value
  result = NodeValue(kind: vkObject, objVal: objClone.RuntimeObject)

# Core method implementations
proc cloneImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Shallow clone of object
  # For Dictionary objects, use Dictionary-specific clone
  if self of DictionaryObj:
    let selfDict = cast[DictionaryObj](self)
    let clone = DictionaryObj()
    # Deep copy properties for blocks
    clone.properties = initTable[string, NodeValue]()
    for key, value in selfDict.properties:
      if value.kind == vkBlock:
        let origBlock = value.blockVal
        let newBlock = BlockNode(
          parameters: origBlock.parameters,
          temporaries: origBlock.temporaries,
          body: origBlock.body,
          isMethod: origBlock.isMethod,
          homeActivation: origBlock.homeActivation
        )
        newBlock.capturedEnv = initTable[string, MutableCell]()
        for name, cell in origBlock.capturedEnv:
          newBlock.capturedEnv[name] = MutableCell(value: cell.value)
        clone.properties[key] = NodeValue(kind: vkBlock, blockVal: newBlock)
      else:
        clone.properties[key] = value
    clone.methods = selfDict.methods
    clone.parents = selfDict.parents
    clone.tags = selfDict.tags
    clone.isNimProxy = false
    clone.nimValue = nil
    clone.nimType = ""
    clone.hasSlots = selfDict.hasSlots
    clone.slots = selfDict.slots
    clone.slotNames = selfDict.slotNames
    return NodeValue(kind: vkObject, objVal: clone.RuntimeObject)

  # Regular RuntimeObject clone
  let clone = RuntimeObject()
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

proc deriveImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Create child with self as parent (inheritance/delegation)
  # If deriving from Dictionary or Table, create a DictionaryObj child
  if self of DictionaryObj:
    let child = DictionaryObj()
    child.properties = initTable[string, NodeValue]()
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
      child.slotNames = self.slotNames  # Share slot names (they don't change)
      for i in 0..<self.slots.len:
        child.slots[i] = nilValue()  # Initialize with nil
    else:
      child.hasSlots = false
      child.slots = @[]
      child.slotNames = initTable[string, int]()

    return NodeValue(kind: vkObject, objVal: child.RuntimeObject)

  # Regular RuntimeObject derivation
  let child = RuntimeObject()
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

proc deriveWithIVarsImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
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
  var child: RuntimeObject
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

    child = dictChild.RuntimeObject
  else:
    if allIvars.len > 0:
      child = initSlotObject(allIvars)
    else:
      # Fallback to empty object if no ivars
      child = RuntimeObject()
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
    setterBody.add(MessageNode(
      receiver: nil,
      selector: "setSlot:value:",
      arguments: setterArgs
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

proc atImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
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

proc atPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
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

proc selectorPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Store a method in the object's method dictionary: obj selector: 'sel' put: [block]
  ## Works on any RuntimeObject, not just Dictionary
  if args.len < 2:
    return nilValue()

  # Get selector name
  var selector: string
  if args[0].kind == vkSymbol:
    selector = args[0].symVal
  elif args[0].kind == vkString:
    selector = args[0].strVal
  else:
    return nilValue()

  # Value must be a block
  if args[1].kind != vkBlock:
    return nilValue()

  let blockNode = args[1].blockVal
  blockNode.isMethod = true

  # Store in methods table
  self.methods[selector] = blockNode
  debug("Added method: ", selector, " to object with tags: ", $self.tags)
  return args[1]

proc plusImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Add two numbers: a + b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return NodeValue(kind: vkInt, intVal: a + otherVal)

  return nilValue()

proc minusImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Subtract two numbers: a - b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return NodeValue(kind: vkInt, intVal: a - otherVal)

  return nilValue()

proc starImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Multiply two numbers: a * b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return NodeValue(kind: vkInt, intVal: a * otherVal)

  # Handle float multiplication
  if self.isNimProxy and self.nimType == "int" and other.kind == vkFloat:
    let a = cast[ptr int](self.nimValue)[]
    let b = other.floatVal
    return NodeValue(kind: vkInt, intVal: int(float(a) * b))

  return nilValue()

proc slashImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Divide two numbers: a / b (integer division)
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    if otherVal == 0:
      return nilValue()  # Division by zero
    return NodeValue(kind: vkInt, intVal: a div otherVal)

  return nilValue()

proc sqrtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Square root: a sqrt
  if self.isNimProxy and self.nimType == "int":
    let a = cast[ptr int](self.nimValue)[]
    return NodeValue(kind: vkInt, intVal: int(sqrt(float(a))))

  return nilValue()

proc ltImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Less than comparison: a < b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return wrapBoolAsObject(a < otherVal)

  return nilValue()

proc gtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Greater than comparison: a > b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return wrapBoolAsObject(a > otherVal)

  return nilValue()

proc eqImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Equality comparison: a = b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return wrapBoolAsObject(a == otherVal)

  return nilValue()

proc leImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Less than or equal: a <= b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return wrapBoolAsObject(a <= otherVal)

  return nilValue()

proc geImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Greater than or equal: a >= b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return wrapBoolAsObject(a >= otherVal)

  return nilValue()

proc neImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Not equal: a ~= b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    return wrapBoolAsObject(a != otherVal)

  return nilValue()

proc intDivImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Integer division: a // b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    if otherVal == 0:
      return nilValue()  # Division by zero
    return NodeValue(kind: vkInt, intVal: a div otherVal)

  return nilValue()

proc backslashModuloImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Smalltalk-style modulo: a \\ b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    if otherVal == 0:
      return nilValue()  # Modulo by zero
    return NodeValue(kind: vkInt, intVal: a mod otherVal)

  return nilValue()

proc moduloImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Modulo: a % b
  if args.len < 1:
    return nilValue()

  let other = args[0]
  let (otherOk, otherVal) = tryGetInt(other)
  if self.isNimProxy and self.nimType == "int" and otherOk:
    let a = cast[ptr int](self.nimValue)[]
    if otherVal == 0:
      return nilValue()  # Modulo by zero
    return NodeValue(kind: vkInt, intVal: a mod otherVal)

  return nilValue()

proc printStringImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
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

proc writeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Write string to stdout without newline (Stdout write: 'text')
  if args.len < 1:
    return nilValue()
  let strVal = args[0]
  if strVal.kind == vkString:
    stdout.write(strVal.strVal)
    flushFile(stdout)
  return strVal  ## Return the string written

proc writelineImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
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

proc getSlotImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Get slot value: obj getSlot: 'key'
  when defined(release):
    discard  # No debug in release
  else:
    debug("getSlotImpl called with ", args.len, " args")
    if args.len > 0:
      debug("arg[0] kind: ", args[0].kind)
      if args[0].kind == vkSymbol:
        debug("arg[0] symVal: ", args[0].symVal)
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
    when defined(release):
      discard
    else:
      debug("getSlotImpl: key is not symbol or string, kind: ", keyVal.kind)
    return nilValue()
  when defined(release):
    discard
  else:
    debug("getSlotImpl: getting slot '", key, "'")
  return getSlot(self, key)

proc setSlotValueImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
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
  debug("setSlotValueImpl: setting slot '", key, "' to ", value.toString())
  when not defined(release):
    debug("  obj hasSlots: ", self.hasSlots)
    debug("  obj slotNames: ", self.slotNames)
  setSlot(self, key, value)
  return value

proc doesNotUnderstandImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Default handler for unknown messages
  if args.len < 1 or args[0].kind != vkSymbol:
    raise newException(ValueError, "doesNotUnderstand: requires message symbol")

  let selector = args[0].symVal
  raise newException(ValueError, "Message not understood: " & selector)

proc propertiesImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return collection of all property keys on this object
  ## For Dictionary objects, return the property keys
  if self of DictionaryObj:
    let dict = cast[DictionaryObj](self)
    var keys: seq[NodeValue] = @[]
    for key in dict.properties.keys:
      keys.add(NodeValue(kind: vkSymbol, symVal: key))
    return NodeValue(kind: vkArray, arrayVal: keys)
  ## For regular objects, return empty array (properties not supported)
  return NodeValue(kind: vkArray, arrayVal: @[])

proc methodsImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return collection of all method selectors on this object
  var selectors: seq[NodeValue] = @[]
  for selector in self.methods.keys:
    selectors.add(NodeValue(kind: vkSymbol, symVal: selector))
  return NodeValue(kind: vkArray, arrayVal: selectors)

proc isKindOfImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Check if object is kind of aClass (in class hierarchy)
  if args.len < 1:
    return NodeValue(kind: vkBool, boolVal: false)

  let aClass = args[0]
  if aClass.kind != vkObject or aClass.objVal == nil:
    return NodeValue(kind: vkBool, boolVal: false)

  var current = self
  while current != nil:
    if current == aClass.objVal:
      return NodeValue(kind: vkBool, boolVal: true)
    if current.parents.len > 0:
      current = current.parents[0]
    else:
      break

  return NodeValue(kind: vkBool, boolVal: false)

proc concatImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
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

proc atCollectionImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Get element from array or table: arr at: index OR table at: key
  ## Also handles DictionaryObj properties for regular objects
  when not defined(release):
    debug "atCollectionImpl called, nimType=", self.nimType, ", args.len=", args.len
    if args.len > 0:
      debug "  key kind=", args[0].kind, " value=", args[0].toString()
  if args.len < 1:
    return nilValue()

  let key = args[0]

  # Handle array access (1-based indexing like Smalltalk)
  # Arrays are stored as DictionaryObj with numeric keys
  if self.isNimProxy and self.nimType == "array":
    when not defined(release):
      debug "atCollectionImpl: array detected"
    if key.kind == vkInt:
      let idx = key.intVal - 1  # Convert to 0-based
      when not defined(release):
        debug "atCollectionImpl: key is int, idx=", idx
      if self of DictionaryObj:
        let dict = cast[DictionaryObj](self)
        let keyStr = $idx
        when not defined(release):
          debug "atCollectionImpl: looking for key '", keyStr, "'"
          for k in dict.properties.keys:
            debug "  properties key: ", k
        if dict.properties.hasKey(keyStr):
          debug "atCollectionImpl: found!"
          return dict.properties[keyStr]
        debug "atCollectionImpl: not found, returning nil"
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

  # Handle regular DictionaryObj property access
  # This allows at: to work on any Dictionary-based object (not just proxies)
  if self of DictionaryObj:
    var keyStr: string
    if key.kind == vkString:
      keyStr = key.strVal
    elif key.kind == vkSymbol:
      keyStr = key.symVal
    else:
      return nilValue()
    let dict = cast[DictionaryObj](self)
    when not defined(release):
      debug "atCollectionImpl: DictionaryObj property access for '", keyStr, "'"
    if dict.properties.hasKey(keyStr):
      return dict.properties[keyStr]
    when not defined(release):
      debug "atCollectionImpl: property not found"

  return nilValue()

proc sizeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Get size of array: arr size
  # Handle array size
  if self.isNimProxy and self.nimType == "array":
    if self of DictionaryObj:
      let dict = cast[DictionaryObj](self)
      # First check for __size property (used by arrayNewImpl)
      if dict.properties.hasKey("__size"):
        return dict.properties["__size"]
      # Fallback: count contiguous elements starting from indices 0, 1, 2, ...
      var size = 0
      while dict.properties.hasKey($size):
        size += 1
      return NodeValue(kind: vkInt, intVal: size)
  return nilValue()

proc atCollectionPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Set element in array: arr at: index put: value
  ## Also handles DictionaryObj properties for regular objects
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

  # Handle table write
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
      dict.properties[keyStr] = value
      return value

  # Handle regular DictionaryObj property write
  # This allows at:put: to work on any Dictionary-based object (not just proxies)
  if self of DictionaryObj:
    var keyStr: string
    if key.kind == vkString:
      keyStr = key.strVal
    elif key.kind == vkSymbol:
      keyStr = key.symVal
    else:
      return nilValue()
    when not defined(release):
      debug "atCollectionPutImpl: setting property '", keyStr, "' = ", value.toString()
    let dict = cast[DictionaryObj](self)
    dict.properties[keyStr] = value
    return value

  return nilValue()

proc randomNextImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Generate random integer: random next
  ## Uses same LCG as SOM: seed = (seed * 1309 + 13849) & 65535
  if self.tags.contains("Random") and self of DictionaryObj:
    let dict = cast[DictionaryObj](self)
    var seed: int
    if dict.properties.hasKey("seed"):
      seed = dict.properties["seed"].intVal
      # SOM-style LCG
      seed = ((seed * 1309) + 13849) and 65535
      dict.properties["seed"] = NodeValue(kind: vkInt, intVal: seed)
      return NodeValue(kind: vkInt, intVal: seed)
  return nilValue()

proc randomNewImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Create a new Random instance with fresh seed: Random new
  if self.tags.contains("Random") and self of DictionaryObj:
    let selfDict = cast[DictionaryObj](self)
    let randObj = DictionaryObj()
    randObj.methods = initTable[string, BlockNode]()
    randObj.parents = @[selfDict.RuntimeObject]
    randObj.tags = @["Random", "derived"]
    randObj.isNimProxy = false
    randObj.nimValue = nil
    randObj.nimType = ""
    randObj.hasSlots = false
    randObj.slots = @[]
    randObj.slotNames = initTable[string, int]()
    randObj.properties = initTable[string, NodeValue]()
    randObj.properties["seed"] = NodeValue(kind: vkInt, intVal: 74755)
    return NodeValue(kind: vkObject, objVal: randObj.RuntimeObject)
  return nilValue()

# ============================================================================
# Collection primitives for Array and Table
# ============================================================================

proc arrayNewImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Create new array with given size: Array new: 1000
  var size = 0
  if args.len >= 1 and args[0].kind == vkInt:
    size = args[0].intVal

  # Create array proxy with properties for 0-based indexing
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[rootObject.RuntimeObject]
  obj.tags = @["Array", "Collection"]
  obj.isNimProxy = true
  obj.nimType = "array"
  obj.properties = initTable[string, NodeValue]()
  obj.properties["__size"] = NodeValue(kind: vkInt, intVal: size)
  # Initialize all slots to nil
  for i in 0..<size:
    obj.properties[$i] = nilValue()
  return NodeValue(kind: vkObject, objVal: obj.RuntimeObject)

proc arraySizeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return number of elements in array
  if not (self of DictionaryObj):
    return NodeValue(kind: vkInt, intVal: 0)
  let dict = cast[DictionaryObj](self)
  if dict.properties.hasKey("__size"):
    return dict.properties["__size"]
  return NodeValue(kind: vkInt, intVal: 0)

proc arrayAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Get element at index (1-based indexing for Smalltalk compatibility)
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()
  let dict = cast[DictionaryObj](self)
  # Convert from 1-based (Smalltalk) to 0-based (internal storage)
  let idx = args[0].intVal - 1
  if idx < 0:
    return nilValue()
  let key = $idx
  if dict.properties.hasKey(key):
    return dict.properties[key]
  return nilValue()

proc arrayAtPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Set element at index (1-based indexing for Smalltalk compatibility)
  if args.len < 2 or args[0].kind != vkInt:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()
  let dict = cast[DictionaryObj](self)
  # Convert from 1-based (Smalltalk) to 0-based (internal storage)
  let idx = args[0].intVal - 1
  if idx < 0:
    return nilValue()
  let key = $idx
  dict.properties[key] = args[1]
  # Expand size if needed (store 1-based size for Smalltalk compatibility)
  let oneBasedIdx = args[0].intVal
  if dict.properties.hasKey("__size"):
    let size = dict.properties["__size"].intVal
    if oneBasedIdx > size:
      dict.properties["__size"] = NodeValue(kind: vkInt, intVal: oneBasedIdx)
  else:
    dict.properties["__size"] = NodeValue(kind: vkInt, intVal: oneBasedIdx)
  return args[1]

proc arrayAddImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Add element to end of array
  if args.len < 1:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)
  if not dict.properties.hasKey("__size"):
    dict.properties["__size"] = NodeValue(kind: vkInt, intVal: 0)

  let size = dict.properties["__size"].intVal
  dict.properties[$size] = args[0]
  dict.properties["__size"] = NodeValue(kind: vkInt, intVal: size + 1)
  return args[0]

proc arrayRemoveAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Remove element at index and return it (1-based indexing for Smalltalk compatibility)
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)
  if not dict.properties.hasKey("__size"):
    return nilValue()

  # Convert from 1-based (Smalltalk) to 0-based (internal storage)
  let idx = args[0].intVal - 1
  let size = dict.properties["__size"].intVal
  if idx < 0 or idx >= size:
    return nilValue()

  # Get element to return (using 0-based internal key)
  let removedElement = dict.properties.getOrDefault($idx)

  # Shift all elements after idx down by one
  for i in idx..<size-1:
    dict.properties[$i] = dict.properties.getOrDefault($(i+1))

  # Remove last element
  dict.properties.del($(size-1))
  dict.properties["__size"] = NodeValue(kind: vkInt, intVal: size - 1)
  return removedElement

proc valuesEqual(v1, v2: NodeValue): bool =
  ## Compare two NodeValues for equality (for basic types only)
  if v1.kind != v2.kind:
    return false
  case v1.kind
  of vkInt: return v1.intVal == v2.intVal
  of vkFloat: return v1.floatVal == v2.floatVal
  of vkString: return v1.strVal == v2.strVal
  of vkSymbol: return v1.symVal == v2.symVal
  of vkBool: return v1.boolVal == v2.boolVal
  of vkNil: return true
  of vkObject: return v1.objVal == v2.objVal
  of vkBlock: return v1.blockVal == v2.blockVal
  else: return false  # Arrays and tables - identity comparison only

proc arrayIncludesImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Check if array includes element (using = comparison)
  if args.len < 1:
    return falseValue
  if not (self of DictionaryObj):
    return falseValue

  let dict = cast[DictionaryObj](self)
  if not dict.properties.hasKey("__size"):
    return falseValue

  let size = dict.properties["__size"].intVal
  let element = args[0]

  for i in 0..<size:
    let elem = dict.properties.getOrDefault($i)
    # Use custom equality check
    if valuesEqual(elem, element):
      return trueValue

  return falseValue

proc arrayReverseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return new array with elements reversed
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)
  if not dict.properties.hasKey("__size"):
    return nilValue()

  let size = dict.properties["__size"].intVal

  # Create new reversed array
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[rootObject.RuntimeObject]
  obj.tags = @["Array", "Collection"]
  obj.isNimProxy = true
  obj.nimType = "array"
  obj.properties = initTable[string, NodeValue]()
  obj.properties["__size"] = NodeValue(kind: vkInt, intVal: size)

  for i in 0..<size:
    obj.properties[$i] = dict.properties.getOrDefault($(size - 1 - i))

  return NodeValue(kind: vkObject, objVal: obj.RuntimeObject)

proc tableNewImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Create new empty table: Table new
  let obj = DictionaryObj()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[rootObject.RuntimeObject]
  obj.tags = @["Table", "Collection", "Dictionary"]
  obj.isNimProxy = true
  obj.nimType = "table"
  obj.properties = initTable[string, NodeValue]()
  # Table uses native Table[string, NodeValue] in properties
  return NodeValue(kind: vkObject, objVal: obj.RuntimeObject)

proc tableKeysImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return array of all keys in table
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)

  # Create array proxy to hold keys
  let arr = DictionaryObj()
  arr.methods = initTable[string, BlockNode]()
  arr.parents = @[rootObject.RuntimeObject]
  arr.tags = @["Array", "Collection"]
  arr.isNimProxy = true
  arr.nimType = "array"
  arr.properties = initTable[string, NodeValue]()

  var idx = 0
  for key, val in dict.properties:
    if key != "__size":  # Skip internal properties
      arr.properties[$idx] = NodeValue(kind: vkString, strVal: key)
      idx += 1

  arr.properties["__size"] = NodeValue(kind: vkInt, intVal: idx)
  return NodeValue(kind: vkObject, objVal: arr.RuntimeObject)

proc tableIncludesKeyImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Check if table includes key
  if args.len < 1:
    return falseValue
  if not (self of DictionaryObj):
    return falseValue

  let dict = cast[DictionaryObj](self)
  var keyStr: string
  if args[0].kind == vkString:
    keyStr = args[0].strVal
  elif args[0].kind == vkSymbol:
    keyStr = args[0].symVal
  else:
    return falseValue

  return toValue(dict.properties.hasKey(keyStr))

proc tableRemoveKeyImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Remove key from table and return value (or nil)
  if args.len < 1:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)
  var keyStr: string
  if args[0].kind == vkString:
    keyStr = args[0].strVal
  elif args[0].kind == vkSymbol:
    keyStr = args[0].symVal
  else:
    return nilValue()

  if dict.properties.hasKey(keyStr):
    let removedValue = dict.properties[keyStr]
    dict.properties.del(keyStr)
    return removedValue
  return nilValue()

proc tableAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Get value at key: table at: 'key'
  if args.len < 1:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)
  var keyStr: string
  if args[0].kind == vkString:
    keyStr = args[0].strVal
  elif args[0].kind == vkSymbol:
    keyStr = args[0].symVal
  else:
    return nilValue()

  if dict.properties.hasKey(keyStr):
    return dict.properties[keyStr]
  return nilValue()

proc tableAtPutImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Set value at key: table at: 'key' put: value
  if args.len < 2:
    return nilValue()
  if not (self of DictionaryObj):
    return nilValue()

  let dict = cast[DictionaryObj](self)
  var keyStr: string
  if args[0].kind == vkString:
    keyStr = args[0].strVal
  elif args[0].kind == vkSymbol:
    keyStr = args[0].symVal
  else:
    return nilValue()

  dict.properties[keyStr] = args[1]
  return args[1]

# ============================================================================
# String primitives
# ============================================================================

proc getStringValue(obj: RuntimeObject): string =
  ## Helper to extract string value from string proxy
  if obj.isNimProxy and obj.nimType == "string":
    if obj of DictionaryObj:
      let dict = cast[DictionaryObj](obj)
      if dict.properties.hasKey("__value"):
        let val = dict.properties["__value"]
        if val.kind == vkString:
          return val.strVal
  return ""

proc stringConcatImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Concatenate strings: self , other
  if args.len < 1:
    return nilValue()
  let selfStr = getStringValue(self)
  var otherStr: string
  if args[0].kind == vkString:
    otherStr = args[0].strVal
  elif args[0].kind == vkObject:
    otherStr = getStringValue(args[0].objVal)
  else:
    return nilValue()
  return NodeValue(kind: vkString, strVal: selfStr & otherStr)

proc stringSizeImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return string length
  let selfStr = getStringValue(self)
  return NodeValue(kind: vkInt, intVal: selfStr.len)

proc stringAtImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return character at index (1-based like Smalltalk)
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()
  let selfStr = getStringValue(self)
  let idx = args[0].intVal - 1  # Convert to 0-based
  if idx < 0 or idx >= selfStr.len:
    return nilValue()
  return NodeValue(kind: vkString, strVal: $selfStr[idx])

proc stringFromToImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return substring from start to end (1-based like Smalltalk)
  if args.len < 2 or args[0].kind != vkInt or args[1].kind != vkInt:
    return nilValue()
  let selfStr = getStringValue(self)
  let startIdx = args[0].intVal - 1  # Convert to 0-based
  let endIdx = args[1].intVal  # End is inclusive in Smalltalk, exclusive in Nim
  if startIdx < 0 or endIdx > selfStr.len or startIdx >= endIdx:
    return nilValue()
  return NodeValue(kind: vkString, strVal: selfStr[startIdx..<endIdx])

proc stringIndexOfImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return index of substring (1-based, 0 if not found)
  if args.len < 1:
    return NodeValue(kind: vkInt, intVal: 0)
  let selfStr = getStringValue(self)
  var searchStr: string
  if args[0].kind == vkString:
    searchStr = args[0].strVal
  elif args[0].kind == vkObject:
    searchStr = getStringValue(args[0].objVal)
  else:
    return NodeValue(kind: vkInt, intVal: 0)
  let idx = selfStr.find(searchStr)
  if idx < 0:
    return NodeValue(kind: vkInt, intVal: 0)
  return NodeValue(kind: vkInt, intVal: idx + 1)  # 1-based

proc stringIncludesSubStringImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Check if string includes substring
  if args.len < 1:
    return falseValue
  let selfStr = getStringValue(self)
  var searchStr: string
  if args[0].kind == vkString:
    searchStr = args[0].strVal
  elif args[0].kind == vkObject:
    searchStr = getStringValue(args[0].objVal)
  else:
    return falseValue
  return toValue(selfStr.contains(searchStr))

proc stringReplaceWithImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Replace all occurrences of old with new
  if args.len < 2:
    return nilValue()
  let selfStr = getStringValue(self)
  var oldStr, newStr: string
  if args[0].kind == vkString: oldStr = args[0].strVal
  elif args[0].kind == vkObject: oldStr = getStringValue(args[0].objVal)
  else: return nilValue()
  if args[1].kind == vkString: newStr = args[1].strVal
  elif args[1].kind == vkObject: newStr = getStringValue(args[1].objVal)
  else: return nilValue()
  return NodeValue(kind: vkString, strVal: selfStr.replace(oldStr, newStr))

proc stringUppercaseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return uppercase version
  let selfStr = getStringValue(self)
  return NodeValue(kind: vkString, strVal: selfStr.toUpperAscii())

proc stringLowercaseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Return lowercase version
  let selfStr = getStringValue(self)
  return NodeValue(kind: vkString, strVal: selfStr.toLowerAscii())

proc stringTrimImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Remove leading and trailing whitespace
  let selfStr = getStringValue(self)
  return NodeValue(kind: vkString, strVal: selfStr.strip())

proc stringSplitImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Split string by delimiter, return array
  if args.len < 1:
    return nilValue()
  let selfStr = getStringValue(self)
  var delim: string
  if args[0].kind == vkString: delim = args[0].strVal
  elif args[0].kind == vkObject: delim = getStringValue(args[0].objVal)
  else: delim = " "

  # Create array proxy to hold results
  let arr = DictionaryObj()
  arr.methods = initTable[string, BlockNode]()
  arr.parents = @[rootObject.RuntimeObject]
  arr.tags = @["Array", "Collection"]
  arr.isNimProxy = true
  arr.nimType = "array"
  arr.properties = initTable[string, NodeValue]()

  let parts = selfStr.split(delim)
  for i, part in parts:
    arr.properties[$i] = NodeValue(kind: vkString, strVal: part)

  arr.properties["__size"] = NodeValue(kind: vkInt, intVal: parts.len)
  return NodeValue(kind: vkObject, objVal: arr.RuntimeObject)

proc wrapIntAsObject*(value: int): NodeValue =
  ## Wrap an integer as a Nim proxy object that can receive messages
  let obj = RuntimeObject()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[rootObject.RuntimeObject]
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
  ## Uses True/False class caches if available for proper method inheritance
  let obj = RuntimeObject()
  obj.methods = initTable[string, BlockNode]()
  # Use True/False class caches if available
  if value and trueClassCache != nil:
    obj.parents = @[trueClassCache]
  elif not value and falseClassCache != nil:
    obj.parents = @[falseClassCache]
  else:
    obj.parents = @[rootObject.RuntimeObject]
  obj.tags = if value: @["Boolean", "True"] else: @["Boolean", "False"]
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](alloc(sizeof(bool)))
  cast[ptr bool](obj.nimValue)[] = value
  obj.nimType = "bool"
  obj.hasSlots = false
  obj.slots = @[]
  obj.slotNames = initTable[string, int]()
  return NodeValue(kind: vkObject, objVal: obj)

proc newObject*(): RuntimeObject =
  ## Create a new lightweight object (no property bag)
  let obj = RuntimeObject()
  obj.methods = initTable[string, BlockNode]()
  obj.parents = @[initRootObject().RuntimeObject]
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
  obj.parents = @[initRootObject().RuntimeObject]
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
proc isSame*(obj1, obj2: RuntimeObject): bool =
  ## Check if two objects are the same (identity)
  return obj1 == obj2

proc inheritsFrom*(obj: RuntimeObject, parent: RuntimeObject): bool =
  ## Check if object inherits from parent in class hierarchy
  if obj.isSame(parent):
    return true

  for p in obj.parents:
    if inheritsFrom(p, parent):
      return true

  return false

# Display helpers
proc printObject*(obj: RuntimeObject, indent: int = 0): string =
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
# proc makeTestObjects*(): (RootObject, RuntimeObject, RuntimeObject) =
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

# ============================================================================
# File I/O primitives
# ============================================================================

proc getFileStreamFile(obj: RuntimeObject): File =
  ## Helper to get File handle from FileStream object
  if obj of FileStreamObj:
    let fs = cast[FileStreamObj](obj)
    if fs.isOpen:
      result = fs.file
  # Return nil file if not valid

proc fileOpenImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Open a file: file open: filename mode: mode
  if args.len < 2:
    return nilValue()

  var filename, mode: string
  if args[0].kind == vkString:
    filename = args[0].strVal
  else:
    return nilValue()

  if args[1].kind == vkString:
    mode = args[1].strVal
  else:
    return nilValue()

  # Convert mode to FileMode
  var fileMode: FileMode
  case mode
  of "r": fileMode = fmRead
  of "w": fileMode = fmWrite
  of "a": fileMode = fmAppend
  of "r+": fileMode = fmReadWrite
  of "w+": fileMode = fmReadWriteExisting
  else: return nilValue()

  # Check if self is a FileStreamObj
  if not (self of FileStreamObj):
    return nilValue()

  let fs = cast[FileStreamObj](self)

  # Open the file
  var f: File
  if open(f, filename, fileMode):
    fs.file = f
    fs.mode = mode
    fs.isOpen = true
    return self.toValue()
  return nilValue()

proc fileCloseImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Close a file: file close
  if not (self of FileStreamObj):
    return nilValue()

  let fs = cast[FileStreamObj](self)
  if fs.isOpen:
    fs.file.close()
    fs.isOpen = false
  return nilValue()

proc fileReadLineImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Read one line from file: file readLine
  if not (self of FileStreamObj):
    return nilValue()

  let fs = cast[FileStreamObj](self)
  if not fs.isOpen:
    return nilValue()

  if fs.file.endOfFile():
    return nilValue()

  let line = fs.file.readLine()
  return NodeValue(kind: vkString, strVal: line)

proc fileWriteImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Write string to file: file write: string
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not (self of FileStreamObj):
    return nilValue()

  let fs = cast[FileStreamObj](self)
  if not fs.isOpen:
    return nilValue()

  fs.file.write(args[0].strVal)
  return args[0]

proc fileAtEndImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Check if at end of file: file atEnd
  if not (self of FileStreamObj):
    return trueValue

  let fs = cast[FileStreamObj](self)
  if not fs.isOpen:
    return trueValue

  return toValue(fs.file.endOfFile())

proc fileReadAllImpl*(self: RuntimeObject, args: seq[NodeValue]): NodeValue =
  ## Read entire file contents: file readAll
  if not (self of FileStreamObj):
    return nilValue()

  let fs = cast[FileStreamObj](self)
  if not fs.isOpen:
    return nilValue()

  let content = fs.file.readAll()
  return NodeValue(kind: vkString, strVal: content)

# ============================================================================
# Class-Based Object System Implementation
# ============================================================================

proc mergeTables*(target: var Table[string, BlockNode], source: Table[string, BlockNode]) =
  ## Merge source table into target (source values override target)
  for key, value in source:
    target[key] = value

proc rebuildAllTables*(cls: Class) =
  ## Rebuild allMethods, allClassMethods, and allSlotNames from parents
  # Start with empty tables
  cls.allMethods = initTable[string, BlockNode]()
  cls.allClassMethods = initTable[string, BlockNode]()
  cls.allSlotNames = @[]

  # Merge from all parents using left-to-right priority (first parent wins)
  for parent in cls.parents:
    # Merge methods (only add if not already present from earlier parent)
    for selector, meth in parent.allMethods:
      if selector notin cls.allMethods:
        cls.allMethods[selector] = meth
    # Merge class methods
    for selector, meth in parent.allClassMethods:
      if selector notin cls.allClassMethods:
        cls.allClassMethods[selector] = meth
    # Merge slot names (avoid duplicates)
    for slot in parent.allSlotNames:
      if slot notin cls.allSlotNames:
        cls.allSlotNames.add(slot)

  # Add own methods (override inherited)
  for selector, meth in cls.methods:
    cls.allMethods[selector] = meth
  for selector, meth in cls.classMethods:
    cls.allClassMethods[selector] = meth

  # Add own slot names (error on conflict)
  for slot in cls.slotNames:
    if slot in cls.allSlotNames:
      raise newException(ValueError, "Slot name conflict: '" & slot & "' already defined in parent")
    cls.allSlotNames.add(slot)

  # Update hasSlots flag
  cls.hasSlots = cls.allSlotNames.len > 0

proc invalidateSubclasses*(cls: Class) =
  ## Eagerly invalidate and rebuild all subclasses recursively
  for sub in cls.subclasses:
    rebuildAllTables(sub)
    invalidateSubclasses(sub)

proc addMethodToClass*(cls: Class, selector: string, methodBlock: BlockNode, isClassMethod: bool = false) =
  ## Add a method to a class and trigger eager invalidation
  if isClassMethod:
    # Add to class methods
    cls.classMethods[selector] = methodBlock
    cls.allClassMethods[selector] = methodBlock
  else:
    # Add to instance methods
    cls.methods[selector] = methodBlock
    cls.allMethods[selector] = methodBlock

  # Eagerly invalidate all subclasses
  invalidateSubclasses(cls)

proc classDeriveImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a subclass: Class derive: #(slotNames)
  var newSlotNames: seq[string] = @[]

  # Extract slot names from argument
  if args.len >= 1:
    if args[0].kind == vkArray:
      for val in args[0].arrayVal:
        if val.kind == vkSymbol:
          newSlotNames.add(val.symVal)
        elif val.kind == vkString:
          newSlotNames.add(val.strVal)
    elif args[0].kind == vkSymbol:
      newSlotNames.add(args[0].symVal)

  # Create new class with self as parent
  let newClass = newClass(parents = @[self], slotNames = newSlotNames)

  # Copy parent's merged methods (shallow copy - BlockNodes are immutable)
  newClass.allMethods = self.allMethods
  newClass.allClassMethods = self.allClassMethods
  newClass.allSlotNames = self.allSlotNames

  # Start with empty own methods
  newClass.methods = initTable[string, BlockNode]()
  newClass.classMethods = initTable[string, BlockNode]()

  # Build slot layout (add own slots to parent's)
  for slot in newSlotNames:
    if slot in newClass.allSlotNames:
      raise newException(ValueError, "Slot name conflict: '" & slot & "' already defined in parent")
    newClass.allSlotNames.add(slot)

  # Update hasSlots flag
  newClass.hasSlots = newClass.allSlotNames.len > 0

  # Generate accessor methods for each new slot
  for slot in newSlotNames:
    # Create getter: slotName -> slots[index]
    let getterIndex = newClass.allSlotNames.len - newSlotNames.len + newSlotNames.find(slot)
    var getterBody: seq[Node] = @[]
    getterBody.add(SlotAccessNode(
      slotName: slot,
      slotIndex: getterIndex,
      isAssignment: false
    ))
    let getter = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: getterBody,
      isMethod: true
    )
    newClass.methods[slot] = getter
    newClass.allMethods[slot] = getter

    # Create setter: slotName: value -> slots[index] := value
    var setterBody: seq[Node] = @[]
    setterBody.add(SlotAccessNode(
      slotName: slot & ":",
      slotIndex: getterIndex,
      isAssignment: true
    ))
    let setter = BlockNode(
      parameters: @["newValue"],
      temporaries: @[],
      body: setterBody,
      isMethod: true
    )
    newClass.methods[slot & ":"] = setter
    newClass.allMethods[slot & ":"] = setter

  # Register as subclass with parent for efficient invalidation
  self.subclasses.add(newClass)

  # Return as vkClass value (no proxy needed)
  return NodeValue(kind: vkClass, classVal: newClass)

proc classNewImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a new instance: Class new
  let inst = newInstance(self)

  # Return as vkInstance value (no proxy needed)
  return NodeValue(kind: vkInstance, instVal: inst)

proc classAddMethodImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Add instance method: Class selector: 'sel' put: [block]
  if args.len < 2:
    return nilValue()

  var selector: string
  if args[0].kind == vkSymbol:
    selector = args[0].symVal
  elif args[0].kind == vkString:
    selector = args[0].strVal
  else:
    return nilValue()

  if args[1].kind != vkBlock:
    return nilValue()

  let blockNode = args[1].blockVal
  blockNode.isMethod = true

  # Add to own methods
  self.methods[selector] = blockNode

  # Update allMethods
  self.allMethods[selector] = blockNode

  # Invalidate subclasses
  invalidateSubclasses(self)

  return args[1]

proc classAddClassMethodImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Add class method: Class classSelector: 'sel' put: [block]
  if args.len < 2:
    return nilValue()

  var selector: string
  if args[0].kind == vkSymbol:
    selector = args[0].symVal
  elif args[0].kind == vkString:
    selector = args[0].strVal
  else:
    return nilValue()

  if args[1].kind != vkBlock:
    return nilValue()

  let blockNode = args[1].blockVal
  blockNode.isMethod = true

  # Add to own class methods
  self.classMethods[selector] = blockNode

  # Update allClassMethods
  self.allClassMethods[selector] = blockNode

  # Invalidate subclasses
  invalidateSubclasses(self)

  return args[1]

proc initRootClass*(): Class =
  ## Initialize the global root class
  if rootClass == nil:
    rootClass = newClass()
    rootClass.tags = @["Object", "Class", "Root"]
    rootClass.name = "Object"

  return rootClass
