## ============================================================================
## BitBarrel BarrelTable
## Native implementation for BarrelTable class - hash-based persistent table
## ============================================================================

when defined(bitbarrel):
  import std/[tables, strutils]
  import ../core/types
  import ../interpreter/objects
  import ../interpreter/vm
  import ./client/client

  ## Forward declarations
  proc initBarrelTableClass*(interp: var Interpreter)
  proc barrelTableNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}

  ## Native method implementations

  proc barrelTableAtImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Get value at key: at: key
    if args.len < 1:
      return nilValue()

    let key = args[0].toString()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let value = client[].get(key)
        return value.toValue()
      except:
        return nilValue()

    nilValue()

  proc barrelTableAtPutImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Set value at key: at:put: key value
    if args.len < 2:
      return self.toValue()

    let key = args[0].toString()
    let value = args[1].toString()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        discard client[].set(key, value)
      except:
        discard

    self.toValue()

  proc barrelTableIncludesKeyImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Check if key exists: includesKey: key
    if args.len < 1:
      return falseValue()

    let key = args[0].toString()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let exists = client[].exists(key)
        return if exists: trueValue() else: falseValue()
      except:
        return falseValue()

    falseValue()

  proc barrelTableRemoveKeyImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Remove key: removeKey: key
    if args.len < 1:
      return nilValue()

    let key = args[0].toString()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        discard client[].delete(key)
      except:
        discard

    nilValue()

  proc barrelTableKeysImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Get all keys as Array
    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let keys = client[].listKeys()
        # Convert to Harding Array
        let arrClass = getArrayClass(interp)
        var result = newInstance(arrClass)
        for key in keys:
          result.elements.add(key.toValue())
        return result.toValue()
      except:
        discard

    nilValue()

  proc barrelTableSizeImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Get number of entries
    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let count = client[].count()
        return count.toValue()
      except:
        discard

    0.toValue()

  ## Implementation of new method
  proc barrelTableNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Create new BarrelTable instance
    # Look up BarrelTable class from globals
    var cls: Class = nil
    if "BarrelTable" in interp.globals[]:
      let val = interp.globals[]["BarrelTable"]
      if val.kind == vkClass:
        cls = val.classVal
    if cls == nil:
      cls = objectClass

    let obj = newInstance(cls)
    obj.isNimProxy = true

    # Create a shared BitBarrel client instance
    # The actual connection will be set up via connect: method
    result = obj.toValue()

  ## Initialize BarrelTable class
  proc initBarrelTableClass*(interp: var Interpreter) =
    ## Initialize and register the BarrelTable class

    # Get Object class as superclass
    var objectCls: Class = nil
    if "Object" in interp.globals[]:
      let val = interp.globals[]["Object"]
      if val.kind == vkClass:
        objectCls = val.classVal

    if objectCls == nil:
      warn("Object class not found, cannot create BarrelTable class")
      return

    # Create BarrelTable class
    let tableCls = newClass(superclasses = @[objectCls], name = "BarrelTable")
    tableCls.tags = @["BitBarrel", "Table", "Persistent", "Hash"]
    tableCls.isNimProxy = true
    tableCls.hardingType = "BarrelTable"

    # Add class methods
    let newMethod = createCoreMethod("new")
    newMethod.nativeImpl = cast[pointer](barrelTableNewImpl)
    newMethod.hasInterpreterParam = true
    addMethodToClass(tableCls, "new", newMethod, isClassMethod = true)

    # Add instance methods
    let atMethod = createCoreMethod("at:")
    atMethod.nativeImpl = cast[pointer](barrelTableAtImpl)
    atMethod.hasInterpreterParam = true
    addMethodToClass(tableCls, "at:", atMethod)

    let atPutMethod = createCoreMethod("at:put:")
    atPutMethod.nativeImpl = cast[pointer](barrelTableAtPutImpl)
    atPutMethod.hasInterpreterParam = true
    addMethodToClass(tableCls, "at:put:", atPutMethod)

    let includesKeyMethod = createCoreMethod("includesKey:")
    includesKeyMethod.nativeImpl = cast[pointer](barrelTableIncludesKeyImpl)
    includesKeyMethod.hasInterpreterParam = true
    addMethodToClass(tableCls, "includesKey:", includesKeyMethod)

    let removeKeyMethod = createCoreMethod("removeKey:")
    removeKeyMethod.nativeImpl = cast[pointer](barrelTableRemoveKeyImpl)
    removeKeyMethod.hasInterpreterParam = true
    addMethodToClass(tableCls, "removeKey:", removeKeyMethod)

    let keysMethod = createCoreMethod("keys")
    keysMethod.nativeImpl = cast[pointer](barrelTableKeysImpl)
    keysMethod.hasInterpreterParam = true
    addMethodToClass(tableCls, "keys", keysMethod)

    let sizeMethod = createCoreMethod("size")
    sizeMethod.nativeImpl = cast[pointer](barrelTableSizeImpl)
    sizeMethod.hasInterpreterParam = true
    addMethodToClass(tableCls, "size", sizeMethod)

    # Register in globals
    interp.globals[]["BarrelTable"] = tableCls.toValue()
    debug("Registered BarrelTable class")

else:
  # Stub implementation when BitBarrel is not enabled
  import ../core/types
  import ../interpreter/objects

  proc initBarrelTableClass*(interp: var Interpreter) =
    ## Stub - BitBarrel support not compiled in
    debug("BarrelTable class not available (compile with -d:bitbarrel)")
