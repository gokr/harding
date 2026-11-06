import std/[tables, algorithm, os, logging, strutils, sequtils, options]
import ../core/types
import ../interpreter/objects
import ./compiled_support
import ../core/log_support

# ============================================================================
# Primitive implementations for compiled Harding code.
#
# Each proc here is the Nim side of one `<primitive selector>` declaration in
# lib/. Harding method bodies are compiled by Granite; these are the leaves that
# talk to the representation. No selector implemented in Harding appears here.
# ============================================================================

proc truthy(value: NodeValue): bool =
  if value.kind == vkBool: return value.boolVal
  not isNilValue(value)

proc storageOf(self: NodeValue): Instance =
  if self.kind == vkInstance and self.instVal != nil and
     self.instVal.kind in {ikArray, ikTable}:
    return self.instVal

proc sequenceOf(value: NodeValue): seq[NodeValue] =
  let storage = storageOf(value)
  if storage != nil:
    if storage.kind == ikArray: return storage.elements
    for entry in storage.entries.values: result.add(entry)
  elif value.kind == vkArray: return value.arrayVal
  elif value.kind == vkTable:
    for entry in value.tableVal.values: result.add(entry)

proc equalValues(a, b: NodeValue): bool =
  compiledIdentityEqual(a, b) or truthy(sendMessage(nil, a, "=", @[b]))

# --- Array -------------------------------------------------------------------

proc primitiveArrayNew*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  compiledArray(@[])

proc primitiveArrayNewSize*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0 and args[0].kind == vkInt and args[0].intVal > 0:
    var elements = newSeq[NodeValue](args[0].intVal)
    for index in 0..<elements.len: elements[index] = nilValue()
    return compiledArray(elements)
  compiledArray(@[])

proc primitiveArrayNewSizeWithAll*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len >= 2 and args[0].kind == vkInt and args[0].intVal > 0:
    var elements = newSeq[NodeValue](args[0].intVal)
    for index in 0..<elements.len: elements[index] = args[1]
    return compiledArray(elements)
  compiledArray(@[])

proc primitiveArrayAt*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let (ok, index) = if args.len > 0: args[0].tryGetInt() else: (false, -1)
  let storage = storageOf(self)
  if storage != nil and ok and index >= 0 and index < storage.elements.len:
    return storage.elements[index]
  if storage == nil and ok and self.kind == vkArray and index >= 0 and
     index < self.arrayVal.len:
    return self.arrayVal[index]
  raiseCompiledError(compiledErrorValue("SubscriptOutOfBounds",
    "Array index out of bounds: " & $index))

proc primitiveArrayAtPut*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 2: return self
  let (ok, index) = args[0].tryGetInt()
  if not ok or index < 0:
    return raiseCompiledError(compiledErrorValue("SubscriptOutOfBounds",
      "Array index out of bounds: " & $index))
  let storage = storageOf(self)
  if storage != nil:
    if index < storage.elements.len:
      storage.elements[index] = args[1]
      return args[1]
    if index == storage.elements.len:
      storage.elements.add(args[1])
      return args[1]
    return raiseCompiledError(compiledErrorValue("SubscriptOutOfBounds",
      "Array index out of bounds: " & $index))
  self

proc primitiveArrayAdd*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return self
  let storage = storageOf(self)
  if storage != nil:
    # A Table-backed receiver is a compiled Set: the element is both key and
    # value, so adding it twice must not grow the collection.
    if storage.kind == ikTable: storage.entries[args[0]] = args[0]
    else: storage.elements.add(args[0])
  args[0]

proc primitiveArrayRemoveAt*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let (ok, index) = if args.len > 0: args[0].tryGetInt() else: (false, -1)
  let storage = storageOf(self)
  if storage != nil and ok and index >= 0 and index < storage.elements.len:
    let removed = storage.elements[index]
    storage.elements.delete(index)
    return removed
  raiseCompiledError(compiledErrorValue("SubscriptOutOfBounds",
    "Array index out of bounds: " & $index))

proc primitiveArrayRemoveAll*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = storageOf(self)
  if storage != nil: storage.elements.setLen(0)
  self

proc primitiveArrayIncludes*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  for element in sequenceOf(self):
    if equalValues(element, args[0]): return toValue(true)
  toValue(false)

