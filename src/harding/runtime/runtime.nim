import std/[tables, strformat, os, strutils, logging]
import ../core/log_support
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

type
  CompiledHardingError* = object of CatchableError
    value*: NodeValue
  HandlerRetry = object of CatchableError
    exceptionInstance: Instance

var activeErrorHandlers {.threadvar.}: seq[Instance]

proc getSuperclassName*(className: string): string
proc ensureCompiledExceptionHierarchy*(): void
proc matchesCompiledError(value: NodeValue, handlerClass: NodeValue): bool
proc compiledMissingMessage(receiver: NodeValue, selector: string): NodeValue
proc sendMessage*(runtime: Runtime, receiver: NodeValue,
                  selector: string, args: seq[NodeValue]): NodeValue

type
  NotificationPass = object of CatchableError
    ## Raised by a notification handler that delegates to an outer handler.
    notification: NodeValue

  NotificationHandlerEntry = ref object
    exceptionClass: NodeValue
    handlerBlock: NodeValue
    running: bool

# Notifications dispatch synchronously while the signaling compiled code keeps
# running: `Notification signal:` calls the innermost active handler itself and
# answers with its result, so code after the signal continues normally. on:do:
# registers its class and handler here for the duration of the protected block.
var activeNotificationHandlers {.threadvar.}: seq[NotificationHandlerEntry]
var activeNotifications {.threadvar.}: seq[Instance]

proc isNotificationClass(name: string): bool =
  ## True when name is Notification or inherits from it.
  var current = name
  while current.len > 0:
    if current == "Notification":
      return true
    current = getSuperclassName(current)
  return false

proc matchesNotificationHandler(notification: NodeValue,
                                handlerClass: NodeValue): bool =
  ## Notifications use the same subclass matching as errors.
  return matchesCompiledError(notification, handlerClass)

proc dispatchCompiledNotification(runtime: Runtime, notification: NodeValue,
                                  handledBy: int): tuple[handled: bool, value: NodeValue] =
  ## Invoke handlers synchronously, excluding every currently running handler.
  var index = if handledBy < 0: activeNotificationHandlers.high else: handledBy - 1
  while index >= 0:
    let entry = activeNotificationHandlers[index]
    if not entry.running and matchesNotificationHandler(notification, entry.exceptionClass):
      entry.running = true
      activeNotifications.add(notification.instVal)
      try:
        try:
          return (true, sendMessage(runtime, entry.handlerBlock, "value:", @[notification]))
        except NotificationPass as action:
          if action.notification.instVal != notification.instVal:
            raise
          return dispatchCompiledNotification(runtime, notification, index)
      finally:
        discard activeNotifications.pop()
        entry.running = false
    dec index
  return (false, NodeValue(kind: vkNil))

proc initRuntime*() =
  ## Initialize global runtime
  if currentRuntime == nil:
    ensureCompiledExceptionHierarchy()
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
type
  CompiledProc = proc(self: NodeValue, args: seq[NodeValue]): NodeValue
  CompiledSendCache* = object
    className: string
    selector: string
    version: uint64
    target: CompiledProc

var compiledClassMethods = initTable[string, CompiledProc]()
var compiledAllocators = initTable[string, CompiledProc]()
var compiledClasses = initTable[string, Class]()
var compiledClassDispatchVersion*: uint64 = 1

proc registerCompiledClass*(name: string, allocator: CompiledProc) =
  ## Register a class receiver and its native allocator.
  compiledAllocators[name] = allocator
  inc compiledClassDispatchVersion
  if name notin compiledClasses:
    compiledClasses[name] = newClass(name = name)

proc compiledClassValue*(name: string): NodeValue =
  ## Return the class-side receiver for a compiled class.
  if name in compiledClasses:
    return NodeValue(kind: vkClass, classVal: compiledClasses[name])
  return NodeValue(kind: vkNil)

