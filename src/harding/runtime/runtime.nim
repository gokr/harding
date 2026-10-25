import std/[tables, strformat, os, strutils, logging, json, options, sets]
import ../interpreter/objects
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
proc getSuperclasses*(className: string): seq[string]
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
    currentRuntime = cast[ptr Runtime](allocShared0(sizeof(Runtime)))
    currentRuntime[] = newRuntime()

proc shutdownRuntime*() =
  ## Shutdown and cleanup runtime
  if currentRuntime != nil:
    # Clean up classes
    currentRuntime.classes.clear()
    currentRuntime.methodCache.clear()
    currentRuntime[] = nil
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
var sealedCompiledClasses = initHashSet[string]()

proc requireMutableCompiledClass*(name: string) =
  ## Full native artifacts reject registry mutation after initialization.
  if name in sealedCompiledClasses:
    raise newException(ValueError, "Frozen native class is sealed: " & name)

proc sealCompiledClass*(name: string) =
  ## Seal native registration only; does not alter any live interpreter class.
  sealedCompiledClasses.incl(name)

proc registerCompiledClass*(name: string, allocator: CompiledProc) =
  ## Register a class receiver and its native allocator.
  requireMutableCompiledClass(name)
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
  if "Root" notin getSuperclasses("Object"): registerSuperclass("Object", "Root")
  if "Root" notin getSuperclasses("Mixin"): registerSuperclass("Mixin", "Root")
  return compiledClassValue(name)

proc compiledSystemClassValue*(): NodeValue =
  ## Canonical System receiver for native process-level services.
  if "System" notin compiledClasses:
    compiledClasses["System"] = newClass(name = "System")
  return compiledClassValue("System")

proc compiledArray*(elements: seq[NodeValue]): NodeValue =
  ## Retain mutable Array storage across assignments and message boundaries.
  if "Array" notin compiledClasses:
    compiledClasses["Array"] = newClass(name = "Array")
  NodeValue(kind: vkInstance, instVal: Instance(kind: ikArray,
    class: compiledClasses["Array"], elements: elements))

proc compiledTable*(entries: Table[NodeValue, NodeValue]): NodeValue =
  ## Retain mutable Table storage across assignments and message boundaries.
  if "Table" notin compiledClasses:
    compiledClasses["Table"] = newClass(name = "Table")
  NodeValue(kind: vkInstance, instVal: Instance(kind: ikTable,
    class: compiledClasses["Table"], entries: entries))

proc compiledArrayElements*(value: NodeValue): seq[NodeValue] =
  ## Read elements without copying the Harding collection identity.
  if value.kind == vkInstance and value.instVal != nil and value.instVal.kind == ikArray:
    return value.instVal.elements
  if value.kind == vkArray:
    return value.arrayVal
  raise newException(ValueError, "Expected Array")

proc compiledSequence*(value: NodeValue): seq[NodeValue] =
  ## Elements of a reference-backed Array or Table-as-Set, or a raw Array view.
  ## Table elements are its values: Set stores each element as key and value.
  if value.kind == vkInstance and value.instVal != nil:
    case value.instVal.kind
    of ikArray: return value.instVal.elements
    of ikTable:
      if value.instVal.class != nil and value.instVal.class.name == "Set":
        for entry in value.instVal.entries.values: result.add(entry)
        return result
    else: discard
    raise newException(ValueError, "Expected a sequence collection")
  if value.kind == vkArray: return value.arrayVal
  raise newException(ValueError, "Expected a sequence collection")

proc compiledSameSpecies*(source: NodeValue, elements: seq[NodeValue]): NodeValue =
  ## Rebuild a collection of the source's species from copied elements.
  if source.kind == vkInstance and source.instVal != nil and
     source.instVal.kind == ikTable:
    var entries = initTable[NodeValue, NodeValue]()
    for element in elements: entries[element] = element
    result = compiledTable(entries)
    result.instVal.class = source.instVal.class
    return
  compiledArray(elements)

proc compiledSystemArguments*(): NodeValue =
  ## Snapshot user arguments, excluding the executable name, as Harding strings.
  var elements: seq[NodeValue] = @[]
  for argument in commandLineParams():
    elements.add(toValue(argument))
  return compiledArray(elements)

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

proc compiledJsonParse*(value: NodeValue): NodeValue =
  ## Parse JSON text into native Harding scalars and collections; failures answer nil.
  if value.kind != vkString:
    return nilValue()

  proc toHarding(node: JsonNode): NodeValue =
    case node.kind
    of JObject:
      var entries = initTable[NodeValue, NodeValue]()
      for key, entry in node.pairs:
        entries[toValue(key)] = toHarding(entry)
      result = compiledTable(entries)
    of JArray:
      var elements: seq[NodeValue]
      for element in node.items:
        elements.add(toHarding(element))
      result = compiledArray(elements)
    of JString:
      result = toValue(node.getStr())
    of JInt:
      result = toValue(node.getInt())
    of JFloat:
      result = toValue(node.getFloat())
    of JBool:
      result = toValue(node.getBool())
    of JNull:
      result = nilValue()

  try:
    result = toHarding(parseJson(value.strVal))
  except CatchableError:
    result = nilValue()

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

var compiledSlotNames = initTable[string, seq[string]]()

proc registerCompiledSlotNames*(name: string, slots: seq[string]) =
  ## Preserve parser-defined parent-first layout independently of accessor permissions.
  requireMutableCompiledClass(name)
  compiledSlotNames[name] = slots
  if name notin compiledClasses:
    compiledClasses[name] = newClass(name = name)
  compiledClasses[name].allSlotNames = slots

proc getSlotValue*(self: NodeValue, slotName: string): NodeValue
proc getReceiverClassName*(receiver: NodeValue): string
proc hasCompiledMethodInHierarchy*(className, selector: string): bool

