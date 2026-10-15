import std/[tables, strformat, os, strutils, logging, json]
import ../core/log_support
import ../core/string_conversion
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
proc registerSuperclass*(className: string, superclassName: string)
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

proc compiledBaseClassValue*(name: string): NodeValue =
  ## Canonical class receiver for the built-in base hierarchy, without an allocator.
  if name notin ["Root", "Object", "Mixin"]:
    return NodeValue(kind: vkNil)
  if name notin compiledClasses:
    compiledClasses[name] = newClass(name = name)
  registerSuperclass("Object", "Root")
  registerSuperclass("Mixin", "Root")
  return compiledClassValue(name)

proc compiledSystemClassValue*(): NodeValue =
  ## Canonical System receiver for native process-level services.
  if "System" notin compiledClasses:
    compiledClasses["System"] = newClass(name = "System")
  return compiledClassValue("System")

proc compiledSystemArguments*(): NodeValue =
  ## Snapshot user arguments, excluding the executable name, as Harding strings.
  var elements: seq[NodeValue] = @[]
  for argument in commandLineParams():
    elements.add(toValue(argument))
  return NodeValue(kind: vkArray, arrayVal: elements)

proc compiledLogClassValue*(): NodeValue =
  ## Class-side receiver for application logging in pure compiled programs.
  if "Log" notin compiledClasses:
    compiledClasses["Log"] = newClass(name = "Log")
  return compiledClassValue("Log")

proc compiledJsonClassValue*(): NodeValue =
  ## Class-side receiver for JSON literal construction.
  if "Json" notin compiledClasses:
    compiledClasses["Json"] = newClass(name = "Json")
  return compiledClassValue("Json")

proc compiledJsonEscape(buf: var string, value: string) =
  ## Mirror the interpreter's JSON string escaping.
  buf.add '"'
  for c in value:
    case c
    of '"': buf.add("\\\"")
    of '\\': buf.add("\\\\")
    of '\b': buf.add("\\b")
    of '\f': buf.add("\\f")
    of '\n': buf.add("\\n")
    of '\r': buf.add("\\r")
    of '\t': buf.add("\\t")
    of '\0'..'\7', '\11', '\14'..'\31', '\127':
      buf.add("\\u00")
      buf.add(toHex(ord(c), 2).toLowerAscii())
    else:
      buf.add(c)
  buf.add '"'

proc enterJsonInstance(visited: var seq[Instance], instance: Instance): bool =
  if instance in visited:
    return false
  visited.add(instance)
  return true

proc leaveJsonInstance(visited: var seq[Instance]) =
  discard visited.pop()

proc compiledJsonKey(buf: var string, key: NodeValue) =
  ## Table keys follow the interpreter's scalar spelling.
  case key.kind
  of vkString:
    compiledJsonEscape(buf, key.strVal)
  of vkSymbol:
    compiledJsonEscape(buf, key.symVal)
  of vkInt:
    compiledJsonEscape(buf, $key.intVal)
  of vkFloat:
    compiledJsonEscape(buf, $(%key.floatVal))
  of vkBool:
    compiledJsonEscape(buf, if key.boolVal: "true" else: "false")
  of vkNil:
    compiledJsonEscape(buf, "null")
  of vkClass:
    compiledJsonEscape(buf, key.classVal.name)
  of vkInstance:
    case key.instVal.kind
    of ikString: compiledJsonEscape(buf, key.instVal.strVal)
    of ikInt: compiledJsonEscape(buf, $key.instVal.intVal)
    of ikFloat: compiledJsonEscape(buf, $(%key.instVal.floatVal))
    else: raise newException(ValueError, "Unsupported JSON table key: " & key.toString())
  else:
    raise newException(ValueError, "Unsupported JSON table key: " & key.toString())

proc compiledJsonValue(buf: var string, value: NodeValue, visited: var seq[Instance])