proc compiledLogClassValue*(): NodeValue =
  ## Class-side receiver for application logging in pure compiled programs.
  if "Log" notin compiledClasses:
    compiledClasses["Log"] = newClass(name = "Log")
  return compiledClassValue("Log")

proc registerCompiledClassMethod*(className, selector: string, fn: CompiledProc) =
  ## Register a class-side method separately from instance methods.
  compiledClassMethods[className & ">>" & selector] = fn
  inc compiledClassDispatchVersion

var nimProxyClassNames*: Table[pointer, string] = initTable[pointer, string]()

type
  SlotGetter* = proc(nimValue: pointer): NodeValue {.nimcall.}
  SlotSetter* = proc(nimValue: pointer, value: NodeValue): NodeValue {.nimcall.}

var slotGetters*: Table[string, SlotGetter] = initTable[string, SlotGetter]()
var slotSetters*: Table[string, SlotSetter] = initTable[string, SlotSetter]()

proc registerSlotAccessor*(className: string, slotName: string,
                           getter: SlotGetter, setter: SlotSetter) =
  let key = className & "::" & slotName
  slotGetters[key] = getter
  slotSetters[key] = setter

proc registerCompiledMethod*(className: string, selector: string,
                              fn: proc(self: NodeValue, args: seq[NodeValue]): NodeValue) =
  let key = className & ">>" & selector
  compiledMethodProcs[key] = fn
  inc compiledClassDispatchVersion

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
  inc compiledClassDispatchVersion

proc getSuperclassName*(className: string): string =
  ## Get the superclass name for a class
  if className in superclassNames:
    return superclassNames[className]
  return ""

proc ensureCompiledExceptionHierarchy*(): void =
  ## Register the built-in exception chain once. Generated modules reference
  ## only the class values they name, so `Error -> Exception` may otherwise be
  ## missing and a user subclass would not match `on: Exception`.
  registerSuperclass("Exception", "")
  registerSuperclass("Error", "Exception")
  registerSuperclass("Notification", "Exception")
  for name in ["DivisionByZero", "MessageNotUnderstood", "SubscriptOutOfBounds",
               "BlockCannotReturn"]:
    registerSuperclass(name, "Error")

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

proc getSlotValue*(self: NodeValue, slotName: string): NodeValue =
  ## Get a slot value from a compiled instance, dispatching by actual class
  if self.kind != vkInstance or self.instVal == nil or not self.instVal.isNimProxy:
    return NodeValue(kind: vkNil)
  let className = getReceiverClassName(self)
  let key = className & "::" & slotName
  if key in slotGetters:
    return slotGetters[key](self.instVal.nimValue)
  return NodeValue(kind: vkNil)

proc setSlotValue*(self: NodeValue, slotName: string, value: NodeValue): NodeValue =
  ## Set a slot value on a compiled instance, dispatching by actual class
  if self.kind != vkInstance or self.instVal == nil or not self.instVal.isNimProxy:
    return value
  let className = getReceiverClassName(self)
  let key = className & "::" & slotName
  if key in slotSetters:
    return slotSetters[key](self.instVal.nimValue, value)
  return value

proc dispatchCompiledMethodFromClass*(receiver: NodeValue, className: string,
                                      selector: string, args: seq[NodeValue]): NodeValue =
  ## Dispatch compiled method by walking class -> superclasses chain
  var currentClass = className
  while currentClass.len > 0:
    let compiledFn = findCompiledMethod(currentClass, selector)
    if compiledFn != nil:
      return compiledFn(receiver, args)
    currentClass = getSuperclassName(currentClass)
  return compiledMissingMessage(receiver, selector)

proc hasCompiledMethodInHierarchy*(className: string, selector: string): bool =
  ## Check if a compiled method exists on this class or any superclass.
  var currentClass = className
  while currentClass.len > 0:
    if findCompiledMethod(currentClass, selector) != nil:
      return true
    currentClass = getSuperclassName(currentClass)
  return false