proc effectiveCompiledJsonSpec(name: string, target: JsonSpec) =
  for parent in getSuperclasses(name):
    effectiveCompiledJsonSpec(parent, target)
  if name notin compiledClasses or compiledClasses[name].jsonSpec == nil:
    return
  let spec = compiledClasses[name].jsonSpec
  for entry in spec.excludedSlots:
    if entry notin target.excludedSlots: target.excludedSlots.add(entry)
  for entry in spec.omitNilSlots:
    if entry notin target.omitNilSlots: target.omitNilSlots.add(entry)
  for entry in spec.omitEmptySlots:
    if entry notin target.omitEmptySlots: target.omitEmptySlots.add(entry)
  if spec.includedOnly.isSome: target.includedOnly = spec.includedOnly
  for key, value in spec.renamedSlots: target.renamedSlots[key] = value
  for key, value in spec.slotFormats: target.slotFormats[key] = value
  if spec.fieldOrder.len > 0: target.fieldOrder = spec.fieldOrder

proc compiledJsonEmpty(value: NodeValue): bool =
  case value.kind
  of vkString: value.strVal.len == 0
  of vkArray: value.arrayVal.len == 0
  of vkTable: value.tableVal.len == 0
  of vkInstance:
    if value.instVal == nil: return false
    case value.instVal.kind
    of ikArray: value.instVal.elements.len == 0
    of ikTable: value.instVal.entries.len == 0
    of ikString: value.instVal.strVal.len == 0
    else: false
  else: false

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
      # Compare retained native identity as wrappers can differ for one owner.
      for prior in visited:
        if prior == value.instVal or (prior.compiledOwner != nil and
           prior.compiledOwner == value.instVal.compiledOwner):
          raise newException(ValueError, "JSON serialization cycle detected")
      visited.add(value.instVal)
      let name = getReceiverClassName(value)
      if hasCompiledMethodInHierarchy(name, "jsonRepresentation"):
        compiledJsonValue(buf, sendMessage(currentRuntime[], value,
                          "jsonRepresentation", @[]), visited)
      else:
        let spec = JsonSpec(renamedSlots: initTable[string, string](),
                            slotFormats: initTable[string, JsonFormatKind]())
        effectiveCompiledJsonSpec(name, spec)
        var names: seq[string]
        let slots = compiledSlotNames.getOrDefault(name)
        for field in spec.fieldOrder:
          if field in slots and field notin names: names.add(field)
        for field in slots:
          if field notin names: names.add(field)
        buf.add '{'
        var first = true
        for field in names:
          if field in spec.excludedSlots or
             (spec.includedOnly.isSome and field notin spec.includedOnly.get):
            continue
          let entry = getSlotValue(value, field)
          if field in spec.omitNilSlots and isNilValue(entry): continue
          if field in spec.omitEmptySlots and compiledJsonEmpty(entry): continue
          if not first: buf.add ','
          first = false
          compiledJsonEscape(buf, spec.renamedSlots.getOrDefault(field, field))
          buf.add ':'
          case spec.slotFormats.getOrDefault(field, jfkNone)
          of jfkNone: compiledJsonValue(buf, entry, visited)
          of jfkRawJson:
            if entry.kind == vkString: buf.add entry.strVal
            else: compiledJsonEscape(buf, entry.toString())
          of jfkClassName:
            if entry.kind == vkClass: compiledJsonEscape(buf, entry.classVal.name)
            elif entry.kind == vkInstance and entry.instVal.class != nil:
              compiledJsonEscape(buf, entry.instVal.class.name)
            else: compiledJsonEscape(buf, entry.toString())
          of jfkString, jfkSymbolName: compiledJsonEscape(buf, entry.toString())
        buf.add '}'
      leaveJsonInstance(visited)
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
  requireMutableCompiledClass(className)
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
  requireMutableCompiledClass(className)
  let key = className & "::" & slotName
  slotGetters[key] = getter
  slotSetters[key] = setter

proc registerCompiledMethod*(className: string, selector: string,
                              fn: proc(self: NodeValue, args: seq[NodeValue]): NodeValue) =
  requireMutableCompiledClass(className)
  let key = className & ">>" & selector
  compiledMethodProcs[key] = fn
  inc compiledClassDispatchVersion

# Interpreted-to-compiled dispatch
################################
#
# A compiled method must also be reachable from interpreted code: a Workspace
# Do It or a subclass created at runtime sends to a compiled class. Each compiled
# method gets a generated shim proc whose class/selector are baked in, bound onto
# the interpreter's own method table as a native implementation. Generating one
# shim per method (instead of one generic adapter) keeps the identity static and
# mirrors how generated modules already emit per-class slot accessor procs.

type
  BoundShimState = object
    currentMethod: BlockNode
    nativePointer: pointer
    primitiveSelector: string
    hasInterpreterParam: bool
    classSide: bool
  BoundCompiledClass = object
    interpreter: Interpreter
    methods: Table[string, BlockNode]
    classMethods: Table[string, BlockNode]
    originals: seq[BoundShimState]

var boundCompiledClasses = initTable[Class, BoundCompiledClass]()

proc sendMessageInterpreted*(interp: var Interpreter, receiver: NodeValue,
                             selector: string, args: seq[NodeValue]): NodeValue =
  ## Send actual values through the non-fatal host callback boundary.
  ## Native-layout proxies must explicitly opt in through bindNativeInstanceTo.
  if receiver.kind == vkInstance and receiver.instVal != nil and
     receiver.instVal.isNimProxy and receiver.instVal.nimValue != nil:
    if receiver.instVal.nativeSlots == nil:
      raise newException(ValueError, "Interpreted sends require an explicit native slot binding")
    receiver.instVal.validateNativeSlots()
  var arguments: seq[Node]
  for argument in args:
    arguments.add(LiteralNode(value: argument))
  let message = MessageNode(receiver: LiteralNode(value: receiver),
                            selector: selector, arguments: arguments)
  result = evalCallbackNonFatal(interp, message)

proc boundClassFor(receiver: NodeValue): Class =
  if boundCompiledClasses.len == 0:
    return nil
  let cls = if receiver.kind == vkClass: receiver.classVal
            elif receiver.kind == vkInstance and receiver.instVal != nil: receiver.instVal.class
            else: nil
  # Find the host through live class identity, not the compiled name registry.
  var visited: seq[Class]
  proc findBinding(current: Class): Class =
    if current == nil or current in visited: return nil
    visited.add(current)
    if current in boundCompiledClasses: return current
    for parent in current.superclasses:
      let found = findBinding(parent)
      if found != nil: return found
  result = findBinding(cls)