proc compiledJsonTable(buf: var string, entries: Table[NodeValue, NodeValue], visited: var seq[Instance]) =
  ## Nested tables are compact, matching the interpreter's writer.
  buf.add '{'
  var first = true
  for key, entryValue in entries.pairs:
    if not first:
      buf.add ','
    first = false
    compiledJsonKey(buf, key)
    buf.add ':'
    compiledJsonValue(buf, entryValue, visited)
  buf.add '}'

proc compiledJsonArray(buf: var string, elements: seq[NodeValue], visited: var seq[Instance]) =
  buf.add '['
  for index, element in elements:
    if index > 0:
      buf.add ','
    compiledJsonValue(buf, element, visited)
  buf.add ']'

proc compiledJsonValue(buf: var string, value: NodeValue, visited: var seq[Instance]) =
  # nil (vkNil or the UndefinedObject instance) has a dedicated JSON literal.
  if isNilValue(value):
    buf.add("null")
    return
  case value.kind
  of vkInt:
    buf.add($value.intVal)
  of vkFloat:
    buf.add($(%value.floatVal))
  of vkString:
    compiledJsonEscape(buf, value.strVal)
  of vkBool:
    buf.add(if value.boolVal: "true" else: "false")
  of vkNil:
    buf.add("null")
  of vkArray:
    compiledJsonArray(buf, value.arrayVal, visited)
  of vkTable:
    compiledJsonTable(buf, value.tableVal, visited)
  of vkSymbol:
    compiledJsonEscape(buf, value.symVal)
  of vkClass:
    compiledJsonEscape(buf, value.classVal.name)
  of vkInstance:
    case value.instVal.kind
    of ikInt: buf.add($value.instVal.intVal)
    of ikFloat: buf.add($(%value.instVal.floatVal))
    of ikString: compiledJsonEscape(buf, value.instVal.strVal)
    of ikArray:
      if not enterJsonInstance(visited, value.instVal):
        raise newException(ValueError, "JSON serialization cycle detected")
      compiledJsonArray(buf, value.instVal.elements, visited)
      leaveJsonInstance(visited)
    of ikTable:
      if not enterJsonInstance(visited, value.instVal):
        raise newException(ValueError, "JSON serialization cycle detected")
      compiledJsonTable(buf, value.instVal.entries, visited)
      leaveJsonInstance(visited)
    of ikObject:
      raise newException(ValueError, "Native JSON object serialization is not implemented")
  else:
    compiledJsonEscape(buf, value.toString())

proc compiledJsonDynamicTable(entries: Table[NodeValue, NodeValue], visited: var seq[Instance]): NodeValue =
  ## `json{...}` literal entries use ", " and ": ", matching the interpreter.
  var buf = newStringOfCap(64)
  buf.add '{'
  var first = true
  for key, entryValue in entries.pairs:
    if not first:
      buf.add ", "
    first = false
    let keyText = if key.kind == vkString: key.strVal else: key.toString()
    compiledJsonEscape(buf, keyText)
    buf.add ": "
    compiledJsonValue(buf, entryValue, visited)
  buf.add '}'
  return NodeValue(kind: vkString, strVal: buf)

proc compiledJsonBuildDynamic*(value: NodeValue): NodeValue =
  ## Evaluate a `json{...}` literal. Nested values stay compact.
  var visited: seq[Instance]
  if value.kind == vkTable:
    return compiledJsonDynamicTable(value.tableVal, visited)
  if value.kind == vkArray:
    var arrayBuf = newStringOfCap(64)
    arrayBuf.add '['
    for index, element in value.arrayVal:
      if index > 0:
        arrayBuf.add ", "
      compiledJsonValue(arrayBuf, element, visited)
    arrayBuf.add ']'
    return NodeValue(kind: vkString, strVal: arrayBuf)
  if value.kind == vkInstance:
    case value.instVal.kind
    of ikTable: return compiledJsonDynamicTable(value.instVal.entries, visited)
    of ikArray:
      var arrayBuf = newStringOfCap(64)
      if not enterJsonInstance(visited, value.instVal):
        raise newException(ValueError, "JSON serialization cycle detected")
      arrayBuf.add '['
      for index, element in value.instVal.elements:
        if index > 0:
          arrayBuf.add ", "
        compiledJsonValue(arrayBuf, element, visited)
      arrayBuf.add ']'
      leaveJsonInstance(visited)
      return NodeValue(kind: vkString, strVal: arrayBuf)
    else: discard
  return NodeValue(kind: vkString, strVal: "{}")

