import std/[tables, hashes]
import ./types

type
  CopyProtocolError* = object of CatchableError
  CopyAllocator* = proc(value: NodeValue): NodeValue
  CopySlotReader* = proc(value: NodeValue, name: string): NodeValue
  CopySlotWriter* = proc(value: NodeValue, name: string, entry: NodeValue)

proc identityHashValue*(value: NodeValue): NodeValue =
  ## Stable within the lifetime of the value; not a persistent identifier.
  case value.kind
  of vkInstance:
    if value.instVal == nil or value.isNilValue: return toValue(0)
    if value.instVal.compiledOwner != nil:
      return toValue(hash(cast[uint](value.instVal.compiledOwner)).int)
    return toValue(hash(cast[uint](value.instVal)).int)
  of vkClass: toValue(hash(cast[uint](value.classVal)).int)
  of vkBlock: toValue(hash(cast[uint](value.blockVal)).int)
  else: toValue(hash(value).int)

proc valueHash*(value: NodeValue): NodeValue =
  ## Primitive values hash by value; ordinary objects default to identity.
  if value.isNilValue: return toValue(0)
  if value.kind == vkInstance and value.instVal != nil:
    case value.instVal.kind
    of ikInt: return toValue(hash(value.instVal.intVal).int)
    of ikFloat:
      let number = value.instVal.floatVal
      return toValue(hash(if number == 0.0: 0.0 else: number).int)
    of ikString: return toValue(hash(value.instVal.strVal).int)
    of ikArray, ikTable:
      # Size is invariant under structural equality and does not recurse into
      # cycles. Custom key classes can supply a more selective hash.
      return toValue(if value.instVal.kind == ikArray: value.instVal.elements.len
                     else: value.instVal.entries.len)
    of ikObject: return identityHashValue(value)
  if value.kind == vkArray: return toValue(value.arrayVal.len)
  if value.kind == vkTable: return toValue(value.tableVal.len)
  if value.kind == vkFloat:
    return toValue(hash(if value.floatVal == 0.0: 0.0 else: value.floatVal).int)
  identityHashValue(value)

proc copyGraph*(value: NodeValue, deep: bool, allocate: CopyAllocator,
                readSlot: CopySlotReader, writeSlot: CopySlotWriter): NodeValue =
  ## Copy object storage, preserving cycles and shared references for deep copies.
  ## Classes, blocks and immediate values are shared. Hosts control native layout.
  var copies = initTable[Instance, NodeValue]()
  proc visit(entry: NodeValue): NodeValue =
    if entry.isNilValue: return entry
    if entry.kind == vkInstance and entry.instVal != nil and entry.instVal.class != nil and
       entry.instVal.class.name in ["True", "False"]:
      return entry
    if entry.kind != vkInstance or entry.instVal == nil:
      return entry
    let original = entry.instVal
    if original in copies: return copies[original]
    let copied = allocate(entry)
    if copied.kind != vkInstance or copied.instVal == nil:
      return copied
    copies[original] = copied
    template child(item: NodeValue): NodeValue =
      (if deep: visit(item) else: item)
    case original.kind
    of ikObject:
      if original.class != nil:
        for name in original.class.allSlotNames:
          writeSlot(copied, name, child(readSlot(entry, name)))
    of ikArray:
      for item in original.elements: copied.instVal.elements.add(child(item))
    of ikTable:
      for key, item in original.entries:
        copied.instVal.entries[child(key)] = child(item)
    of ikInt: copied.instVal.intVal = original.intVal
    of ikFloat: copied.instVal.floatVal = original.floatVal
    of ikString: copied.instVal.strVal = original.strVal
    copied
  visit(value)

proc interpretedCopy*(value: NodeValue, deep: bool): NodeValue =
  ## Refuse host resources rather than aliasing raw pointers in a purported copy.
  proc allocate(entry: NodeValue): NodeValue =
    let source = entry.instVal
    if source.isNimProxy or source.nimValue != nil or source.nativeSlots != nil:
      raise newException(CopyProtocolError, "Copying native resources requires an explicit adapter")
    var target: Instance
    case source.kind
    of ikObject: target = newInstance(source.class)
    of ikArray: target = newArrayInstance(source.class, @[])
    of ikTable: target = newTableInstance(source.class, initTable[NodeValue, NodeValue]())
    of ikInt: target = newIntInstance(source.class, source.intVal)
    of ikFloat: target = newFloatInstance(source.class, source.floatVal)
    of ikString: target = newStringInstance(source.class, source.strVal)
    NodeValue(kind: vkInstance, instVal: target)
  proc readSlot(entry: NodeValue, name: string): NodeValue =
    entry.instVal.readInstanceSlot(entry.instVal.class.getSlotIndex(name))
  proc writeSlot(entry: NodeValue, name: string, item: NodeValue) =
    entry.instVal.writeInstanceSlot(entry.instVal.class.getSlotIndex(name), item)
  copyGraph(value, deep, allocate, readSlot, writeSlot)

proc tryInterpretedCopy*(value: NodeValue, deep: bool): tuple[value: NodeValue, error: string] =
  ## Translate representation-level refusals before returning to the stackless VM.
  try:
    result.value = interpretedCopy(value, deep)
  except CopyProtocolError as failure:
    result.error = failure.msg
