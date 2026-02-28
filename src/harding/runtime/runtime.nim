import std/[tables, strformat, os, logging]
import ../core/types
import ../core/scheduler
import ../interpreter/vm

# ============================================================================
# Harding Runtime
# Runtime support for compiled Harding code
# ============================================================================

type
  Runtime* = ref object
    rootObject*: Instance
    classes*: Table[string, Instance]
    methodCache*: Table[string, CompiledMethod]
    isInitializing*: bool

  CompiledMethod* = ref object
    selector*: string
    arity*: int
    nativeAddr*: pointer
    symbolName*: string

var currentRuntime*: ptr Runtime = nil

proc newRuntime*(): Runtime =
  ## Create new runtime instance
  result = Runtime(
    rootObject: nil,
    classes: initTable[string, Instance](),
    methodCache: initTable[string, CompiledMethod](),
    isInitializing: false
  )

proc initRuntime*() =
  ## Initialize global runtime
  if currentRuntime == nil:
    currentRuntime = cast[ptr Runtime](allocShared(sizeof(Runtime)))
    currentRuntime[] = newRuntime()

proc shutdownRuntime*() =
  ## Shutdown and cleanup runtime
  if currentRuntime != nil:
    # Clean up classes
    currentRuntime.classes.clear()
    currentRuntime.methodCache.clear()
    deallocShared(cast[pointer](currentRuntime))
    currentRuntime = nil

proc registerClass*(runtime: var Runtime, name: string, cls: Instance) =
  ## Register a class in the runtime
  runtime.classes[name] = cls

proc getClass*(runtime: Runtime, name: string): Instance =
  ## Get a registered class by name
  if name in runtime.classes:
    return runtime.classes[name]
  return nil

proc registerMethod*(runtime: var Runtime, selector: string,
                     nativeAddr: pointer, arity: int = 0,
                     symbolName: string = ""): void =
  ## Register a compiled method
  let meth = CompiledMethod(
    selector: selector,
    arity: arity,
    nativeAddr: nativeAddr,
    symbolName: if symbolName.len > 0: symbolName else: selector
  )
  runtime.methodCache[selector] = meth

var compiledMethodProcs*: Table[string, proc(self: NodeValue, args: seq[NodeValue]): NodeValue] =
  initTable[string, proc(self: NodeValue, args: seq[NodeValue]): NodeValue]()
var nimProxyClassNames*: Table[pointer, string] = initTable[pointer, string]()

proc registerCompiledMethod*(className: string, selector: string,
                              fn: proc(self: NodeValue, args: seq[NodeValue]): NodeValue) =
  let key = className & ">>" & selector
  compiledMethodProcs[key] = fn

proc registerNimProxyClassName*(nimValue: pointer, className: string) =
  ## Register the class name for a Nim proxy object
  nimProxyClassNames[nimValue] = className

proc getNimProxyClassName*(nimValue: pointer): string =
  ## Get the class name for a Nim proxy object
  if nimValue in nimProxyClassNames:
    return nimProxyClassNames[nimValue]
  return ""

var superclassNames*: Table[string, string] = initTable[string, string]()

proc registerSuperclass*(className: string, superclassName: string) =
  ## Register the superclass for a class
  superclassNames[className] = superclassName

proc getSuperclassName*(className: string): string =
  ## Get the superclass name for a class
  if className in superclassNames:
    return superclassNames[className]
  return ""

proc findCompiledMethod*(className: string, selector: string): proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## Look up a compiled method by class name and selector
  let key = className & ">>" & selector
  if key in compiledMethodProcs:
    return compiledMethodProcs[key]
  return nil

proc getReceiverClassName*(receiver: NodeValue): string =
  ## Resolve runtime class name for compiled Nim proxy instances
  if receiver.kind != vkInstance or receiver.instVal == nil or not receiver.instVal.isNimProxy:
    return ""

  if receiver.instVal.class != nil:
    return receiver.instVal.class.name

  if receiver.instVal.nimValue != nil:
    return getNimProxyClassName(receiver.instVal.nimValue)

  return ""