proc hasCompiledClassMethodInHierarchy*(className, selector: string): bool =
  ## Detect a class-side override, including inherited methods.
  var currentClass = className
  while currentClass.len > 0:
    if currentClass & ">>" & selector in compiledClassMethods:
      return true
    currentClass = getSuperclassName(currentClass)
  return false

proc canDirectAllocate*(className: string,
                        allocator: proc(self: NodeValue, args: seq[NodeValue]): NodeValue): bool =
  ## Guard the default allocation path against method and allocator replacement.
  if className notin compiledAllocators or compiledAllocators[className] != allocator:
    return false
  return not hasCompiledClassMethodInHierarchy(className, "new")

proc compiledNewInstance*(className: string, allocator: CompiledProc): NodeValue =
  ## Native `new` for a class with no class-side override: allocate, then run a
  ## compiled `initialize` when the class hierarchy defines one, matching
  ## Object class>>new basicNew initialize.
  let created = allocator(NodeValue(kind: vkNil), @[])
  if hasCompiledMethodInHierarchy(className, "initialize"):
    return dispatchCompiledMethodFromClass(created, className, "initialize", @[])
  return created

proc dispatchCompiledClassMethod(receiver: NodeValue, startClass, selector: string,
                                 args: seq[NodeValue]): NodeValue =
  var currentClass = startClass
  while currentClass.len > 0:
    let key = currentClass & ">>" & selector
    if key in compiledClassMethods:
      return compiledClassMethods[key](receiver, args)
    currentClass = getSuperclassName(currentClass)
  if selector == "new" and receiver.kind == vkClass and receiver.classVal != nil:
    let name = receiver.classVal.name
    if name in compiledAllocators:
      return compiledNewInstance(name, compiledAllocators[name])
  return compiledMissingMessage(receiver, selector)

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
    return compiledMissingMessage(receiver, selector)
  if receiver.kind == vkClass:
    return dispatchCompiledClassMethod(receiver, startClass, selector, args)
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

proc compiledExceptionClassValue*(name: string): NodeValue =
  ## Built-in exception class receiver for pure compiled programs.
  if name notin compiledClasses:
    compiledClasses[name] = newClass(slotNames = @["message"], name = name)
  if name == "Error" or name == "Notification":
    registerSuperclass(name, "Exception")
  elif name in ["DivisionByZero", "MessageNotUnderstood", "SubscriptOutOfBounds",
                "BlockCannotReturn"]:
    registerSuperclass(name, "Error")
  return compiledClassValue(name)

proc isCompiledExceptionClass(name: string): bool =
  var current = name
  while current.len > 0:
    if current == "Exception":
      return true
    current = getSuperclassName(current)
  return false

proc compiledExceptionMessage*(value: NodeValue): string =
  ## Message slot of a compiled exception instance, proxy or plain instance.
  if value.kind != vkInstance or value.instVal == nil:
    return ""
  if value.instVal.isNimProxy:
    return getSlotValue(value, "message").toString()
  if value.instVal.slots.len > 0:
    return value.instVal.slots[0].toString()
  return ""

proc compiledSetExceptionMessage*(value: NodeValue, message: string): NodeValue =
  ## Store the message slot on a compiled exception instance. Returns the
  ## receiver: setters answer their value, which is not what the caller wants.
  let stored = NodeValue(kind: vkString, strVal: message)
  if value.kind == vkInstance and value.instVal != nil and value.instVal.isNimProxy:
    discard setSlotValue(value, "message", stored)
  elif value.kind == vkInstance and value.instVal != nil and value.instVal.slots.len > 0:
    value.instVal.slots[0] = stored
  return value