proc primitiveArrayReverse*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = storageOf(self)
  if storage != nil:
    var elements = storage.elements
    reverse(elements)
    storage.elements = elements
  self

# --- Table -------------------------------------------------------------------

proc tableOf(self: NodeValue): Instance =
  result = storageOf(self)
  if result == nil or result.kind != ikTable: result = nil

proc primitiveTableNew*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  compiledTable(initTable[NodeValue, NodeValue]())

proc primitiveTableAt*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = tableOf(self)
  if args.len > 0 and storage != nil:
    if storage.entries.hasKey(args[0]): return storage.entries[args[0]]
    return raiseCompiledError(compiledErrorValue("NotFound",
      "Key not found: " & args[0].toString()))
  nilValue()

proc primitiveTableAtPut*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len >= 2:
    let storage = tableOf(self)
    if storage != nil: storage.entries[args[0]] = args[1]
  self

proc primitiveTableKeys*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var elements: seq[NodeValue] = @[]
  let storage = tableOf(self)
  if storage != nil:
    for key in storage.entries.keys: elements.add(key)
  compiledArray(elements)

proc primitiveTableIncludesKey*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = tableOf(self)
  if args.len > 0 and storage != nil:
    return toValue(storage.entries.hasKey(args[0]))
  toValue(false)

proc primitiveTableRemoveKey*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = tableOf(self)
  if args.len > 0 and storage != nil and storage.entries.hasKey(args[0]):
    storage.entries.del(args[0])
  self

# --- Set ---------------------------------------------------------------------

proc setOf(self: NodeValue): Instance =
  result = tableOf(self)
  if result != nil and result.class != nil and result.class.name != "Set":
    result = nil

proc compiledSet(entries: Table[NodeValue, NodeValue]): NodeValue =
  result = compiledTable(entries)
  result.instVal.class = ensureCompiledClass("Set")

proc primitiveSetNew*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  compiledSet(initTable[NodeValue, NodeValue]())

proc primitiveSetAdd*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0:
    let storage = setOf(self)
    if storage != nil: storage.entries[args[0]] = args[0]
    return args[0]
  self

proc primitiveSetRemove*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0:
    let storage = setOf(self)
    if storage != nil and storage.entries.hasKey(args[0]):
      storage.entries.del(args[0])
      return args[0]
  nilValue()

proc primitiveSetIncludes*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = setOf(self)
  if args.len > 0 and storage != nil:
    return toValue(storage.entries.hasKey(args[0]))
  toValue(false)

proc primitiveSetSize*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = setOf(self)
  if storage != nil: return toValue(storage.entries.len)
  toValue(0)

proc primitiveSetAsArray*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var elements: seq[NodeValue] = @[]
  let storage = setOf(self)
  if storage != nil:
    for value in storage.entries.values: elements.add(value)
  compiledArray(elements)

proc setAlgebra(self: NodeValue, args: seq[NodeValue], keep, union: bool): NodeValue =
  var entries = initTable[NodeValue, NodeValue]()
  let storage = setOf(self)
  if storage != nil:
    let other = if args.len > 0: sequenceOf(args[0]) else: newSeq[NodeValue]()
    if union:
      for key, value in storage.entries: entries[key] = value
      for value in other: entries[value] = value
    elif keep:
      for value in other:
        if storage.entries.hasKey(value): entries[value] = value
    else:
      for key, value in storage.entries: entries[key] = value
      for value in other: entries.del(value)
  result = compiledSet(entries)

proc primitiveSetUnion*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  setAlgebra(self, args, keep = false, union = true)

proc primitiveSetIntersection*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  setAlgebra(self, args, keep = true, union = false)

proc primitiveSetDifference*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  setAlgebra(self, args, keep = false, union = false)

# --- Numeric operators -------------------------------------------------------
#
# The library declares these as `<primitive primitivePlus: other>` and friends,
# so this is the operation itself. It must never re-send the selector: dispatch
# already chose this method, and falling back would re-enter it forever.