proc dispatchCompiledMethodFromClass*(receiver: NodeValue, className: string,
                                      selector: string, args: seq[NodeValue]): NodeValue =
  ## Dispatch compiled method by walking class -> superclasses chain
  var currentClass = className
  while currentClass.len > 0:
    let compiledFn = findCompiledMethod(currentClass, selector)
    if compiledFn != nil:
      return compiledFn(receiver, args)
    currentClass = getSuperclassName(currentClass)
  return NodeValue(kind: vkNil)

proc sendSuperMessage*(receiver: NodeValue, definingClassName: string,
                       selector: string, args: seq[NodeValue],
                       explicitParent: string = ""): NodeValue =
  ## Send message starting lookup from superclass of defining class
  ## Used for compiled nkSuperSend expressions
  discard args
  var startClass = explicitParent
  if startClass.len == 0:
    startClass = getSuperclassName(definingClassName)
  if startClass.len == 0:
    return NodeValue(kind: vkNil)
  return dispatchCompiledMethodFromClass(receiver, startClass, selector, args)

proc evalBlock*(runtime: Runtime, blk: BlockNode,
                args: seq[NodeValue] = @[]): NodeValue =
  ## Evaluate a block (placeholder - needs full evaluator integration)
  discard
  return NodeValue(kind: vkNil)

type
  BlockProc0* = proc(): NodeValue {.cdecl.}
  BlockProc1* = proc(a: NodeValue): NodeValue {.cdecl.}
  BlockProc2* = proc(a, b: NodeValue): NodeValue {.cdecl.}
  BlockProc3* = proc(a, b, c: NodeValue): NodeValue {.cdecl.}
  BlockEnvProc0* = proc(env: pointer): NodeValue {.cdecl.}
  BlockEnvProc1* = proc(env: pointer, a: NodeValue): NodeValue {.cdecl.}
  BlockEnvProc2* = proc(env: pointer, a, b: NodeValue): NodeValue {.cdecl.}
  BlockEnvProc3* = proc(env: pointer, a, b, c: NodeValue): NodeValue {.cdecl.}

proc getBlockEnvPtr*(blk: BlockNode): pointer =
  ## Retrieve the environment pointer from a block
  if blk.capturedEnvInitialized and "__env_ptr__" in blk.capturedEnv:
    return cast[pointer](blk.capturedEnv["__env_ptr__"].value.intVal)
  return nil