proc compiledErrorValue*(name, message: string): NodeValue =
  if name in compiledAllocators:
    let receiver = compiledNewInstance(name, compiledAllocators[name])
    return compiledSetExceptionMessage(receiver, message)
  let clsValue = compiledExceptionClassValue(name)
  let instance = newInstance(clsValue.classVal)
  instance.slots[0] = NodeValue(kind: vkString, strVal: message)
  return instance.toValue()

proc raiseCompiledError*(value: NodeValue): NodeValue =
  let className = if value.kind == vkInstance and value.instVal != nil and value.instVal.class != nil:
                    value.instVal.class.name
                  else:
                    "Exception"
  raise (ref CompiledHardingError)(value: value, msg: className & ": " & compiledExceptionMessage(value))

proc reportUncaughtError*(value: NodeValue): int =
  ## Default action and diagnostic for an error that reached the top of a
  ## compiled program: run `defaultAction`, report it, and answer a failing exit
  ## status, instead of letting a Nim exception escape.
  let className = if value.kind == vkInstance and value.instVal != nil and value.instVal.class != nil:
                    value.instVal.class.name
                  else:
                    "Exception"
  stderr.write("=== Uncaught Exception ===\n")
  stderr.write(className & ": " & compiledExceptionMessage(value) & "\n")
  try:
    discard sendMessage(currentRuntime[], value, "defaultAction", @[])
  except CatchableError:
    discard
  return 1

proc compiledMissingMessage(receiver: NodeValue, selector: string): NodeValue =
  ## Offer a custom DNU method once, then signal the ordinary Harding error.
  let selectorValue = NodeValue(kind: vkSymbol, symVal: selector)
  if selector != "doesNotUnderstand:":
    if receiver.kind == vkClass and receiver.classVal != nil and
       hasCompiledClassMethodInHierarchy(receiver.classVal.name, "doesNotUnderstand:"):
      return dispatchCompiledClassMethod(receiver, receiver.classVal.name,
                                         "doesNotUnderstand:", @[selectorValue])
    let className = getReceiverClassName(receiver)
    if className.len > 0 and hasCompiledMethodInHierarchy(className, "doesNotUnderstand:"):
      return dispatchCompiledMethodFromClass(receiver, className, "doesNotUnderstand:", @[selectorValue])
  return raiseCompiledError(compiledErrorValue("MessageNotUnderstood", "Message not understood: " & selector))

proc matchesCompiledError(value: NodeValue, handlerClass: NodeValue): bool =
  if value.kind != vkInstance or value.instVal == nil or value.instVal.class == nil or
     handlerClass.kind != vkClass or handlerClass.classVal == nil:
    return false
  var name = value.instVal.class.name
  while name.len > 0:
    if name == handlerClass.classVal.name:
      return true
    name = getSuperclassName(name)
  return false