proc numericPair(a, b: NodeValue, intOp: proc(x, y: int): NodeValue,
                 floatOp: proc(x, y: float): NodeValue): NodeValue =
  if a.kind == vkInt and b.kind == vkInt: return intOp(a.intVal, b.intVal)
  var ax, bx: float
  let aFloat = case a.kind
               of vkInt: (ax = float(a.intVal); true)
               of vkFloat: (ax = a.floatVal; true)
               else: false
  let bFloat = case b.kind
               of vkInt: (bx = float(b.intVal); true)
               of vkFloat: (bx = b.floatVal; true)
               else: false
  if aFloat and bFloat: return floatOp(ax, bx)
  nilValue()

proc stringCompare(a, b: string, intOp: proc(x, y: int): bool): bool =
  let order = cmp(a, b)
  intOp(order, 0)

proc comparePair(a, b: NodeValue, intOp: proc(x, y: int): bool,
                 floatOp: proc(x, y: float): bool, ordered: bool): NodeValue =
  if a.kind == vkInt and b.kind == vkInt: return toValue(intOp(a.intVal, b.intVal))
  if a.kind == vkFloat and b.kind == vkFloat:
    return toValue(floatOp(a.floatVal, b.floatVal))
  if ordered and a.kind in {vkInt, vkFloat} and b.kind in {vkInt, vkFloat}:
    let ax = if a.kind == vkInt: float(a.intVal) else: a.floatVal
    let bx = if b.kind == vkInt: float(b.intVal) else: b.floatVal
    return toValue(floatOp(ax, bx))
  if a.kind == vkString and b.kind == vkString and ordered:
    return toValue(stringCompare(a.strVal, b.strVal, intOp))
  if a.kind == vkSymbol and b.kind == vkSymbol and ordered:
    return toValue(stringCompare(a.symVal, b.symVal, intOp))
  toValue(false)

proc primitivePlus*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  numericPair(self, args[0],
    proc (x, y: int): NodeValue = checkedIntAdd(x, y),
    proc (x, y: float): NodeValue = toValue(x + y))

proc primitiveMinus*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  numericPair(self, args[0],
    proc (x, y: int): NodeValue = checkedIntSub(x, y),
    proc (x, y: float): NodeValue = toValue(x - y))

proc primitiveTimes*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  numericPair(self, args[0],
    proc (x, y: int): NodeValue = checkedIntMul(x, y),
    proc (x, y: float): NodeValue = toValue(x * y))

proc primitiveDivide*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  let divisorIsZero =
    (args[0].kind == vkInt and args[0].intVal == 0) or
    (args[0].kind == vkFloat and args[0].floatVal == 0.0)
  if divisorIsZero:
    return raiseCompiledError(compiledErrorValue("DivisionByZero",
      "Integer division by zero"))
  numericPair(self, args[0],
    proc (x, y: int): NodeValue = toValue(float(x) / float(y)),
    proc (x, y: float): NodeValue = toValue(x / y))

proc primitiveIntDiv*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0 and self.kind == vkInt and args[0].kind == vkInt:
    return toValue(compiledIntegerDiv(self.intVal, args[0].intVal))
  nilValue()

proc primitiveBackslashModulo*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0 and self.kind == vkInt and args[0].kind == vkInt:
    if args[0].intVal == 0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero",
        "Integer division by zero"))
    return toValue(self.intVal mod args[0].intVal)
  nilValue()

proc primitiveLessThan*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  comparePair(self, args[0],
    proc (x, y: int): bool = x < y,
    proc (x, y: float): bool = x < y, ordered = true)

proc primitiveGreaterThan*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  comparePair(self, args[0],
    proc (x, y: int): bool = x > y,
    proc (x, y: float): bool = x > y, ordered = true)

proc primitiveLessOrEq*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  comparePair(self, args[0],
    proc (x, y: int): bool = x <= y,
    proc (x, y: float): bool = x <= y, ordered = true)

proc primitiveGreaterOrEq*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  comparePair(self, args[0],
    proc (x, y: int): bool = x >= y,
    proc (x, y: float): bool = x >= y, ordered = true)

proc primitiveEquals*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  if self.kind == args[0].kind and self.kind in {vkString, vkSymbol, vkBool}:
    return toValue(self == args[0])
  if self.kind == vkClass and args[0].kind == vkClass:
    return toValue(self.classVal == args[0].classVal)
  if self.kind in {vkInt, vkFloat} and args[0].kind in {vkInt, vkFloat}:
    return comparePair(self, args[0],
      proc (x, y: int): bool = x == y,
      proc (x, y: float): bool = x == y, ordered = false)
  toValue(compiledIdentityEqual(self, args[0]))