proc sendMessage*(runtime: Runtime, receiver: NodeValue,
                  selector: string, args: seq[NodeValue]): NodeValue =
  ## Send a message to a receiver (dynamic dispatch)
  ## This is the slow path fallback for compiled code

  # Block evaluation: value, value:, value:value:, value:value:value:
  if receiver.kind == vkBlock and receiver.blockVal != nil and
     receiver.blockVal.nativeImpl != nil:
    let envPtr = getBlockEnvPtr(receiver.blockVal)
    let hasEnv = envPtr != nil
    case selector
    of "value":
      if hasEnv:
        let fn = cast[BlockEnvProc0](receiver.blockVal.nativeImpl)
        return fn(envPtr)
      else:
        let fn = cast[BlockProc0](receiver.blockVal.nativeImpl)
        return fn()
    of "value:":
      if args.len >= 1:
        if hasEnv:
          let fn = cast[BlockEnvProc1](receiver.blockVal.nativeImpl)
          return fn(envPtr, args[0])
        else:
          let fn = cast[BlockProc1](receiver.blockVal.nativeImpl)
          return fn(args[0])
    of "value:value:":
      if args.len >= 2:
        if hasEnv:
          let fn = cast[BlockEnvProc2](receiver.blockVal.nativeImpl)
          return fn(envPtr, args[0], args[1])
        else:
          let fn = cast[BlockProc2](receiver.blockVal.nativeImpl)
          return fn(args[0], args[1])
    of "value:value:value:":
      if args.len >= 3:
        if hasEnv:
          let fn = cast[BlockEnvProc3](receiver.blockVal.nativeImpl)
          return fn(envPtr, args[0], args[1], args[2])
        else:
          let fn = cast[BlockProc3](receiver.blockVal.nativeImpl)
          return fn(args[0], args[1], args[2])
    else:
      discard

  case selector
  of "writeLine:", "writeline:", "println":
    if args.len > 0:
      echo args[0].toString()
    return receiver
  of "write:", "print":
    if args.len > 0:
      stdout.write(args[0].toString())
    return receiver
  of "toString", "asString":
    return NodeValue(kind: vkString, strVal: receiver.toString())
  of "printString":
    return NodeValue(kind: vkString, strVal: receiver.toString())
  of ",":
    if args.len > 0:
      let aStr = receiver.toString()
      let bStr = args[0].toString()
      return NodeValue(kind: vkString, strVal: aStr & bStr)
    return receiver
  of "+", "plus":
    if receiver.kind == vkInt and args.len > 0 and args[0].kind == vkInt:
      return NodeValue(kind: vkInt, intVal: receiver.intVal + args[0].intVal)
    return NodeValue(kind: vkNil)
  of "-", "minus":
    if receiver.kind == vkInt and args.len > 0 and args[0].kind == vkInt:
      return NodeValue(kind: vkInt, intVal: receiver.intVal - args[0].intVal)
    return NodeValue(kind: vkNil)
  of "*", "star":
    if receiver.kind == vkInt and args.len > 0 and args[0].kind == vkInt:
      return NodeValue(kind: vkInt, intVal: receiver.intVal * args[0].intVal)
    return NodeValue(kind: vkNil)
  of "/":
    if receiver.kind == vkInt and args.len > 0 and args[0].kind == vkInt:
      return NodeValue(kind: vkInt, intVal: receiver.intVal div args[0].intVal)
    return NodeValue(kind: vkNil)

  of "new":
    if receiver.kind == vkSymbol:
      case receiver.symVal
      of "Array":
        return NodeValue(kind: vkArray, arrayVal: @[])
      of "Table":
        return NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]())
      else:
        discard
    return NodeValue(kind: vkNil)

  of "add:":
    if receiver.kind == vkArray and args.len > 0:
      var arr = receiver.arrayVal
      arr.add(args[0])
      return NodeValue(kind: vkArray, arrayVal: arr)
    return NodeValue(kind: vkNil)

  of "at:":
    if args.len > 0:
      if receiver.kind == vkArray and args[0].kind == vkInt:
        let idx = args[0].intVal - 1
        if idx >= 0 and idx < receiver.arrayVal.len:
          return receiver.arrayVal[idx]
      elif receiver.kind == vkTable:
        if receiver.tableVal.hasKey(args[0]):
          return receiver.tableVal[args[0]]
    return NodeValue(kind: vkNil)

  of "at:put:":
    if args.len >= 2:
      if receiver.kind == vkArray and args[0].kind == vkInt:
        let idx = args[0].intVal - 1
        if idx >= 0:
          var arr = receiver.arrayVal
          if idx < arr.len:
            arr[idx] = args[1]
          elif idx == arr.len:
            arr.add(args[1])
          return NodeValue(kind: vkArray, arrayVal: arr)
      elif receiver.kind == vkTable:
        var tbl = receiver.tableVal
        tbl[args[0]] = args[1]
        return NodeValue(kind: vkTable, tableVal: tbl)
    return receiver

  of "size":
    if receiver.kind == vkArray:
      return NodeValue(kind: vkInt, intVal: receiver.arrayVal.len)
    if receiver.kind == vkTable:
      return NodeValue(kind: vkInt, intVal: receiver.tableVal.len)
    return NodeValue(kind: vkNil)

  of "last":
    if receiver.kind == vkArray and receiver.arrayVal.len > 0:
      return receiver.arrayVal[^1]
    return NodeValue(kind: vkNil)

  of "keys":
    if receiver.kind == vkTable:
      var keys: seq[NodeValue] = @[]
      for k in receiver.tableVal.keys:
        keys.add(k)
      return NodeValue(kind: vkArray, arrayVal: keys)
    return NodeValue(kind: vkNil)

  of "do:":
    if receiver.kind == vkArray and args.len > 0:
      for item in receiver.arrayVal:
        discard sendMessage(runtime, args[0], "value:", @[item])
      return receiver
    return NodeValue(kind: vkNil)

  of "inject:into:":
    if receiver.kind == vkArray and args.len >= 2:
      var acc = args[0]
      for item in receiver.arrayVal:
        acc = sendMessage(runtime, args[1], "value:value:", @[acc, item])
      return acc
    return NodeValue(kind: vkNil)

  of "to:do:":
    if receiver.kind == vkInt and args.len >= 2 and args[0].kind == vkInt:
      let startNum = receiver.intVal
      let endNum = args[0].intVal
      if startNum <= endNum:
        for i in startNum..endNum:
          discard sendMessage(runtime, args[1], "value:", @[NodeValue(kind: vkInt, intVal: i)])
      else:
        for i in countdown(startNum, endNum):
          discard sendMessage(runtime, args[1], "value:", @[NodeValue(kind: vkInt, intVal: i)])
      return receiver
    return NodeValue(kind: vkNil)

  of "ifTrue:":
    if args.len > 0 and isTruthy(receiver):
      return sendMessage(runtime, args[0], "value", @[])
    return NodeValue(kind: vkNil)

  of "ifFalse:":
    if args.len > 0 and not isTruthy(receiver):
      return sendMessage(runtime, args[0], "value", @[])
    return NodeValue(kind: vkNil)

  of "ifTrue:ifFalse:":
    if args.len >= 2:
      if isTruthy(receiver):
        return sendMessage(runtime, args[0], "value", @[])
      return sendMessage(runtime, args[1], "value", @[])
    return NodeValue(kind: vkNil)

  of "and:":
    if receiver.kind == vkBool and args.len > 0:
      if not receiver.boolVal:
        return NodeValue(kind: vkBool, boolVal: false)
      let rhs = sendMessage(runtime, args[0], "value", @[])
      return NodeValue(kind: vkBool, boolVal: isTruthy(rhs))
    return NodeValue(kind: vkNil)

  of "or:":
    if receiver.kind == vkBool and args.len > 0:
      if receiver.boolVal:
        return NodeValue(kind: vkBool, boolVal: true)
      let rhs = sendMessage(runtime, args[0], "value", @[])
      return NodeValue(kind: vkBool, boolVal: isTruthy(rhs))
    return NodeValue(kind: vkNil)

  of "&":
    if receiver.kind == vkBool and args.len > 0 and args[0].kind == vkBool:
      return NodeValue(kind: vkBool, boolVal: receiver.boolVal and args[0].boolVal)
    return NodeValue(kind: vkNil)

  of "|":
    if receiver.kind == vkBool and args.len > 0 and args[0].kind == vkBool:
      return NodeValue(kind: vkBool, boolVal: receiver.boolVal or args[0].boolVal)
    return NodeValue(kind: vkNil)

  of "not":
    if receiver.kind == vkBool:
      return NodeValue(kind: vkBool, boolVal: not receiver.boolVal)
    return NodeValue(kind: vkNil)
  else:
    # Check for compiled method on Nim proxy objects
    if selector == "isKindOf:" and args.len > 0:
      let receiverClass = getReceiverClassName(receiver)
      if receiverClass.len > 0:
        var targetClass = ""
        case args[0].kind
        of vkClass:
          if args[0].classVal != nil:
            targetClass = args[0].classVal.name
        of vkSymbol:
          targetClass = args[0].symVal
        of vkString:
          targetClass = args[0].strVal
        else:
          discard

        var currentClass = receiverClass
        while currentClass.len > 0:
          if currentClass == targetClass:
            return NodeValue(kind: vkBool, boolVal: true)
          currentClass = getSuperclassName(currentClass)
        return NodeValue(kind: vkBool, boolVal: false)

    let className = getReceiverClassName(receiver)
    if className.len > 0:
      return dispatchCompiledMethodFromClass(receiver, className, selector, args)
    return NodeValue(kind: vkNil)

