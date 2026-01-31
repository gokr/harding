import std/[tables, sequtils]
import ./types

# ============================================================================
# Compiler Context
# Maintains state during Nimtalk to Nim compilation
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
    generatedMethods*: seq[tuple[selector: string, code: string]]

proc newCompiler*(outputDir = "./build", moduleName = "compiled"): CompilerContext =
  ## Create new compiler context
  result = CompilerContext(
    outputDir: outputDir,
    moduleName: moduleName,
    classes: initTable[string, ClassInfo](),
    currentClass: nil,
    symbols: initTable[string, string](),
    generatedMethods: @[]
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

proc addMethod*(cls: ClassInfo, selector: string,
                parameters: seq[TypeConstraint],
                returnType: TypeConstraint = tcNone): MethodType =
  ## Add method type information
  let meth = MethodType(
    selector: selector,
    parameters: parameters,
    returnType: returnType,
    isPrimitive: false
  )
  cls.methods.add(meth)
  return meth

proc getMethodType*(cls: ClassInfo, selector: string): MethodType =
  ## Get method type info, searching inheritance chain
  for meth in cls.methods:
    if meth.selector == selector:
      return meth
  if cls.parent != nil:
    return cls.parent.getMethodType(selector)
  return MethodType(selector: selector, parameters: @[], returnType: tcNone)

proc getAllSlots*(cls: ClassInfo): seq[SlotDef] =
  ## Get all slots including inherited ones
  result = @[]
  var current: ClassInfo = cls
  while current != nil:
    for slot in current.slots:
      if not slot.isInherited and result.allIt(it.name != slot.name):
        result.add(slot)
    current = current.parent
  # Reverse to put parents first
  var reversedResult: seq[SlotDef] = @[]
  for i in countdown(result.len - 1, 0):
    reversedResult.add(result[i])
  result = reversedResult

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