proc sendMessage*(runtime: Runtime, receiver: NodeValue,
                  selector: string, args: seq[NodeValue]): NodeValue =
  ## Send a message to a receiver (dynamic dispatch)
  ## This is the slow path fallback for compiled code

  if receiver.kind == vkBlock and selector == "ensure:" and args.len == 1:
    # Run the protected block, then the cleanup exactly once, whether the body
    # completes, fails, or leaves through a non-local return. The cleanup result
    # is discarded and the body's result is preserved.
    try:
      return sendMessage(runtime, receiver, "value", @[])
    finally:
      discard sendMessage(runtime, args[0], "value", @[])

  if receiver.kind == vkBlock and selector == "on:do:" and args.len == 2:
    let handlerClass = args[0]
    let notificationHandler = NotificationHandlerEntry(
      exceptionClass: handlerClass, handlerBlock: args[1])
    activeNotificationHandlers.add(notificationHandler)
    defer:
      discard activeNotificationHandlers.pop()
    if handlerClass.kind == vkClass and handlerClass.classVal != nil and
       isNotificationClass(handlerClass.classVal.name):
      # Notifications do not unwind: the protected block keeps running and a
      # synchronous handler call supplies the value of the signal expression.
      return sendMessage(runtime, receiver, "value", @[])
    while true:
      try:
        return sendMessage(runtime, receiver, "value", @[])
      except CompiledHardingError as failure:
        if not matchesCompiledError(failure.value, args[0]):
          raise
        var retryRequested = false
        activeErrorHandlers.add(failure.value.instVal)
        notificationHandler.running = true
        try:
          try:
            return sendMessage(runtime, args[1], "value:", @[failure.value])
          except HandlerRetry as action:
            if action.exceptionInstance != failure.value.instVal:
              raise
            retryRequested = true
        finally:
          discard activeErrorHandlers.pop()
          notificationHandler.running = false
        if not retryRequested:
          raise

  if receiver.kind == vkClass and receiver.classVal != nil and
     isCompiledExceptionClass(receiver.classVal.name) and selector == "signal:" and args.len == 1:
    let notification = compiledErrorValue(receiver.classVal.name, args[0].toString())
    if isNotificationClass(receiver.classVal.name):
      # Synchronous: run the innermost handler now and answer with its result.
      let dispatch = dispatchCompiledNotification(runtime, notification, -1)
      if dispatch.handled:
        return dispatch.value
      discard sendMessage(runtime, notification, "defaultAction", @[])
      return NodeValue(kind: vkNil)
    return raiseCompiledError(notification)

  if receiver.kind == vkInstance and receiver.instVal != nil and receiver.instVal.class != nil and
     isCompiledExceptionClass(receiver.instVal.class.name):
    # User-defined exception methods take precedence over the built-in protocol.
    if hasCompiledMethodInHierarchy(receiver.instVal.class.name, selector):
      return dispatchCompiledMethodFromClass(receiver, receiver.instVal.class.name, selector, args)
    if isNotificationClass(receiver.instVal.class.name):
      case selector
      of "message":
        return NodeValue(kind: vkString, strVal: compiledExceptionMessage(receiver))
      of "signal":
        let dispatch = dispatchCompiledNotification(runtime, receiver, -1)
        if dispatch.handled:
          return dispatch.value
        discard sendMessage(runtime, receiver, "defaultAction", @[])
        return NodeValue(kind: vkNil)
      of "pass":
        if receiver.instVal notin activeNotifications:
          return raiseCompiledError(compiledErrorValue("Error", "Exception action requires an active handler"))
        raise (ref NotificationPass)(notification: receiver)
      of "retry":
        return raiseCompiledError(compiledErrorValue("Error",
          "Notification does not support " & selector))
      else:
        discard

    case selector
    of "defaultAction":
      echo "Exception: " & compiledExceptionMessage(receiver)
      return receiver
    of "message":
      return NodeValue(kind: vkString, strVal: compiledExceptionMessage(receiver))
    of "message:":
      if args.len >= 1:
        return compiledSetExceptionMessage(receiver, args[0].toString())
      return receiver
    of "printString":
      return NodeValue(kind: vkString,
        strVal: receiver.instVal.class.name & ": " & compiledExceptionMessage(receiver))
    of "signal":
      return raiseCompiledError(receiver)
    of "retry", "pass":
      if receiver.instVal notin activeErrorHandlers:
        return raiseCompiledError(compiledErrorValue("Error", "Exception action requires an active handler"))
      if selector == "retry":
        raise (ref HandlerRetry)(exceptionInstance: receiver.instVal)
      if selector == "pass":
        return raiseCompiledError(receiver)
    else:
      discard

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

  if receiver.kind == vkClass and receiver.classVal != nil:
    if receiver.classVal.name == "Log" and args.len == 1 and
       not hasCompiledClassMethodInHierarchy("Log", selector):
      case selector
      of "debug:": return writeHardingLog(logging.lvlDebug, args[0])
      of "info:": return writeHardingLog(logging.lvlInfo, args[0])
      of "warn:": return writeHardingLog(logging.lvlWarn, args[0])
      of "error:": return writeHardingLog(logging.lvlError, args[0])
      of "fatal:": return writeHardingLog(logging.lvlFatal, args[0])
      else: discard
    return dispatchCompiledClassMethod(receiver, receiver.classVal.name, selector, args)

  let receiverClassName = getReceiverClassName(receiver)
  if receiverClassName.len > 0 and hasCompiledMethodInHierarchy(receiverClassName, selector):
    return dispatchCompiledMethodFromClass(receiver, receiverClassName, selector, args)

  case selector
  of "isNil":
    return NodeValue(kind: vkBool, boolVal: receiver.kind == vkNil)
  of "notNil":
    return NodeValue(kind: vkBool, boolVal: receiver.kind != vkNil)
  of "writeLine:", "writeline:", "println", "println:":
    if args.len > 0:
      echo args[0].toString()
    return receiver
  of "write:", "print", "print:":
    if args.len > 0:
      stdout.write(args[0].toString())
    return receiver
  of "toString", "asString":
    return NodeValue(kind: vkString, strVal: receiver.toString())
  of "printString":
    return NodeValue(kind: vkString, strVal: receiver.toString())
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
      return NodeValue(kind: vkFloat, floatVal: float(receiver.intVal) / float(args[0].intVal))
    return NodeValue(kind: vkNil)
  of "//":
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
        let idx = args[0].intVal
        if idx >= 0 and idx < receiver.arrayVal.len:
          return receiver.arrayVal[idx]
      elif receiver.kind == vkTable:
        if receiver.tableVal.hasKey(args[0]):
          return receiver.tableVal[args[0]]
    return NodeValue(kind: vkNil)

  of "at:put:":
    if args.len >= 2:
      if receiver.kind == vkArray and args[0].kind == vkInt:
        let idx = args[0].intVal
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
    if receiver.kind == vkString:
      return NodeValue(kind: vkInt, intVal: receiver.strVal.len)
    return NodeValue(kind: vkNil)

  of "first":
    if receiver.kind == vkArray and receiver.arrayVal.len > 0:
      return receiver.arrayVal[0]
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

  of "uppercase":
    if receiver.kind == vkString:
      return NodeValue(kind: vkString, strVal: receiver.strVal.toUpperAscii())
    return NodeValue(kind: vkNil)

  of "lowercase":
    if receiver.kind == vkString:
      return NodeValue(kind: vkString, strVal: receiver.strVal.toLowerAscii())
    return NodeValue(kind: vkNil)

  of "trim":
    if receiver.kind == vkString:
      return NodeValue(kind: vkString, strVal: receiver.strVal.strip())
    return NodeValue(kind: vkNil)

  of "indexOf:":
    if receiver.kind == vkString and args.len > 0 and args[0].kind == vkString:
      return NodeValue(kind: vkInt, intVal: receiver.strVal.find(args[0].strVal))
    return NodeValue(kind: vkNil)

  of "includesSubString:":
    if receiver.kind == vkString and args.len > 0 and args[0].kind == vkString:
      return NodeValue(kind: vkBool, boolVal: receiver.strVal.contains(args[0].strVal))
    return NodeValue(kind: vkNil)

  of "replace:with:":
    if receiver.kind == vkString and args.len >= 2 and args[0].kind == vkString and args[1].kind == vkString:
      return NodeValue(kind: vkString, strVal: receiver.strVal.replace(args[0].strVal, args[1].strVal))
    return NodeValue(kind: vkNil)

  of "split:":
    if receiver.kind == vkString and args.len > 0 and args[0].kind == vkString:
      var parts: seq[NodeValue] = @[]
      for part in receiver.strVal.split(args[0].strVal):
        parts.add(NodeValue(kind: vkString, strVal: part))
      return NodeValue(kind: vkArray, arrayVal: parts)
    return NodeValue(kind: vkNil)

  of "max:":
    if args.len > 0:
      if receiver.kind == vkInt and args[0].kind == vkInt:
        return NodeValue(kind: vkInt, intVal: max(receiver.intVal, args[0].intVal))
      if receiver.kind == vkFloat and args[0].kind == vkFloat:
        return NodeValue(kind: vkFloat, floatVal: max(receiver.floatVal, args[0].floatVal))
    return NodeValue(kind: vkNil)

  of "min:":
    if args.len > 0:
      if receiver.kind == vkInt and args[0].kind == vkInt:
        return NodeValue(kind: vkInt, intVal: min(receiver.intVal, args[0].intVal))
      if receiver.kind == vkFloat and args[0].kind == vkFloat:
        return NodeValue(kind: vkFloat, floatVal: min(receiver.floatVal, args[0].floatVal))
    return NodeValue(kind: vkNil)

  of "between:and:":
    if args.len >= 2 and receiver.kind == vkInt and args[0].kind == vkInt and args[1].kind == vkInt:
      return NodeValue(kind: vkBool, boolVal: receiver.intVal >= args[0].intVal and receiver.intVal <= args[1].intVal)
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
    if args.len > 0:
      let aStr = receiver.toString()
      let bStr = args[0].toString()
      return NodeValue(kind: vkString, strVal: aStr & bStr)
    return receiver

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

    if receiverClassName.len > 0:
      return dispatchCompiledMethodFromClass(receiver, receiverClassName, selector, args)
    return compiledMissingMessage(receiver, selector)