# Global interpreter instance for mixed mode (initialized on first use)
var hybridInterpreter*: Interpreter = nil
var hybridScheduler*: SchedulerContext = nil

proc initHybridRuntime*(sourceFiles: seq[string] = @[]) =
  ## Initialize the hybrid runtime (interpreter embedded in compiled code)
  ## sourceFiles: optional list of .hrd files to load (creates classes in interpreter)
  if hybridInterpreter == nil:
    hybridScheduler = newSchedulerContext()
    hybridInterpreter = hybridScheduler.mainProcess.getInterpreter()
    initGlobals(hybridInterpreter)
    initSymbolTable()
    loadStdlib(hybridInterpreter)
    # Load user source files to register classes
    for srcFile in sourceFiles:
      if fileExists(srcFile):
        let source = readFile(srcFile)
        let (_, err) = hybridInterpreter.evalStatements(source)
        if err.len > 0:
          warn("Failed to load source file ", srcFile, ": ", err)

proc sendMessageHybrid*(receiver: NodeValue, selector: string,
                       args: seq[NodeValue]): NodeValue =
  ## Hybrid message dispatch: try compiled first, fall back to interpreter
  ## This is used in mixed mode (--mixed flag) for unsupported features
  
  # First, try to use the compiled runtime if available
  if currentRuntime != nil:
    let dispatchResult = sendMessage(currentRuntime[], receiver, selector, args)
    # If result is not nil, the compiled version handled it
    if dispatchResult.kind != vkNil:
      return dispatchResult
  
  # Fall back to interpreter for uncompiled methods
  initHybridRuntime()
  
  # If receiver is a Nim proxy (native object), we need to find or create interpreter instance
  if receiver.kind == vkInstance and receiver.instVal != nil and receiver.instVal.isNimProxy:
    # This is a native object - we need the interpreter to know about it
    # For now, return nil with a warning
    when not defined(release):
      echo "Mixed mode: Nim proxy not yet supported for '", selector, "'"
    return NodeValue(kind: vkNil)
  
  # Use interpreter to evaluate the message send
  when not defined(release):
    echo "Mixed mode: Falling back to interpreter for '", selector, "'"
  
  # Build source code to evaluate
  var source = ""
  if receiver.kind == vkInstance and receiver.instVal != nil:
    # Get the class name for display
    let className = if receiver.instVal.class != nil: receiver.instVal.class.name else: "?"
    source = className
  elif receiver.kind == vkClass:
    source = "Class"
  else:
    source = receiver.toString()
  
  if args.len == 0:
    source.add(" " & selector)
  else:
    source.add(" " & selector & " ")
    for i, arg in args:
      source.add(arg.toString())
      if i < args.len - 1:
        source.add(" ")
  
  let (results, err) = hybridInterpreter.evalStatements(source)
  if err.len > 0:
    when not defined(release):
      echo "Mixed mode error: ", err
    return NodeValue(kind: vkNil)
  
  if results.len > 0:
    return results[results.len - 1]  # Return last result
  return NodeValue(kind: vkNil)