proc boundGlobalValue*(ownerReceiver: NodeValue, name: string): tuple[handled: bool, value: NodeValue] =
  ## Resolve a lexical global through isolated host lookup, including libraries.
  ## A bound missing/nil binding is not a request to use the native globals table.
  let owner = boundClassFor(ownerReceiver)
  if owner == nil:
    return
  var interp = boundCompiledClasses[owner].interpreter
  result.value = evalCallbackNonFatal(interp, IdentNode(name: name, localIndex: -1))
  result.handled = true

proc boundGlobalWrite*(ownerReceiver: NodeValue, name: string,
                       value: NodeValue): tuple[handled: bool, value: NodeValue] =
  ## Assign via a fresh VM block activation: imported bindings and protected
  ## globals use exactly the interpreter's ordinary assignment path.
  let owner = boundClassFor(ownerReceiver)
  if owner == nil:
    return
  var interp = boundCompiledClasses[owner].interpreter
  let assignment = AssignNode(variable: name, expression: LiteralNode(value: value), localIndex: -1)
  let body = BlockNode(body: @[Node(assignment)])
  let message = MessageNode(receiver: LiteralNode(value: NodeValue(kind: vkBlock, blockVal: body)),
                            selector: "value")
  result.value = evalCallbackNonFatal(interp, message)
  result.handled = true

proc hostedBuiltin*(ownerReceiver, receiver: NodeValue, selector: string,
                    args: seq[NodeValue]): tuple[handled: bool, value: NodeValue] =
  ## Builtin helper sends in bound code must honor the calling method's host.
  ## Only interpreter-owned receivers are routed: native primitives keep the
  ## fast helpers, and an unbound (pure compiled) call keeps native dispatch.
  if receiver.kind != vkInstance or receiver.instVal == nil:
    return
  let instance = receiver.instVal
  if selector in ["==", "~="]:
    return
  if instance.isNimProxy and instance.nativeSlots == nil:
    return
  if instance.kind in {ikArray, ikTable} and instance.class != nil and
     instance.class.name in compiledClasses and
     compiledClasses[instance.class.name] == instance.class:
    return
  let owner = boundClassFor(ownerReceiver)
  if owner == nil:
    return
  var interp = boundCompiledClasses[owner].interpreter
  result.value = sendMessageInterpreted(interp, receiver, selector, args)
  result.handled = true

proc sendMessageBound*(ownerReceiver, receiver: NodeValue, selector: string,
                       args: seq[NodeValue]): NodeValue =
  ## Ordinary sends from bound code use live host lookup for VM-owned receivers.
  let hosted = hostedBuiltin(ownerReceiver, receiver, selector, args)
  if hosted.handled:
    return hosted.value
  let owner = boundClassFor(ownerReceiver)
  if owner != nil and receiver.kind == vkClass:
    var interp = boundCompiledClasses[owner].interpreter
    return sendMessageInterpreted(interp, receiver, selector, args)
  initRuntime()
  result = sendMessage(currentRuntime[], receiver, selector, args)

proc boundNewInstance*(ownerReceiver: NodeValue, className: string): tuple[handled: bool, value: NodeValue] =
  ## Host-bound code allocates through the live class's ordinary new protocol.
  ## Unbound/native code keeps the caller's native allocator path.
  let owner = boundClassFor(ownerReceiver)
  if owner == nil:
    return
  var interp = boundCompiledClasses[owner].interpreter
  let target = boundGlobalValue(ownerReceiver, className).value
  if target.kind != vkClass or target.classVal == nil:
    raise newException(ValueError, "Bound allocation requires a live class: " & className)
  result.value = sendMessageInterpreted(interp, target, "new", @[])
  result.handled = true

proc boundInterpretedSend(receiver: NodeValue, selector: string,
                          args: seq[NodeValue]): tuple[handled: bool, value: NodeValue] =
  let owner = boundClassFor(receiver)
  if owner == nil:
    return
  let classSide = receiver.kind == vkClass
  let cls = if classSide: receiver.classVal else: receiver.instVal.class
  let binding = boundCompiledClasses[owner]
  let resolved = if classSide: vm.lookupClassMethod(cls, selector).currentMethod
                 else: lookupInstanceMethod(cls, selector)
  # A bound shim remains native. Replacements and subclass overrides go through
  # the VM even after a compiled cache has warmed.
  if cls == owner:
    if classSide:
      if selector in binding.classMethods and binding.classMethods[selector] == resolved:
        return
    elif selector in binding.methods and binding.methods[selector] == resolved:
      return
  var interp = binding.interpreter
  result.value = sendMessageInterpreted(interp, receiver, selector, args)
  result.handled = true

proc bindCompiledMethodShim*(interp: var Interpreter, className, selector: string,
                             shim: pointer, isClassMethod: bool = false): bool =
  ## Bind an instance (Instance receiver) or class-side (NodeValue receiver) shim.
  ## Both signatures include the interpreter and use the nimcall convention.
  ##
  ## Answers false when the interpreter does not know the class or method, or when
  ## the method already has a native implementation. A hand-written or
  ## interpreter-registered primitive therefore keeps precedence over generated
  ## code.
  if interp.globals == nil or shim == nil:
    return false
  if className notin interp.globals[]:
    return false
  let classValue = interp.globals[][className]
  if classValue.kind != vkClass or classValue.classVal == nil:
    return false
  let cls = classValue.classVal
  let declared = if isClassMethod: cls.classMethods else: cls.methods
  if selector notin declared:
    return false
  let boundMethod = declared[selector]
  if boundMethod == nil or boundMethod.nativeImpl != nil or
     boundMethod.nativeValueImpl != nil:
    return false
  var binding = boundCompiledClasses.getOrDefault(cls)
  if binding.interpreter != nil and binding.interpreter != interp:
    raise newException(ValueError, "Compiled class is already bound to another interpreter")
  binding.originals.add(BoundShimState(currentMethod: boundMethod, nativePointer: shim,
    primitiveSelector: boundMethod.primitiveSelector,
    hasInterpreterParam: boundMethod.hasInterpreterParam, classSide: isClassMethod))
  boundMethod.primitiveSelector = selector
  if isClassMethod:
    boundMethod.setNativeValueImpl(shim)
  else:
    boundMethod.setNativeImpl(shim)
  boundMethod.hasInterpreterParam = true
  binding.interpreter = interp
  if isClassMethod:
    binding.classMethods[selector] = boundMethod
  else:
    binding.methods[selector] = boundMethod
  boundCompiledClasses[cls] = binding
  inc compiledClassDispatchVersion
  return true