proc sendMessageCached*(runtime: Runtime, receiver: NodeValue, selector: string,
                        args: seq[NodeValue], cache: var CompiledSendCache): NodeValue =
  ## Positive monomorphic cache for registered instance methods only. Builtins,
  ## class-side sends and exception protocols retain the generic runtime path.
  if selector in ["message", "signal", "defaultAction", "retry", "pass"]:
    return sendMessage(runtime, receiver, selector, args)
  let className = getReceiverClassName(receiver)
  if className.len > 0:
    if cache.version == compiledClassDispatchVersion and cache.className == className and
       cache.selector == selector and cache.target != nil:
      let target = cache.target
      return target(receiver, args)
    var currentClass = className
    var target: CompiledProc
    while currentClass.len > 0:
      target = findCompiledMethod(currentClass, selector)
      if target != nil:
        break
      currentClass = getSuperclassName(currentClass)
    if target != nil:
      cache = CompiledSendCache(className: className, selector: selector,
                                version: compiledClassDispatchVersion, target: target)
      return target(receiver, args)
  return sendMessage(runtime, receiver, selector, args)

template cachedSend*(runtime: Runtime, receiver: NodeValue, selector: string,
                     args: seq[NodeValue]): NodeValue =
  ## Each expanded send site owns its cache; recursive calls may safely replace
  ## the entry because the selected target is copied before invocation.
  block:
    var siteCache {.global, threadvar.}: CompiledSendCache
    sendMessageCached(runtime, receiver, selector, args, siteCache)

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
          types.warn("Failed to load source file ", srcFile, ": ", err)

proc sendMessageHybrid*(receiver: NodeValue, selector: string,
                       args: seq[NodeValue]): NodeValue =
  ## Hybrid message dispatch: try compiled first, fall back to interpreter
  ## This is used in mixed mode (--mixed flag) for unsupported features
  
  # First, try to use the compiled runtime if available
  if currentRuntime != nil:
    try:
      let dispatchResult = sendMessage(currentRuntime[], receiver, selector, args)
      # If result is not nil, the compiled version handled it
      if dispatchResult.kind != vkNil:
        return dispatchResult
    except CompiledHardingError as failure:
      if failure.value.kind != vkInstance or failure.value.instVal == nil or
         failure.value.instVal.class == nil or failure.value.instVal.class.name != "MessageNotUnderstood":
        raise
  
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
