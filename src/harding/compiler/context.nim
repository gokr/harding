import std/tables
import ./types

# ============================================================================
# Compiler Context
# Maintains state during Harding to Nim compilation
# ============================================================================

type
  SlotDef* = object
    name*: string              ## Slot name
    constraint*: TypeConstraint ## Type constraint
    index*: int                ## Slot index (O(1) access)
    isInherited*: bool         ## Inherited from parent

  MethodType* = object
    selector*: string          ## Method selector
    parameters*: seq[TypeConstraint]  ## Parameter type constraints
    returnType*: TypeConstraint ## Return type constraint
    isPrimitive*: bool         ## Has primitive implementation

  ClassInfo* = ref object
    name*: string              ## Class name
    parent*: ClassInfo     ## Parent class (inheritance chain)
    slots*: seq[SlotDef]       ## Slot definitions
    methods*: seq[MethodType]  ## Method type information
    slotIndex*: Table[string, int]  ## Slot name -> index

  CompilerContext* = ref object
    outputDir*: string
    moduleName*: string
    classes*: Table[string, ClassInfo]  ## Class registry
    currentClass*: ClassInfo  ## Currently compiling class
    symbols*: Table[string, string]  ## Selector -> mangled name

proc newCompiler*(outputDir = "./build", moduleName = "compiled"): CompilerContext =
  ## Create new compiler context
  result = CompilerContext(
    outputDir: outputDir,
    moduleName: moduleName,
    classes: initTable[string, ClassInfo](),
    currentClass: nil,
    symbols: initTable[string, string]()
  )

proc newClassInfo*(name: string, parent: ClassInfo = nil): ClassInfo =
  ## Create new class info
  result = ClassInfo(
    name: name,
    parent: parent,
    slots: @[],
    methods: @[],
    slotIndex: initTable[string, int]()
  )

proc addSlot*(cls: ClassInfo, name: string,
              constraint: TypeConstraint = tcObject): int =
  ## Add a slot definition and return its index
  if name in cls.slotIndex:
    return cls.slotIndex[name]

  let slot = SlotDef(
    name: name,
    constraint: constraint,
    index: cls.slots.len,
    isInherited: false
  )
  cls.slots.add(slot)
  cls.slotIndex[name] = slot.index
  return slot.index

proc getSlotIndex*(cls: ClassInfo, name: string): int =
  ## Get slot index, searching inheritance chain
  if name in cls.slotIndex:
    return cls.slotIndex[name]
  if cls.parent != nil:
    return cls.parent.getSlotIndex(name)
  return -1

proc getSlotDef*(cls: ClassInfo, name: string): SlotDef =
  ## Get slot definition, searching inheritance chain
  if name in cls.slotIndex:
    let idx = cls.slotIndex[name]
    if idx < cls.slots.len and cls.slots[idx].name == name:
      return cls.slots[idx]
  if cls.parent != nil:
    return cls.parent.getSlotDef(name)
  return SlotDef(name: name, constraint: tcNone, index: -1, isInherited: true)

proc getAllSlots*(cls: ClassInfo): seq[SlotDef] =
  ## Get all slots including inherited ones (parents first)
  result = @[]

  if cls == nil:
    return result

  if cls.parent != nil:
    result = cls.parent.getAllSlots()

  for slot in cls.slots:
    if slot.isInherited:
      continue

    var found = false
    for existing in result:
      if existing.name == slot.name:
        found = true
        break

    if not found:
      result.add(slot)

proc resolveSlotIndices*(ctx: var CompilerContext): void =
  ## Resolve and assign slot indices across inheritance chain
  for name, cls in ctx.classes.mpairs:
    cls.slotIndex.clear()
    var idx = cls.parent.getAllSlots().len
    for slot in cls.slots.mitems:
      if not slot.isInherited:
        slot.index = idx
        cls.slotIndex[slot.name] = idx
        inc idx