proc unbindCompiledMethodsFrom*(interp: Interpreter) =
  ## Restore only our own shim metadata before releasing interpreter ownership.
  var classes: seq[Class]
  for cls, binding in boundCompiledClasses:
    if binding.interpreter != interp: continue
    for original in binding.originals:
      let currentMethod = original.currentMethod
      if original.classSide:
        if currentMethod.nativeValueImpl != original.nativePointer: continue
        currentMethod.nativeValueImpl = nil
      else:
        if currentMethod.nativeImpl != original.nativePointer: continue
        currentMethod.nativeImpl = nil
      currentMethod.primitiveSelector = original.primitiveSelector
      currentMethod.hasInterpreterParam = original.hasInterpreterParam
    classes.add(cls)
  for cls in classes:
    boundCompiledClasses.del(cls)
  if classes.len > 0: inc compiledClassDispatchVersion

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
  requireMutableCompiledClass(className)
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
  if "Exception" notin superclassLists: registerSuperclass("Exception", "")
  if "Exception" notin getSuperclasses("Error"): registerSuperclass("Error", "Exception")
  if "Exception" notin getSuperclasses("Notification"): registerSuperclass("Notification", "Exception")
  for name in ["DivisionByZero", "MessageNotUnderstood", "SubscriptOutOfBounds",
               "BlockCannotReturn"]:
    if "Error" notin getSuperclasses(name): registerSuperclass(name, "Error")

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

proc bindNativeInstanceTo*(interp: Interpreter, receiver: NodeValue): bool =
  ## Attach live class identity and a checked native slot bridge, without copying
  ## fields or retaining the interpreter. Unknown/incompatible layouts are refused.
  if interp == nil or interp.globals == nil or receiver.kind != vkInstance or
     receiver.instVal == nil:
    return false
  let instance = receiver.instVal
  if instance.kind != ikObject or not instance.isNimProxy or
     instance.compiledOwner == nil or instance.nimValue == nil or instance.class == nil:
    return false
  let name = instance.class.name
  if name notin compiledSlotNames or name notin interp.globals[]:
    return false
  let liveValue = interp.globals[][name]
  if liveValue.kind != vkClass or liveValue.classVal == nil or
     liveValue.classVal.allSlotNames != compiledSlotNames[name]:
    return false
  var binding = boundCompiledClasses.getOrDefault(liveValue.classVal)
  if binding.interpreter != nil and binding.interpreter != interp:
    raise newException(ValueError, "Native class is already bound to another interpreter")
  if instance.nativeSlots != nil:
    instance.validateNativeSlots()
    if instance.class != liveValue.classVal:
      return false
    binding.interpreter = interp
    boundCompiledClasses[instance.class] = binding
    return true
  let storage = NativeSlotStorage()
  for slot in compiledSlotNames[name]:
    let key = name & "::" & slot
    if key notin slotGetters or key notin slotSetters:
      return false
    storage.names.add(slot)
    storage.getters.add(slotGetters[key])
    storage.setters.add(slotSetters[key])
  # Publish only after all validation succeeds.
  instance.class = liveValue.classVal
  instance.nativeSlots = storage
  binding.interpreter = interp
  boundCompiledClasses[instance.class] = binding
  return true

proc getSlotValue*(self: NodeValue, slotName: string): NodeValue =
  ## Read the receiver's storage without assuming a native or interpreted layout.
  if self.kind != vkInstance or self.instVal == nil or self.instVal.kind != ikObject:
    return nilValue()
  let instance = self.instVal
  if instance.nativeSlots != nil:
    instance.validateNativeSlots()
    return instance.readInstanceSlot(instance.class.getSlotIndex(slotName))
  if not instance.isNimProxy:
    if instance.class != nil:
      let index = instance.class.getSlotIndex(slotName)
      if index >= 0 and index < instance.slots.len:
        return instance.slots[index]
    return nilValue()
  if instance.nimValue == nil:
    return nilValue()
  let key = getReceiverClassName(self) & "::" & slotName
  if key in slotGetters:
    return slotGetters[key](instance.nimValue)
  return nilValue()

proc setSlotValue*(self: NodeValue, slotName: string, value: NodeValue): NodeValue =
  ## Write through the receiver's own layout; never cast VM-owned slot storage.
  if self.kind != vkInstance or self.instVal == nil or self.instVal.kind != ikObject:
    return value
  let instance = self.instVal
  if instance.nativeSlots != nil:
    instance.validateNativeSlots()
    instance.writeInstanceSlot(instance.class.getSlotIndex(slotName), value)
    return value
  if not instance.isNimProxy:
    if instance.class != nil:
      let index = instance.class.getSlotIndex(slotName)
      if index >= 0 and index < instance.slots.len:
        instance.slots[index] = value
    return value
  if instance.nimValue == nil:
    return value
  let key = getReceiverClassName(self) & "::" & slotName
  if key in slotSetters:
    return slotSetters[key](instance.nimValue, value)
  return value

proc compiledErrorValue*(name, message: string): NodeValue
proc raiseCompiledError*(value: NodeValue): NodeValue

proc compiledNamedAccess*(receiver: NodeValue, name: string,
                          value: NodeValue = NodeValue(kind: vkNil),
                          isAssignment: bool = false): NodeValue =
  ## Named slot access is distinct from at:, including visibility checks.
  if receiver.kind == vkInstance and receiver.instVal != nil:
    let instance = receiver.instVal
    if instance.kind == ikObject and instance.class != nil and
       instance.class.getSlotIndex(name) >= 0:
      let permitted = if isAssignment: name in instance.class.writableSlotNames
                      else: name in instance.class.readableSlotNames
      if not permitted:
        return raiseCompiledError(compiledErrorValue("Error", "Named access to private slot: " & name))
      if isAssignment: return setSlotValue(receiver, name, value)
      return getSlotValue(receiver, name)
    if instance.kind == ikTable:
      let symbol = toSymbol(name)
      let key = if instance.entries.hasKey(symbol): symbol else: toValue(name)
      if isAssignment:
        instance.entries[key] = value
        return value
      return instance.entries.getOrDefault(key, nilValue())
  return nilValue()

