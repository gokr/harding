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
  of "writeLine:", "println":
    if args.len > 0:
      echo args[0].toString()
    return receiver
  of "write:", "print":
    if args.len > 0:
      stdout.write(args[0].toString())
    return receiver
  of "toString", "asString":
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
  else:
    # Unknown selector - return nil for now
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
    let result = sendMessage(currentRuntime[], receiver, selector, args)
    # If result is not nil, the compiled version handled it
    if result.kind != vkNil:
      return result
  
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