proc compiledJsonStringify*(value: NodeValue): NodeValue =
  ## `Json stringify:` for scalars and collections; object protocols are separate.
  var visited: seq[Instance]
  var buf = newStringOfCap(64)
  compiledJsonValue(buf, value, visited)
  return NodeValue(kind: vkString, strVal: buf)

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
var superclassLists*: Table[string, seq[string]] = initTable[string, seq[string]]()

proc registerSuperclass*(className: string, superclassName: string) =
  ## Register one superclass in declaration order. A class may have several
  ## parents (`addSuperclass:`), so this appends rather than replaces; repeated
  ## registration of the same parent is ignored. Dispatch searches parents in
  ## this order, matching the interpreter.
  if superclassName.len == 0:
    if className notin superclassLists:
      superclassLists[className] = @[]
    inc compiledClassDispatchVersion
    return
  var parents = superclassLists.getOrDefault(className)
  if superclassName notin parents:
    parents.add(superclassName)
    superclassLists[className] = parents
    inc compiledClassDispatchVersion
  superclassNames[className] = parents[0]

proc getSuperclassName*(className: string): string =
  ## First (primary) superclass of a class, or "".
  if className in superclassLists and superclassLists[className].len > 0:
    return superclassLists[className][0]
  if className in superclassNames:
    return superclassNames[className]
  return ""

proc getSuperclasses*(className: string): seq[string] =
  ## All registered superclasses in declaration order.
  if className in superclassLists:
    return superclassLists[className]
  if className in superclassNames and superclassNames[className].len > 0:
    return @[superclassNames[className]]
  return @[]

proc walkCompiledHierarchy*(className: string, visit: proc(name: string): bool): string =
  ## Depth-first pre-order over the superclass graph, parents in declaration
  ## order. `visit` returns true to stop; the visited name is returned, or "".
  ## A `seen` guard keeps a malformed cyclic hierarchy from looping forever.
  var seen: seq[string] = @[]
  proc walk(name: string): string =
    if name.len == 0 or name in seen:
      return ""
    seen.add(name)
    if visit(name):
      return name
    for parent in getSuperclasses(name):
      let found = walk(parent)
      if found.len > 0:
        return found
    return ""
  return walk(className)

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
  ## Dispatch compiled method by walking class -> superclass graph in declaration
  ## order, so multiple parents follow the interpreter's lookup order.
  let owner = walkCompiledHierarchy(className,
    proc(name: string): bool = findCompiledMethod(name, selector) != nil)
  if owner.len > 0:
    return findCompiledMethod(owner, selector)(receiver, args)
  return compiledMissingMessage(receiver, selector)

proc hasCompiledMethodInHierarchy*(className: string, selector: string): bool =
  ## Check if a compiled method exists on this class or any superclass.
  return walkCompiledHierarchy(className,
    proc(name: string): bool = findCompiledMethod(name, selector) != nil).len > 0

proc hasCompiledClassMethodInHierarchy*(className, selector: string): bool =
  ## Detect a class-side override, including inherited methods.
  return walkCompiledHierarchy(className,
    proc(name: string): bool = name & ">>" & selector in compiledClassMethods).len > 0

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
  let owner = walkCompiledHierarchy(startClass,
    proc(name: string): bool = name & ">>" & selector in compiledClassMethods)
  if owner.len > 0:
    return compiledClassMethods[owner & ">>" & selector](receiver, args)
  if selector == "new" and receiver.kind == vkClass and receiver.classVal != nil:
    let name = receiver.classVal.name
    if name in compiledAllocators:
      return compiledNewInstance(name, compiledAllocators[name])
  return compiledMissingMessage(receiver, selector)