proc dispatchCompiledMethodFromClass*(receiver: NodeValue, className: string,
                                      selector: string, args: seq[NodeValue]): NodeValue =
  ## Dispatch compiled method by walking class -> superclass graph in declaration
  ## order, so multiple parents follow the interpreter's lookup order.
  if className == getReceiverClassName(receiver):
    let interpreted = boundInterpretedSend(receiver, selector, args)
    if interpreted.handled:
      return interpreted.value
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

proc implementsPerform(receiver: NodeValue, receiverClassName, selector: string): bool =
  ## True when a compiled user method implements this `perform:` selector for the
  ## receiver, in which case the builtin table must not convey the send itself.
  if receiver.kind == vkClass and receiver.classVal != nil:
    return hasCompiledClassMethodInHierarchy(receiver.classVal.name, selector)
  return receiverClassName.len > 0 and
         hasCompiledMethodInHierarchy(receiverClassName, selector)

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
  if selector in ["new", "basicNew"] and receiver.kind == vkClass and receiver.classVal != nil:
    let name = receiver.classVal.name
    if name in compiledAllocators:
      if selector == "basicNew":
        return compiledAllocators[name](receiver, @[])
      return compiledNewInstance(name, compiledAllocators[name])
  return compiledMissingMessage(receiver, selector)

proc sendSuperMessage*(receiver: NodeValue, definingClassName: string,
                       selector: string, args: seq[NodeValue],
                       explicitParent: string = ""): NodeValue =
  ## Keep the receiver and start lookup at a direct parent of the declaring class.
  ## An explicit qualifier must name one of that class's direct parents.
  let boundOwner = boundClassFor(receiver)
  if boundOwner != nil:
    let receiverClass = if receiver.kind == vkClass: receiver.classVal else: receiver.instVal.class
    var visited: seq[Class]
    proc findDefinition(cls: Class): Class =
      if cls == nil or cls in visited: return nil
      visited.add(cls)
      if cls.name == definingClassName: return cls
      for parent in cls.superclasses:
        let found = findDefinition(parent)
        if found != nil: return found
    let definition = findDefinition(receiverClass)
    if definition == nil:
      raise newException(ValueError, "Super send defining class is absent from live receiver hierarchy: " & definingClassName)
    if receiver.kind == vkInstance and receiver.instVal.isNimProxy and
       receiver.instVal.nativeSlots == nil:
      raise newException(ValueError, "Super sends require an explicit native slot binding")
    var interp = boundCompiledClasses[boundOwner].interpreter
    return evalSuperCallbackNonFatal(interp, receiver, definition, selector, args, explicitParent)
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

proc invokeCompiledBlock*(blk: BlockNode, args: seq[NodeValue]): NodeValue

proc evalBlock*(runtime: Runtime, blk: BlockNode,
                args: seq[NodeValue] = @[]): NodeValue =
  ## Evaluate native blocks used by compiled control-flow helpers.
  if blk != nil and blk.nativeImpl != nil:
    return invokeCompiledBlock(blk, args)
  return nilValue()

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