proc primitiveNotEquals*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(true)
  let equal = primitiveEquals(self, args)
  toValue(not (equal.kind == vkBool and equal.boolVal))

# --- Object reflection -------------------------------------------------------

proc classOfValue(self: NodeValue): string =
  ## The class name of any receiver: a compiled proxy, an instance with a class,
  ## a class value, or an immediate.
  result = getReceiverClassName(self)
  if result.len == 0 and self.kind == vkInstance and self.instVal != nil and
     self.instVal.class != nil:
    result = self.instVal.class.name
  if result.len == 0 and self.kind == vkClass and self.classVal != nil:
    result = self.classVal.name
  if result.len == 0: result = builtInClassName(self)

proc primitiveClassName*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  # A class value answers its own name; `Object class>>name` is declared as this
  # primitive, so the metaclass is not the subject.
  if self.kind == vkClass and self.classVal != nil:
    return toValue(self.classVal.name)
  let name = classOfValue(self)
  if name.len > 0: return toValue(name)
  if self.kind == vkClass and self.classVal != nil: return toValue(self.classVal.name)
  nilValue()

proc primitiveClass*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if self.kind == vkClass: return self
  let name = classOfValue(self)
  if name.len > 0: return compiledClassValue(name)
  compiledBaseClassValue("Object")

proc primitiveSuperclassNames*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var names: seq[NodeValue] = @[]
  for parent in getSuperclasses(classOfValue(self)):
    names.add(toValue(parent))
  compiledArray(names)

proc primitiveSlotNames*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var names: seq[NodeValue] = @[]
  let className = classOfValue(self)
  for slot in compiledSlotNamesFor(className): names.add(toValue(slot))
  compiledArray(names)

proc primitiveIsKindOf*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0 or args[0].kind != vkClass or args[0].classVal == nil:
    return toValue(false)
  # Classes may have several parents (`Set` is a collection and a mixin), so
  # membership is a walk over the whole superclass graph, not the first parent.
  let target = args[0].classVal.name
  let owner = walkCompiledHierarchy(classOfValue(self),
    proc(name: string): bool = name == target)
  toValue(owner.len > 0)

proc primitiveRespondsTo*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  var selector = ""
  if args[0].kind == vkSymbol: selector = args[0].symVal
  elif args[0].kind == vkString: selector = args[0].strVal
  if selector.len == 0: return toValue(false)
  if self.kind == vkClass and self.classVal != nil:
    return toValue(hasCompiledClassMethodInHierarchy(self.classVal.name, selector))
  let name = classOfValue(self)
  if name.len == 0: return toValue(false)
  toValue(hasCompiledMethodInHierarchy(name, selector))

proc primitiveClone*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let storage = storageOf(self)
  if storage != nil:
    if storage.kind == ikArray: return compiledArray(storage.elements)
    return compiledTable(storage.entries)
  if self.kind == vkInstance and self.instVal != nil and
     self.instVal.kind == ikObject:
    let copy = Instance(kind: ikObject, class: self.instVal.class,
      isNimProxy: self.instVal.isNimProxy, slots: self.instVal.slots,
      nativeSlots: self.instVal.nativeSlots, compiledOwner: self.instVal.compiledOwner,
      nimValue: self.instVal.nimValue)
    return NodeValue(kind: vkInstance, instVal: copy)
  self

proc primitivePerform*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  var selector = ""
  if args[0].kind == vkSymbol: selector = args[0].symVal
  elif args[0].kind == vkString: selector = args[0].strVal
  sendMessage(nil, self, selector, @[])

proc primitivePerformWith*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 2: return nilValue()
  var selector = ""
  if args[0].kind == vkSymbol: selector = args[0].symVal
  elif args[0].kind == vkString: selector = args[0].strVal
  sendMessage(nil, self, selector, @[args[1]])

proc primitivePerformWithWith*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 3: return nilValue()
  var selector = ""
  if args[0].kind == vkSymbol: selector = args[0].symVal
  elif args[0].kind == vkString: selector = args[0].strVal
  sendMessage(nil, self, selector, @[args[1], args[2]])