proc sendSuperMessage*(receiver: NodeValue, definingClassName: string,
                       selector: string, args: seq[NodeValue],
                       explicitParent: string = ""): NodeValue =
  ## Keep the receiver and start lookup at a direct parent of the declaring class.
  ## An explicit qualifier must name one of that class's direct parents.
  var startClass = explicitParent
  if startClass.len > 0:
    if startClass notin getSuperclasses(definingClassName):
      raise newException(ValueError, "Parent class '" & startClass & "' not found in inheritance chain")
  else:
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
  return walkCompiledHierarchy(name, proc(candidate: string): bool = candidate == "Exception").len > 0

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

proc compiledIdentityEqual*(a, b: NodeValue): bool =
  ## Match VM identity comparisons, using the retained native owner for compiled
  ## instances whose storage may be exposed through multiple Instance wrappers.
  if a.kind == vkInstance and b.kind == vkInstance and
     a.instVal != nil and b.instVal != nil and
     a.instVal.compiledOwner != nil and b.instVal.compiledOwner != nil:
    return a.instVal.compiledOwner == b.instVal.compiledOwner
  return identityEqual(a, b)

proc sendMessage*(runtime: Runtime, receiver: NodeValue,
                  selector: string, args: seq[NodeValue]): NodeValue =
  ## Send a message to a receiver (dynamic dispatch)
  ## This is the slow path fallback for compiled code

  if selector in ["==", "~="] and args.len == 1:
    let same = compiledIdentityEqual(receiver, args[0])
    return NodeValue(kind: vkBool, boolVal: if selector == "==": same else: not same)

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
    if selector == "addSuperclass:" and args.len >= 1:
      # Register another parent at runtime, matching the interpreter. Generated
      # modules also emit these statically; this path covers ids whose parent is
      # only known at execution time.
      var parentName = ""
      if args[0].kind == vkClass and args[0].classVal != nil:
        parentName = args[0].classVal.name
      elif args[0].kind == vkInstance and args[0].instVal != nil and args[0].instVal.class != nil:
        parentName = args[0].instVal.class.name
      if parentName.len > 0:
        registerSuperclass(receiver.classVal.name, parentName)
      return receiver
    if args.len == 0:
      case selector
      of "class": return receiver
      of "name", "className":
        if not hasCompiledClassMethodInHierarchy(receiver.classVal.name, selector):
          return toValue(receiver.classVal.name)
      of "superclassNames":
        if not hasCompiledClassMethodInHierarchy(receiver.classVal.name, selector):
          var names: seq[NodeValue] = @[]
          for parent in getSuperclasses(receiver.classVal.name):
            names.add(toValue(parent))
          return NodeValue(kind: vkArray, arrayVal: names)
      else: discard
    if receiver.classVal.name == "System" and selector == "arguments" and args.len == 0 and
       not hasCompiledClassMethodInHierarchy("System", selector):
      return compiledSystemArguments()
    if receiver.classVal.name == "Json" and args.len == 1 and
       not hasCompiledClassMethodInHierarchy("Json", selector):
      case selector
      of "buildDynamic:": return compiledJsonBuildDynamic(args[0])
      of "stringify:": return compiledJsonStringify(args[0])
      else: discard
    if receiver.classVal.name == "Log" and args.len == 1 and
       not hasCompiledClassMethodInHierarchy("Log", selector):
      case selector
      of "debug:": return writeHardingLog(logging.lvlDebug, args[0])
      of "info:": return writeHardingLog(logging.lvlInfo, args[0])
      of "warn:": return writeHardingLog(logging.lvlWarn, args[0])
      of "error:": return writeHardingLog(logging.lvlError, args[0])
      of "fatal:": return writeHardingLog(logging.lvlFatal, args[0])
      else: discard
    if selector == "respondsTo:" and args.len >= 1:
      var querySelector = ""
      if args[0].kind == vkSymbol:
        querySelector = args[0].symVal
      elif args[0].kind == vkString:
        querySelector = args[0].strVal
      let found = querySelector.len > 0 and
        (hasCompiledClassMethodInHierarchy(receiver.classVal.name, querySelector) or
         hasCompiledMethodInHierarchy(receiver.classVal.name, querySelector) or
         (querySelector == "new" and receiver.classVal.name in compiledAllocators))
      return NodeValue(kind: vkBool, boolVal: found)
    return dispatchCompiledClassMethod(receiver, receiver.classVal.name, selector, args)

  let receiverClassName = getReceiverClassName(receiver)
  if receiverClassName.len > 0 and hasCompiledMethodInHierarchy(receiverClassName, selector):
    return dispatchCompiledMethodFromClass(receiver, receiverClassName, selector, args)

  case selector
  of "class":
    if args.len == 0 and receiverClassName.len > 0:
      return compiledClassValue(receiverClassName)
    return compiledMissingMessage(receiver, selector)
  of "className":
    if args.len == 0 and receiverClassName.len > 0:
      return toValue(receiverClassName)
    return compiledMissingMessage(receiver, selector)
  of "superclassNames":
    if args.len == 0 and receiverClassName.len > 0:
      var names: seq[NodeValue] = @[]
      for parent in getSuperclasses(receiverClassName):
        names.add(toValue(parent))
      return NodeValue(kind: vkArray, arrayVal: names)
    return compiledMissingMessage(receiver, selector)
  of "isKindOf:":
    if args.len == 1 and args[0].kind == vkClass and args[0].classVal != nil and
       receiverClassName.len > 0:
      let targetName = args[0].classVal.name
      let owner = walkCompiledHierarchy(receiverClassName,
        proc(name: string): bool = name == targetName)
      return toValue(owner.len > 0)
    return toValue(false)
  of "perform:", "perform:with:", "perform:with:with:":
    # Dynamic send: the selector argument (symbol or string) names the method to
    # run on this receiver, with the remaining arguments as its arguments.
    if args.len < 1:
      return NodeValue(kind: vkNil)
    var dynSelector = ""
    if args[0].kind == vkSymbol:
      dynSelector = args[0].symVal
    elif args[0].kind == vkString:
      dynSelector = args[0].strVal
    else:
      return NodeValue(kind: vkNil)
    var dynArgs: seq[NodeValue] = @[]
    for i in 1..<args.len:
      dynArgs.add(args[i])
    return sendMessage(runtime, receiver, dynSelector, dynArgs)

  of "respondsTo:":
    if args.len < 1:
      return NodeValue(kind: vkBool, boolVal: false)
    var querySelector = ""
    if args[0].kind == vkSymbol:
      querySelector = args[0].symVal
    elif args[0].kind == vkString:
      querySelector = args[0].strVal
    if querySelector.len == 0:
      return NodeValue(kind: vkBool, boolVal: false)
    let queryName = getReceiverClassName(receiver)
    if queryName.len > 0 and hasCompiledMethodInHierarchy(queryName, querySelector):
      return NodeValue(kind: vkBool, boolVal: true)
    if receiver.kind == vkClass and receiver.classVal != nil:
      return NodeValue(kind: vkBool, boolVal: hasCompiledClassMethodInHierarchy(receiver.classVal.name, querySelector))
    return NodeValue(kind: vkBool, boolVal: false)

  of "asInteger", "asFloat", "asNumber":
    if receiver.kind == vkString and args.len == 0:
      case selector
      of "asInteger": return stringAsInteger(receiver.strVal)
      of "asFloat": return stringAsFloat(receiver.strVal)
      else: return stringAsNumber(receiver.strVal)
    return compiledMissingMessage(receiver, selector)

  of "isNil":
    return toValue(isNilValue(receiver))
  of "notNil":
    return toValue(not isNilValue(receiver))
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
      of "Set":
        return NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]())
      of "String":
        return NodeValue(kind: vkString, strVal: "")
      else:
        discard
    return NodeValue(kind: vkNil)

  of "new:":
    if receiver.kind == vkSymbol and args.len > 0:
      let size = if args[0].kind == vkInt: args[0].intVal else: -1
      let isInt = args[0].kind == vkInt
      case receiver.symVal
      of "Array":
        if isInt and size >= 0:
          var elements = newSeq[NodeValue](size)
          for i in 0..<size:
            elements[i] = NodeValue(kind: vkNil)
          return NodeValue(kind: vkArray, arrayVal: elements)
      of "String":
        if isInt and size >= 0:
          return NodeValue(kind: vkString, strVal: "")
      else:
        discard
    return NodeValue(kind: vkNil)

  of "new:withAll:":
    if receiver.kind == vkSymbol and args.len >= 2 and args[0].kind == vkInt and args[0].intVal >= 0:
      case receiver.symVal
      of "Array":
        var elements = newSeq[NodeValue](args[0].intVal)
        for i in 0..<args[0].intVal:
          elements[i] = args[1]
        return NodeValue(kind: vkArray, arrayVal: elements)
      else:
        discard
    return NodeValue(kind: vkNil)

  of "add:":
    if receiver.kind == vkArray and args.len > 0:
      var arr = receiver.arrayVal
      arr.add(args[0])
      return NodeValue(kind: vkArray, arrayVal: arr)
    if receiver.kind == vkTable and args.len > 0:
      # Tables back compiled Set values: the element is both key and value, so
      # repeated adds are naturally deduplicated.
      var tbl = receiver.tableVal
      tbl[args[0]] = args[0]
      return NodeValue(kind: vkTable, tableVal: tbl)
    return NodeValue(kind: vkNil)

  of "includes:":
    if args.len > 0:
      if receiver.kind == vkArray:
        for element in receiver.arrayVal:
          if element == args[0]:
            return NodeValue(kind: vkBool, boolVal: true)
        return NodeValue(kind: vkBool, boolVal: false)
      if receiver.kind == vkTable:
        return NodeValue(kind: vkBool, boolVal: receiver.tableVal.hasKey(args[0]))
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

  of "withIndexDo:":
    if receiver.kind == vkArray and args.len == 1:
      let size = receiver.arrayVal.len
      for index in 0..<size:
        discard sendMessage(runtime, args[0], "value:value:",
                            @[receiver.arrayVal[index], toValue(index)])
      return receiver
    return compiledMissingMessage(receiver, selector)

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

  of "ifNil:", "ifNotNil:", "ifNil:ifNotNil:", "ifNotNil:ifNil:":
    let arity = if selector in ["ifNil:", "ifNotNil:"]: 1 else: 2
    if args.len != arity:
      return compiledMissingMessage(receiver, selector)
    let absent = isTruthy(sendMessage(runtime, receiver, "isNil", @[]))
    case selector
    of "ifNil:":
      if absent:
        return sendMessage(runtime, args[0], "value", @[])
      return receiver
    of "ifNotNil:":
      if absent:
        return NodeValue(kind: vkNil)
      return sendMessage(runtime, args[0], "value:", @[receiver])
    of "ifNil:ifNotNil:":
      if absent:
        return sendMessage(runtime, args[0], "value", @[])
      return sendMessage(runtime, args[1], "value:", @[receiver])
    else:
      if absent:
        return sendMessage(runtime, args[1], "value", @[])
      return sendMessage(runtime, args[0], "value:", @[receiver])

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
    if receiverClassName.len > 0:
      return dispatchCompiledMethodFromClass(receiver, receiverClassName, selector, args)
    return compiledMissingMessage(receiver, selector)

proc sendMessageCached*(runtime: Runtime, receiver: NodeValue, selector: string,
                        args: seq[NodeValue], cache: var CompiledSendCache): NodeValue =
  ## Positive monomorphic cache for registered instance methods only. Builtins,
  ## class-side sends and exception protocols retain the generic runtime path.
  if selector in ["message", "signal", "defaultAction", "retry", "pass", "==", "~="]:
    return sendMessage(runtime, receiver, selector, args)
  let className = getReceiverClassName(receiver)
  if className.len > 0:
    if cache.version == compiledClassDispatchVersion and cache.className == className and
       cache.selector == selector and cache.target != nil:
      let target = cache.target
      return target(receiver, args)
    let owner = walkCompiledHierarchy(className,
      proc(name: string): bool = findCompiledMethod(name, selector) != nil)
    if owner.len > 0:
      let target = findCompiledMethod(owner, selector)
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
