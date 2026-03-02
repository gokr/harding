## ============================================================================
## BitBarrel Barrel Management
## Native implementation for Barrel class - manages connection to BitBarrel server
## ============================================================================

when defined(bitbarrel):
  import std/[tables, strutils, net]
  import ../core/types
  import ../interpreter/objects
  import ../interpreter/vm
  import ./client/client

  ## Native method implementations

  proc barrelConnectImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Connect to BitBarrel server: host:port
    if args.len < 1:
      return nilValue()

    let host = args[0].toString()
    var port = 9876.Port

    # Parse host:port format
    var actualHost = host
    if ":" in host:
      let parts = host.split(":")
      actualHost = parts[0]
      try:
        port = parseInt(parts[1]).Port
      except:
        port = 9876.Port

    # Create and connect client
    var client = newClient(actualHost, port)
    try:
      client.connect()
      if self.isNimProxy:
        # Store the client pointer in nimValue
        # We need to allocate on heap for stable pointer
        var clientPtr = create(BitBarrelClient)
        clientPtr[] = client
        self.nimValue = cast[pointer](clientPtr)
        return self.toValue()
    except:
      warn("Failed to connect to BitBarrel server at ", host)
      return nilValue()

    nilValue()

  proc barrelCreateImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Create a barrel: name mode:
    if args.len < 2:
      return falseValue()

    let name = args[0].toString()
    let modeStr = args[1].toString()

    let mode = if modeStr == "critbit": bmCritBit else: bmHash

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let success = client[].createBarrel(name, mode)
        return if success: trueValue() else: falseValue()
      except:
        return falseValue()

    falseValue()

  proc barrelUseImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Select a barrel for operations
    if args.len < 1:
      return falseValue()

    let name = args[0].toString()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let success = client[].useBarrel(name)
        return if success: trueValue() else: falseValue()
      except:
        return falseValue()

    falseValue()

  proc barrelCloseImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Close connection to BitBarrel server
    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        client[].close()
        return trueValue()
      except:
        discard

    nilValue()

  proc barrelListBarrelsImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## List all barrels on the server
    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let barrels = client[].listBarrels()
        # Convert to Harding Array
        let arrClass = getArrayClass(interp)
        var result = newInstance(arrClass)
        for barrel in barrels:
          result.elements.add(barrel.toValue())
        return result.toValue()
      except:
        discard

    nilValue()

  ## Initialize Barrel class
  proc initBarrelClass*(interp: var Interpreter) =
    ## Initialize and register the Barrel class

    # Get Object class as superclass
    var objectCls: Class = nil
    if "Object" in interp.globals[]:
      let val = interp.globals[]["Object"]
      if val.kind == vkClass:
        objectCls = val.classVal

    if objectCls == nil:
      warn("Object class not found, cannot create Barrel class")
      return

    # Create Barrel class
    let barrelCls = newClass(superclasses = @[objectCls], name = "Barrel")
    barrelCls.tags = @["BitBarrel", "Database", "Persistent"]
    barrelCls.isNimProxy = true
    barrelCls.hardingType = "Barrel"

    # Add class methods
    let newMethod = createCoreMethod("new")
    newMethod.nativeImpl = cast[pointer](barrelConnectImpl)
    newMethod.hasInterpreterParam = true
    addMethodToClass(barrelCls, "new", newMethod, isClassMethod = true)

    let openMethod = createCoreMethod("open:")
    openMethod.nativeImpl = cast[pointer](barrelConnectImpl)
    openMethod.hasInterpreterParam = true
    addMethodToClass(barrelCls, "open:", openMethod, isClassMethod = true)

    # Add instance methods
    let createMethod = createCoreMethod("create:mode:")
    createMethod.nativeImpl = cast[pointer](barrelCreateImpl)
    createMethod.hasInterpreterParam = true
    addMethodToClass(barrelCls, "create:mode:", createMethod)

    let useMethod = createCoreMethod("use:")
    useMethod.nativeImpl = cast[pointer](barrelUseImpl)
    useMethod.hasInterpreterParam = true
    addMethodToClass(barrelCls, "use:", useMethod)

    let closeMethod = createCoreMethod("close")
    closeMethod.nativeImpl = cast[pointer](barrelCloseImpl)
    closeMethod.hasInterpreterParam = true
    addMethodToClass(barrelCls, "close", closeMethod)

    let listBarrelsMethod = createCoreMethod("listBarrels")
    listBarrelsMethod.nativeImpl = cast[pointer](barrelListBarrelsImpl)
    listBarrelsMethod.hasInterpreterParam = true
    addMethodToClass(barrelCls, "listBarrels", listBarrelsMethod)

    # Register in globals
    interp.globals[]["Barrel"] = barrelCls.toValue()
    debug("Registered Barrel class")

else:
  # Stub implementation when BitBarrel is not enabled
  import ../core/types
  import ../interpreter/objects

  proc initBarrelClass*(interp: var Interpreter) =
    ## Stub - BitBarrel support not compiled in
    debug("Barrel class not available (compile with -d:bitbarrel)")