proc primitiveError*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let message = if args.len > 0: args[0].toString() else: ""
  raiseCompiledError(compiledErrorValue("Error", message))

# --- Block -------------------------------------------------------------------

proc primitiveValue*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  invokeBlockValue(self, @[])

proc primitiveValueWith*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: invokeBlockValue(self, @[args[0]]) else: nilValue()

proc primitiveValueWithWith*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len >= 2: invokeBlockValue(self, @[args[0], args[1]]) else: nilValue()

proc primitiveValueWithWithWith*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len >= 3: invokeBlockValue(self, @[args[0], args[1], args[2]]) else: nilValue()

proc primitiveOnDo*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## Establish a handler. The protocol is defined once, where compiled sends are
  ## dispatched; re-sending `on:do:` here would re-enter this same method.
  if args.len < 2: return nilValue()
  compiledOnDo(self, args[0], args[1])

proc primitiveEnsure*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  compiledEnsure(self, args[0])

# --- Exception ---------------------------------------------------------------
#
# The exception protocol is defined once, in the runtime's send path. These
# primitives ask it directly: re-sending their own selector from inside the
# compiled method would re-enter that method forever.

proc primitiveSignal*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let answer = exceptionProtocol(self, "signal", @[])
  if answer.handled: return answer.value
  raiseCompiledError(self)

proc primitiveExceptionPass*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let answer = exceptionProtocol(self, "pass", @[])
  if answer.handled: return answer.value
  nilValue()

proc primitiveExceptionRetry*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let answer = exceptionProtocol(self, "retry", @[])
  if answer.handled: return answer.value
  nilValue()

# --- Logging -----------------------------------------------------------------

proc primitiveLogDebug*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: writeHardingLog(logging.lvlDebug, args[0]) else: nilValue()

proc primitiveLogInfo*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: writeHardingLog(logging.lvlInfo, args[0]) else: nilValue()

proc primitiveLogWarn*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: writeHardingLog(logging.lvlWarn, args[0]) else: nilValue()

proc primitiveLogError*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: writeHardingLog(logging.lvlError, args[0]) else: nilValue()

proc primitiveLogFatal*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: writeHardingLog(logging.lvlFatal, args[0]) else: nilValue()

# --- System ------------------------------------------------------------------

proc primitiveSystemCwd*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  toValue(getCurrentDir())

proc primitiveSystemArguments*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var elements: seq[NodeValue] = @[]
  for argument in commandLineParams(): elements.add(toValue(argument))
  compiledArray(elements)

# --- Mutable strings ---------------------------------------------------------

proc primitiveStringAppendValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return self
  let suffix = args[0].toString()
  if self.kind == vkString:
    return toValue(self.strVal & suffix)
  if self.kind == vkInstance and self.instVal != nil and self.instVal.kind == ikString:
    return toValue(self.instVal.strVal & suffix)
  self

proc primitiveStartsWithValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  let prefix = args[0].toString()
  toValue(self.toString().startsWith(prefix))

proc primitiveEndsWithValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  let suffix = args[0].toString()
  toValue(self.toString().endsWith(suffix))

# --- Files --------------------------------------------------------------------

proc pathOf(value: NodeValue): string =
  value.toString()

proc primitiveFileExists*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  toValue(fileExists(pathOf(args[0])))

proc primitiveFileDelete*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  let path = pathOf(args[0])
  if fileExists(path):
    removeFile(path)
    return toValue(true)
  toValue(false)

# --- Block shape and loops ---------------------------------------------------

proc primitiveParameterCount*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if self.kind == vkBlock and self.blockVal != nil:
    return toValue(self.blockVal.parameters.len)
  toValue(0)

proc whileLoop(self, body: NodeValue, untilFalse: bool): NodeValue =
  ## The condition block is the receiver. Each iteration evaluates it and the
  ## body block, matching Block>>whileTrue:/whileFalse: as the library declares
  ## them; the loop answers nil.
  while true:
    let condition = sendMessage(nil, self, "value", @[])
    var keepGoing = truthy(condition)
    if untilFalse: keepGoing = not keepGoing
    if not keepGoing: break
    discard sendMessage(nil, body, "value", @[])
  nilValue()