proc invokeCompiledBlock*(blk: BlockNode, args: seq[NodeValue]): NodeValue =
  ## Shared native block ABI for the native runtime and VM callback boundary.
  if blk == nil or blk.nativeImpl == nil:
    raise newException(ValueError, "Compiled block has no native implementation")
  if args.len != blk.parameters.len:
    raise newException(ValueError, "Wrong number of arguments to block: expected " &
      $blk.parameters.len & ", got " & $args.len)
  let env = getBlockEnvPtr(blk)
  case args.len
  of 0:
    if env != nil: return cast[BlockEnvProc0](blk.nativeImpl)(env)
    return cast[BlockProc0](blk.nativeImpl)()
  of 1:
    if env != nil: return cast[BlockEnvProc1](blk.nativeImpl)(env, args[0])
    return cast[BlockProc1](blk.nativeImpl)(args[0])
  of 2:
    if env != nil: return cast[BlockEnvProc2](blk.nativeImpl)(env, args[0], args[1])
    return cast[BlockProc2](blk.nativeImpl)(args[0], args[1])
  of 3:
    if env != nil: return cast[BlockEnvProc3](blk.nativeImpl)(env, args[0], args[1], args[2])
    return cast[BlockProc3](blk.nativeImpl)(args[0], args[1], args[2])
  else:
    raise newException(ValueError, "Compiled block calls support at most three arguments")

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

  if selector notin ["==", "~="]:
    let interpreted = boundInterpretedSend(receiver, selector, args)
    if interpreted.handled: return interpreted.value

  if receiver.kind == vkInstance and receiver.instVal != nil and
     receiver.instVal.kind in {ikArray, ikTable}:
    let storage = receiver.instVal
    case selector
    of "add:":
      if args.len == 1:
        if storage.kind == ikArray:
          storage.elements.add(args[0])
        else:
          storage.entries[args[0]] = args[0]
        return receiver
    of "at:put:":
      if args.len == 2:
        if storage.kind == ikTable:
          storage.entries[args[0]] = args[1]
          return args[1]
        if args[0].kind == vkInt:
          let index = args[0].intVal
          if index >= 0 and index < storage.elements.len:
            storage.elements[index] = args[1]
            return args[1]
          return args[1]
    of "class": return toValue(storage.class)
    of "className": return toValue(storage.class.name)
    of "isKindOf:":
      if args.len == 1:
        let target = if args[0].kind == vkClass: args[0].classVal.name
                     elif args[0].kind == vkSymbol: args[0].symVal else: ""
        return toValue(target in [storage.class.name, "Object", "Root"])
    of "=":
      if args.len == 1: return toValue(compiledIdentityEqual(receiver, args[0]))
    of "asArray":
      if storage.kind == ikArray: return receiver
      var elements: seq[NodeValue]
      for value in storage.entries.values: elements.add(value)
      return compiledArray(elements)
    of "addAll:":
      if args.len == 1:
        for element in compiledSequence(args[0]):
          if storage.kind == ikArray: storage.elements.add(element)
          else: storage.entries[element] = element
        return args[0]
    of "occurrencesOf:":
      if args.len == 1:
        var total = 0
        for value in compiledSequence(receiver):
          if isTruthy(sendMessage(runtime, value, "=", @[args[0]])): inc total
        return toValue(total)
    of "findFirst:", "findLast:":
      if args.len == 1 and storage.kind == ikArray:
        let count = storage.elements.len
        for offset in 0..<count:
          let index = if selector == "findFirst:": offset else: count - 1 - offset
          if isTruthy(sendMessage(runtime, args[0], "value:", @[storage.elements[index]])):
            return toValue(index)
        return nilValue()
    of "reverseDo:":
      if args.len == 1 and storage.kind == ikArray:
        for index in countdown(storage.elements.len - 1, 0):
          discard sendMessage(runtime, args[0], "value:", @[storage.elements[index]])
        return receiver
    of "includesAll:":
      if args.len == 1:
        for wanted in compiledSequence(args[0]):
          var found = false
          for value in compiledSequence(receiver):
            if isTruthy(sendMessage(runtime, value, "=", @[wanted])):
              found = true
              break
          if not found: return toValue(false)
        return toValue(true)
    of "removeAll":
      if storage.kind == ikArray:
        storage.elements.setLen(0)
        return receiver
    of "sorted", "sorted:":
      if storage.kind == ikArray and (selector == "sorted" or args.len == 1):
        var elements = storage.elements
        for i in 1..<elements.len:
          var j = i
          while j > 0:
            let left = elements[j]
            let right = elements[j - 1]
            let before = if selector == "sorted:":
                           sendMessage(runtime, args[0], "value:value:", @[left, right])
                         elif left.kind == vkInt and right.kind == vkInt:
                           toValue(left.intVal < right.intVal)
                         elif left.kind == vkFloat and right.kind == vkFloat:
                           toValue(left.floatVal < right.floatVal)
                         elif left.kind in {vkInt, vkFloat} and right.kind in {vkInt, vkFloat}:
                           toValue((if left.kind == vkInt: float(left.intVal) else: left.floatVal) <
                                   (if right.kind == vkInt: float(right.intVal) else: right.floatVal))
                         elif left.kind == vkString and right.kind == vkString:
                           toValue(left.strVal < right.strVal)
                         elif left.kind == vkBool and right.kind == vkBool:
                           toValue(left.boolVal < right.boolVal)
                         else:
                           sendMessage(runtime, left, "<", @[right])
            if not isTruthy(before): break
            swap(elements[j], elements[j - 1])
            dec j
        return compiledArray(elements)
    of "removeAt:":
      if storage.kind == ikArray and args.len == 1 and args[0].kind == vkInt:
        let index = args[0].intVal
        if index >= 0 and index < storage.elements.len:
          let removed = storage.elements[index]
          storage.elements.delete(index)
          return removed
        return nilValue()
    of "removeLast", "removeFirst":
      if storage.kind == ikArray and storage.elements.len > 0:
        let index = if selector == "removeLast": storage.elements.len - 1 else: 0
        let removed = storage.elements[index]
        storage.elements.delete(index)
        return removed
      return nilValue()
    of "remove:":
      if args.len == 1 and storage.class.name == "Set":
        if storage.entries.hasKey(args[0]): storage.entries.del(args[0])
        return receiver
      return nilValue()
    of "union:", "intersection:", "difference:":
      if args.len == 1 and storage.class.name == "Set":
        var entries = initTable[NodeValue, NodeValue]()
        let other = compiledSequence(args[0])
        case selector
        of "union:":
          for key, value in storage.entries: entries[key] = value
          for value in other: entries[value] = value
        of "intersection:":
          for value in other:
            if storage.entries.hasKey(value): entries[value] = value
        else:
          for key, value in storage.entries: entries[key] = value
          for value in other: entries.del(value)
        result = compiledTable(entries)
        result.instVal.class = storage.class
        return
      return nilValue()
    of "removeKey:":
      if storage.kind == ikTable and storage.class.name == "Table" and args.len == 1:
        if storage.entries.hasKey(args[0]):
          storage.entries.del(args[0])
        return receiver
    of "values":
      if storage.kind == ikTable and storage.class.name == "Table":
        var elements: seq[NodeValue]
        for value in storage.entries.values: elements.add(value)
        return compiledArray(elements)
    of "keys":
      if storage.kind == ikTable and storage.class.name == "Table":
        var elements: seq[NodeValue]
        for key in storage.entries.keys: elements.add(key)
        return compiledArray(elements)
    of "associations":
      if storage.kind == ikTable and storage.class.name == "Table":
        var pairs: seq[NodeValue]
        for key, value in storage.entries:
          pairs.add(compiledArray(@[key, value]))
        return compiledArray(pairs)
    of "at:":
      if args.len == 1:
        if storage.kind == ikArray and args[0].kind == vkInt:
          let index = args[0].intVal
          if index >= 0 and index < storage.elements.len: return storage.elements[index]
        elif storage.kind == ikTable and storage.entries.hasKey(args[0]):
          return storage.entries[args[0]]
        return nilValue()
    of "includes:":
      if storage.kind == ikTable and storage.class.name == "Table" and args.len == 1:
        for value in storage.entries.values:
          if isTruthy(sendMessage(runtime, value, "=", @[args[0]])):
            return toValue(true)
        return toValue(false)
    of "includesKey:":
      if storage.kind == ikTable and args.len == 1:
        return toValue(storage.entries.hasKey(args[0]))
    of "do:", "keysAndValuesDo:", "collect:", "select:", "reject:",
       "detect:", "detect:ifNone:", "inject:into:", "anySatisfy:",
       "allSatisfy:", "noneSatisfy:":
      if storage.kind == ikTable and storage.class.name == "Table":
        var collected: seq[NodeValue]
        var selected = initTable[NodeValue, NodeValue]()
        var accumulator = if selector == "inject:into:" and args.len == 2: args[0] else: nilValue()
        let callback = if selector == "inject:into:" and args.len == 2: args[1]
                       elif args.len > 0: args[0] else: nilValue()
        for key, value in storage.entries:
          let answer = if selector == "inject:into:":
                         sendMessage(runtime, callback, "value:value:value:", @[accumulator, key, value])
                       else:
                         sendMessage(runtime, callback, "value:value:", @[key, value])
          case selector
          of "do:", "keysAndValuesDo:": discard
          of "collect:": collected.add(answer)
          of "inject:into:": accumulator = answer
          of "select:":
            if isTruthy(answer): selected[key] = value
          of "reject:":
            if not isTruthy(answer): selected[key] = value
          of "detect:", "detect:ifNone:":
            if isTruthy(answer): return value
          of "anySatisfy:":
            if isTruthy(answer): return toValue(true)
          of "allSatisfy:", "noneSatisfy:":
            if isTruthy(answer) == (selector == "noneSatisfy:"):
              return toValue(false)
          else: discard
        case selector
        of "do:", "keysAndValuesDo:": return receiver
        of "collect:": return compiledArray(collected)
        of "select:", "reject:": return compiledTable(selected)
        of "inject:into:": return accumulator
        of "detect:ifNone:": return sendMessage(runtime, args[1], "value", @[])
        of "detect:": return nilValue()
        of "anySatisfy:": return toValue(false)
        else: return toValue(true)
    of "clone", "copy":
      if storage.kind == ikArray:
        return compiledArray(storage.elements)
      return compiledTable(storage.entries)
    of "==", "~=":
      if args.len == 1:
        let same = compiledIdentityEqual(receiver, args[0])
        return toValue(if selector == "==": same else: not same)
    else: discard
    if storage.kind == ikTable and storage.class.name == "Set" and
       selector in ["do:", "collect:", "select:", "reject:", "detect:",
                    "detect:ifNone:", "inject:into:", "anySatisfy:",
                    "allSatisfy:", "noneSatisfy:"]:
      var elements: seq[NodeValue]
      for value in storage.entries.values: elements.add(value)
      let answer = sendMessage(runtime, compiledArray(elements), selector, args)
      if selector == "do:": return receiver
      if selector in ["collect:", "select:", "reject:"]:
        var entries = initTable[NodeValue, NodeValue]()
        for value in compiledArrayElements(answer): entries[value] = value
        let collected = compiledTable(entries)
        collected.instVal.class = storage.class
        return collected
      return answer
    # Read-only operations use an ephemeral value view, never a mutable owner.
    let view = if storage.kind == ikArray:
                 NodeValue(kind: vkArray, arrayVal: storage.elements)
               else:
                 NodeValue(kind: vkTable, tableVal: storage.entries)
    let answer = sendMessage(runtime, view, selector, args)
    if selector in ["do:", "withIndexDo:"]:
      return receiver
    return answer

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
    if selector in ["value", "value:", "value:value:", "value:value:value:", "value:value:value:value:"]:
      return invokeCompiledBlock(receiver.blockVal, args)

  # A dynamic send reads its selector from an argument, so the builtin table
  # cannot run it: the `perform:` builtins sit after the class-side and compiled
  # method paths, which meant class-side, builtin, allocator and DNU sends never
  # ran and every miss silently answered nil. Convey the real send instead, so
  # `obj perform: sel` matches the direct send, including signalling on a miss.
  # A user method that implements `perform:` itself keeps ordinary dispatch.
  if selector.len >= 8 and selector[0] == 'p' and
     selector in ["perform:", "perform:with:", "perform:with:with:"] and
     args.len >= 1 and not implementsPerform(receiver, getReceiverClassName(receiver), selector):
    var conveyedSelector = ""
    case args[0].kind
    of vkSymbol: conveyedSelector = args[0].symVal
    of vkString: conveyedSelector = args[0].strVal
    else: discard
    return sendMessage(runtime, receiver, conveyedSelector, args[1..^1])

  if receiver.kind == vkClass and receiver.classVal != nil:
    if selector in ["jsonExclude:", "jsonOnly:", "jsonRename:", "jsonOmitNil:",
                    "jsonOmitEmpty:", "jsonFormat:", "jsonFieldOrder:", "jsonReset", "jsonSpec"] and
       not hasCompiledClassMethodInHierarchy(receiver.classVal.name, selector):
      let cls = receiver.classVal
      case selector
      of "jsonExclude:": return classJsonExcludeImpl(cls, args)
      of "jsonOnly:": return classJsonOnlyImpl(cls, args)
      of "jsonRename:": return classJsonRenameImpl(cls, args)
      of "jsonOmitNil:": return classJsonOmitNilImpl(cls, args)
      of "jsonOmitEmpty:": return classJsonOmitEmptyImpl(cls, args)
      of "jsonFormat:": return classJsonFormatImpl(cls, args)
      of "jsonFieldOrder:": return classJsonFieldOrderImpl(cls, args)
      of "jsonReset": return classJsonResetImpl(cls, args)
      else: return classJsonSpecImpl(cls, args)
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
          return compiledArray(names)
      else: discard
    if receiver.classVal.name == "System" and selector == "arguments" and args.len == 0 and
       not hasCompiledClassMethodInHierarchy("System", selector):
      return compiledSystemArguments()
    if receiver.classVal.name == "Json" and args.len == 1 and
       not hasCompiledClassMethodInHierarchy("Json", selector):
      case selector
      of "buildDynamic:": return compiledJsonBuildDynamic(args[0])
      of "stringify:": return compiledJsonStringify(args[0])
      of "parse:": return compiledJsonParse(args[0])
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
  of "=":
    if args.len == 1:
      let other = args[0]
      if receiver.kind != other.kind:
        return toValue(false)
      case receiver.kind
      of vkInt: return toValue(receiver.intVal == other.intVal)
      of vkFloat: return toValue(receiver.floatVal == other.floatVal)
      of vkString: return toValue(receiver.strVal == other.strVal)
      of vkSymbol: return toValue(receiver.symVal == other.symVal)
      of vkBool: return toValue(receiver.boolVal == other.boolVal)
      else: return toValue(compiledIdentityEqual(receiver, other))
  of "<>":
    if args.len == 1:
      let other = args[0]
      if receiver.kind in {vkInt, vkFloat} and other.kind in {vkInt, vkFloat}:
        if receiver.kind != other.kind:
          return toValue(true)
        if receiver.kind == vkInt:
          return toValue(receiver.intVal != other.intVal)
        return toValue(receiver.floatVal != other.floatVal)
      if receiver.kind == vkString and other.kind == vkString:
        return toValue(receiver.strVal != other.strVal)
      if receiver.kind == vkSymbol and other.kind == vkSymbol:
        return toValue(receiver.symVal != other.symVal)
    return compiledMissingMessage(receiver, selector)
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
      return compiledArray(names)
    return compiledMissingMessage(receiver, selector)
  of "isKindOf:":
    if args.len == 1 and args[0].kind == vkClass and args[0].classVal != nil and
       receiverClassName.len > 0:
      let targetName = args[0].classVal.name
      let owner = walkCompiledHierarchy(receiverClassName,
        proc(name: string): bool = name == targetName)
      return toValue(owner.len > 0)
    return toValue(false)

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
        return compiledArray(@[])
      of "Table":
        return compiledTable(initTable[NodeValue, NodeValue]())
      of "Set":
        let value = compiledTable(initTable[NodeValue, NodeValue]())
        if "Set" notin compiledClasses:
          compiledClasses["Set"] = newClass(name = "Set")
        value.instVal.class = compiledClasses["Set"]
        return value
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
          return compiledArray(elements)
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
        return compiledArray(elements)
      else:
        discard
    return NodeValue(kind: vkNil)

  of "add:":
    if receiver.kind == vkArray and args.len > 0:
      var arr = receiver.arrayVal
      arr.add(args[0])
      return compiledArray(arr)
    if receiver.kind == vkTable and args.len > 0:
      # Tables back compiled Set values: the element is both key and value, so
      # repeated adds are naturally deduplicated.
      var tbl = receiver.tableVal
      tbl[args[0]] = args[0]
      return compiledTable(tbl)
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
          return compiledArray(arr)
      elif receiver.kind == vkTable:
        var tbl = receiver.tableVal
        tbl[args[0]] = args[1]
        return compiledTable(tbl)
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
      return compiledArray(keys)
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
      return compiledArray(parts)
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

  of "isEmpty", "notEmpty":
    var size = -1
    case receiver.kind
    of vkArray: size = receiver.arrayVal.len
    of vkTable: size = receiver.tableVal.len
    of vkString: size = receiver.strVal.len
    else: discard
    if size >= 0:
      return toValue(if selector == "isEmpty": size == 0 else: size > 0)
    return compiledMissingMessage(receiver, selector)

  of "collect:", "select:", "reject:", "detect:", "detect:ifNone:",
     "anySatisfy:", "allSatisfy:", "noneSatisfy:":
    let arity = if selector == "detect:ifNone:": 2 else: 1
    if receiver.kind != vkArray or args.len != arity:
      return compiledMissingMessage(receiver, selector)
    var elements: seq[NodeValue]
    for item in receiver.arrayVal:
      let answer = sendMessage(runtime, args[0], "value:", @[item])
      let matched = if selector == "collect:": false else: isTruthy(answer)
      case selector
      of "collect:": elements.add(answer)
      of "select:":
        if matched: elements.add(item)
      of "reject:":
        if not matched: elements.add(item)
      of "detect:", "detect:ifNone:":
        if matched: return item
      of "anySatisfy:":
        if matched: return toValue(true)
      of "allSatisfy:":
        if not matched: return toValue(false)
      of "noneSatisfy:":
        if matched: return toValue(false)
      else: discard
    case selector
    of "collect:", "select:", "reject:":
      return compiledArray(elements)
    of "detect:ifNone:": return sendMessage(runtime, args[1], "value", @[])
    of "detect:": return nilValue()
    of "anySatisfy:": return toValue(false)
    else: return toValue(true)

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
  let interpreted = boundInterpretedSend(receiver, selector, args)
  if interpreted.handled:
    return interpreted.value
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