# Convenience procs for common operations

proc toValue*(obj: Instance): NodeValue =
  ## Convert Instance to NodeValue
  if obj == nil:
    return NodeValue(kind: vkNil)
  return NodeValue(kind: vkInstance, instVal: obj)

proc toNodeValue*(obj: Instance): NodeValue =
  ## Alias for toValue
  return obj.toValue()

proc toInt*(value: NodeValue): int =
  ## Get integer value, raise error if not an integer
  if value.kind != vkInt:
    raise newException(ValueError, fmt("Expected Int, got {value.kind}"))
  return value.intVal

proc toFloat*(value: NodeValue): float64 =
  ## Get float value, raise error if not a float
  if value.kind == vkFloat:
    return value.floatVal
  if value.kind == vkInt:
    return float(value.intVal)
  raise newException(ValueError, fmt("Expected Float, got {value.kind}"))

proc toBool*(value: NodeValue): bool =
  ## Get boolean value, raise error if not a boolean
  if value.kind != vkBool:
    raise newException(ValueError, fmt("Expected Bool, got {value.kind}"))
  return value.boolVal

# Slot access helpers

proc getSlot*(obj: Instance, name: string): NodeValue =
  ## Get slot value by name (O(1) if slot exists)
  if obj == nil or obj.kind != ikObject or obj.class == nil:
    return NodeValue(kind: vkNil)

  let idx = obj.class.getSlotIndex(name)
  if idx >= 0 and idx < obj.slots.len:
    return obj.slots[idx]

  return NodeValue(kind: vkNil)

proc setSlot*(obj: Instance, name: string, value: NodeValue): NodeValue =
  ## Set slot value by name
  if obj == nil or obj.kind != ikObject or obj.class == nil:
    return value

  let idx = obj.class.getSlotIndex(name)
  if idx >= 0:
    while obj.slots.len <= idx:
      obj.slots.add(NodeValue(kind: vkNil))
    obj.slots[idx] = value

  return value