proc primitiveWhileTrue*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  whileLoop(self, args[0], untilFalse = false)

proc primitiveWhileFalse*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  whileLoop(self, args[0], untilFalse = true)

# --- Reflection without compiled state ---------------------------------------

proc primitiveConflictSelectors*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  compiledArray(@[])

proc primitiveClassConflictSelectors*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  compiledArray(@[])

proc primitiveIsMixin*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  toValue(classOfValue(self) == "Mixin")

proc primitiveHasProperty*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  toValue(compiledSlotNamesFor(classOfValue(self)).len > 0 and
          args[0].toString() in compiledSlotNamesFor(classOfValue(self)))

proc primitiveProperties*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var names: seq[NodeValue] = @[]
  for slot in compiledSlotNamesFor(classOfValue(self)): names.add(toValue(slot))
  compiledArray(names)

proc primitiveHtmlEscape*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var text = self.toString()
  text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
  text = text.replace("\"", "&quot;")
  toValue(text)

proc primitiveBasicNew*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let className = if self.kind == vkClass and self.classVal != nil:
                    self.classVal.name
                  else: ""
  if className.len == 0: return nilValue()
  newCompiledInstance(className)

# --- Exception diagnostics ----------------------------------------------------
#
# Compiled exceptions carry message and signaler as ordinary state; there is no
# VM activation stack to walk, so the introspection selectors answer the honest
# empty value instead of inventing a context.

proc primitiveExceptionSignaler*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  getSlotValue(self, "signaler")

proc primitiveExceptionSignalContext*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  nilValue()

proc primitiveExceptionSignalActivationDepth*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  toValue(0)

# --- Self-application ---------------------------------------------------------

proc primitiveAsSelfDo*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## `Class extend: aBlock` evaluates the block with the class as `self`; the
  ## compiled equivalent sends the block back to itself for the class side.
  if args.len == 0: return self
  sendMessage(nil, self, "extend:", @[args[0]])

# --- String construction ------------------------------------------------------

proc primitiveStringWithCapacity*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  toValue("")

# --- FileStream ---------------------------------------------------------------
#
# Compiled FileStream values own a real handle through a registry, because the
# handle is a Nim `File` and cannot live in a NodeValue.

type
  CompiledStream = ref object
    file: File
    open: bool
    readMode: bool

var compiledStreams* = initTable[int, CompiledStream]()
var nextStreamId = 1

proc streamHandle(self: NodeValue): int =
  ## FileStream keeps its handle in the `file` slot the library declares; the
  ## Nim File itself lives in a registry because a handle cannot be a NodeValue.
  let value = getSlotValue(self, "file")
  if value.kind == vkInt: value.intVal else: 0

proc primitiveFileOpenMode*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 2: return nilValue()
  let path = args[0].toString()
  let mode = args[1].toString().toLowerAscii()
  let stream = CompiledStream(open: true, readMode: mode.startsWith("r"))
  let opened =
    case mode
    of "r", "read": open(stream.file, path, fmRead)
    of "w", "write": open(stream.file, path, fmWrite)
    of "a", "append": open(stream.file, path, fmAppend)
    else: false
  if not opened: return nilValue()
  let handle = nextStreamId
  inc nextStreamId
  compiledStreams[handle] = stream
  discard setSlotValue(self, "file", toValue(handle))
  discard setSlotValue(self, "mode", toValue(mode))
  discard setSlotValue(self, "isOpen", toValue(true))
  self

proc primitiveFileWrite*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let handle = streamHandle(self)
  if args.len > 0 and handle in compiledStreams and compiledStreams[handle].open:
    compiledStreams[handle].file.write(args[0].toString())
  self

proc primitiveFileReadLine*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let handle = streamHandle(self)
  if handle in compiledStreams and compiledStreams[handle].open:
    var line = ""
    if compiledStreams[handle].file.readLine(line): return toValue(line)
  nilValue()

proc primitiveFileReadAll*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let handle = streamHandle(self)
  if handle in compiledStreams and compiledStreams[handle].open:
    return toValue(compiledStreams[handle].file.readAll())
  toValue("")

proc primitiveFileAtEnd*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let handle = streamHandle(self)
  if handle in compiledStreams and compiledStreams[handle].open:
    return toValue(compiledStreams[handle].file.endOfFile)
  toValue(true)