proc frozenHostInterpreter*(host: SchedulerContext): Interpreter =
  ## Access the interpreter owned by this explicit host's main process.
  host.mainProcess.getInterpreter()

proc newEmbeddedFrozenHost*(sources: openArray[tuple[path, source: string]]): SchedulerContext =
  ## Create an explicit scheduler-owned host from embedded library sources only.
  ## No application source replay and no ambient hybrid interpreter are involved.
  result = newSchedulerContext()
  var interp = result.mainProcess.getInterpreter()
  interp.packageOnlyLoads = true
  interp.hardingHome = "."
  for (path, source) in sources:
    interp.packageSources[][path] = source
  let previousSuppress = interp.suppressUncaughtExit
  interp.suppressUncaughtExit = true
  try:
    loadStdlib(interp, "lib/core/Bootstrap.hrd")
  finally:
    interp.suppressUncaughtExit = previousSuppress

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
  ## Mixed sends select an engine before execution, never by inspecting a result.
  ## Interpreter-owned objects use the live VM method table (including shims).
  ## Native-layout objects and compiled blocks remain in the native runtime;
  ## their missing sends propagate rather than retrying and duplicating effects.
  if receiver.kind == vkInstance and receiver.instVal != nil and
     receiver.instVal.isNimProxy and receiver.instVal.nimValue != nil:
    initRuntime()
    return sendMessage(currentRuntime[], receiver, selector, args)
  if receiver.kind == vkBlock and receiver.blockVal != nil and
     receiver.blockVal.nativeImpl != nil:
    initRuntime()
    return sendMessage(currentRuntime[], receiver, selector, args)
  # Native class objects and collection owners are distinct from the VM's
  # classes even when their names match. Select by identity, not spelling.
  let cls = if receiver.kind == vkClass: receiver.classVal
            elif receiver.kind == vkInstance and receiver.instVal != nil and
                 receiver.instVal.kind in {ikArray, ikTable}: receiver.instVal.class
            else: nil
  if cls != nil and cls.name in compiledClasses and compiledClasses[cls.name] == cls:
    initRuntime()
    return sendMessage(currentRuntime[], receiver, selector, args)
  initHybridRuntime()
  result = sendMessageInterpreted(hybridInterpreter, receiver, selector, args)

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