proc primitiveFileClose*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let handle = streamHandle(self)
  if handle in compiledStreams and compiledStreams[handle].open:
    compiledStreams[handle].file.close()
    compiledStreams[handle].open = false
    compiledStreams.del(handle)
  discard setSlotValue(self, "isOpen", toValue(false))
  self

# --- Library ------------------------------------------------------------------
#
# A compiled Library holds its bindings in a slot; the selectors are the same
# table operations the interpreter exposes, so a compiled library behaves like
# one in a compiled program.

proc libraryBindingsOf(self: NodeValue): NodeValue =
  getSlotValue(self, "bindings")

proc primitiveLibraryNew*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  compiledNewInstance("Library", nil)

proc primitiveLibraryAt*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  sendMessage(nil, libraryBindingsOf(self), "at:", @[args[0]])

proc primitiveLibraryAtPut*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 2: return self
  discard sendMessage(nil, libraryBindingsOf(self), "at:put:", @[args[0], args[1]])
  self

proc primitiveLibraryKeys*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  sendMessage(nil, libraryBindingsOf(self), "keys", @[])

proc primitiveLibraryIncludesKey*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return toValue(false)
  sendMessage(nil, libraryBindingsOf(self), "includesKey:", @[args[0]])

proc primitiveLibraryBindings*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  libraryBindingsOf(self)

proc primitiveLibraryName*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  getSlotValue(self, "name")

proc primitiveLibraryNameSet*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: discard setSlotValue(self, "name", args[0])
  self

proc primitiveLibraryAllNames*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  sendMessage(nil, libraryBindingsOf(self), "keys", @[])

proc primitiveLibraryNamed*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  sendMessage(nil, libraryBindingsOf(self), "at:", @[args[0]])

# --- Host services ------------------------------------------------------------
#
# Selectors that reach interpreter-owned class objects, the activation stack,
# process state or JSON configuration. A compiled program answers the honest
# compiled value where it has one, and refuses explicitly where the interpreter
# is the only thing that can answer.

proc primitiveIsClass*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  toValue(self.kind == vkClass)

proc primitivePrint*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  stdout.write(self.toString())
  self

proc primitivePrintln*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len > 0: echo args[0].toString()
  else: echo self.toString()
  self

proc primitiveSlotAt*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0: return nilValue()
  if args[0].kind == vkInt:
    let slots = compiledSlotNamesFor(classOfValue(self))
    if args[0].intVal >= 0 and args[0].intVal < slots.len:
      return getSlotValue(self, slots[args[0].intVal])
    return nilValue()
  getSlotValue(self, args[0].toString())

proc primitiveSlotAtPut*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 2: return self
  if args[0].kind == vkInt:
    let slots = compiledSlotNamesFor(classOfValue(self))
    if args[0].intVal >= 0 and args[0].intVal < slots.len:
      return setSlotValue(self, slots[args[0].intVal], args[1])
    return self
  setSlotValue(self, args[0].toString(), args[1])

proc compiledBlockImpl(body: NodeValue): proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## Adapt a block value to the compiled-method ABI the registry stores.
  let captured = body
  result = proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
    sendMessage(nil, captured, "value:value:value:", @[
      if args.len > 0: args[0] else: nilValue(),
      if args.len > 1: args[1] else: nilValue(),
      if args.len > 2: args[2] else: nilValue()])

proc primitiveSelectorPut*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len >= 2:
    registerCompiledMethod(classOfValue(self), args[0].toString(), compiledBlockImpl(args[1]))
    return args[1]
  nilValue()

proc primitiveClassSelectorPut*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len >= 2 and self.kind == vkClass and self.classVal != nil:
    registerCompiledClassMethod(self.classVal.name, args[0].toString(), compiledBlockImpl(args[1]))
    return args[1]
  nilValue()

proc requireInterpreter(name: string): NodeValue =
  raiseCompiledError(compiledErrorValue("Error",
    name & " needs the Harding interpreter; it is not available in a compiled program"))

proc primitiveEval*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  requireInterpreter("eval:")

proc primitiveEvaluate*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  requireInterpreter("evaluate:")

proc primitiveDeriveWithAccessors*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if self.kind != vkClass or self.classVal == nil: return nilValue()
  var source = "TmpDerived := " & self.classVal.name & " derive: #("
  if args.len > 0:
    for element in sequenceOf(args[0]):
      if source[^1] != '(': source.add(", ")
      source.add(element.toString())
  source.add(")")

  # Deriving a class is a definition-time operation on interpreter-owned class
  # objects, so a compiled program refuses it explicitly.
  requireInterpreter("deriveWithAccessors:" & source)

# JSON configuration is class-side state on the Class object itself, so a
# compiled program's serialization specification is the same one the interpreter
# and the JSON writer read.

proc jsonTargetClass(self: NodeValue): Class =
  if self.kind == vkClass: self.classVal
  elif self.kind == vkInstance and self.instVal != nil: self.instVal.class
  else: nil

proc slotList(value: NodeValue): seq[string] =
  for element in sequenceOf(value):
    let name = element.toString()
    if name.len > 0: result.add(name)

proc stringMap(value: NodeValue): Table[string, string] =
  let storage = storageOf(value)
  if storage != nil and storage.kind == ikTable:
    for key, entry in storage.entries.pairs:
      result[key.toString()] = entry.toString()

proc recordJsonOption(self: NodeValue, selector: string,
                      args: seq[NodeValue]): NodeValue =
  let cls = jsonTargetClass(self)
  if cls == nil or args.len == 0: return self
  let spec = getJsonSpec(cls)
  case selector
  of "exclude": spec.excludedSlots = slotList(args[0])
  of "only": spec.includedOnly = some(slotList(args[0]))
  of "rename": spec.renamedSlots = stringMap(args[0])
  of "omitNil": spec.omitNilSlots = slotList(args[0])
  of "omitEmpty": spec.omitEmptySlots = slotList(args[0])
  of "format":
    var formats = initTable[string, JsonFormatKind]()
    let storage = storageOf(args[0])
    if storage != nil and storage.kind == ikTable:
      for key, entry in storage.entries.pairs:
        let name = if entry.kind == vkSymbol: entry.symVal else: entry.toString()
        formats[key.toString()] =
          case name
          of "string": jfkString
          of "rawJson": jfkRawJson
          of "symbolName": jfkSymbolName
          of "className": jfkClassName
          else: jfkNone
    spec.slotFormats = formats
  of "fieldOrder": spec.fieldOrder = slotList(args[0])
  else: discard
  cls.jsonConfigVersion = cls.jsonConfigVersion + 1
  self

proc primitiveJsonExclude*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  recordJsonOption(self, "exclude", args)

proc primitiveJsonOnly*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  recordJsonOption(self, "only", args)

proc primitiveJsonRename*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  recordJsonOption(self, "rename", args)

proc primitiveJsonOmitNil*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  recordJsonOption(self, "omitNil", args)

proc primitiveJsonOmitEmpty*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  recordJsonOption(self, "omitEmpty", args)

proc primitiveJsonFormat*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  recordJsonOption(self, "format", args)

proc primitiveJsonFieldOrder*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  recordJsonOption(self, "fieldOrder", args)

proc primitiveJsonReset*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  let cls = jsonTargetClass(self)
  if cls != nil:
    cls.jsonSpec = nil
    cls.jsonConfigVersion = cls.jsonConfigVersion + 1
  self

proc primitiveJsonSpec*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var entries = initTable[NodeValue, NodeValue]()
  let cls = jsonTargetClass(self)
  if cls != nil and cls.jsonSpec != nil:
    if cls.jsonSpec.excludedSlots.len > 0:
      entries[toValue("exclude")] = compiledArray(
        cls.jsonSpec.excludedSlots.mapIt(toValue(it)))
    if cls.jsonSpec.renamedSlots.len > 0:
      var renames = initTable[NodeValue, NodeValue]()
      for key, value in cls.jsonSpec.renamedSlots.pairs:
        renames[toValue(key)] = toValue(value)
      entries[toValue("rename")] = compiledTable(renames)
  compiledTable(entries)

proc primitiveLibraryLoad*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## Loading executes source; that is the interpreter's job, and a compiled
  ## program says so instead of pretending it loaded something.
  requireInterpreter("Library>>load:")
