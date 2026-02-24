import std/strformat
import ../compiler/context
import ../compiler/symbols
import ../compiler/types as compTypes

# ============================================================================
# Slot Access Code Generation - Native Nim types
# ============================================================================

proc genSlotConsts*(cls: ClassInfo): string =
  result = ""
  if cls.slots.len == 0:
    return
  result.add("  # Slot constants\n")
  for i, slot in cls.slots:
    result.add(fmt("  const {mangleClass(cls.name)}_{mangleSlot(slot.name)}_index = {i}\n"))
  result.add("\n")

proc genSlotGetter*(cls: ClassInfo, slot: SlotDef): string =
  ## Generate optimized slot getter procedure
  let clsName = mangleClass(cls.name)
  let slotName = mangleSlot(slot.name)
  
  var output = ""
  output.add(fmt("proc get{slotName}*(self: {clsName}): NodeValue =\n"))
  output.add(fmt("  ## Get slot '{slot.name}' from {cls.name}\n"))
  output.add(fmt("  return self[].{slotName}\n\n"))
  return output

proc genSlotSetter*(cls: ClassInfo, slot: SlotDef): string =
  ## Generate optimized slot setter procedure
  let clsName = mangleClass(cls.name)
  let slotName = mangleSlot(slot.name)
  
  var output = ""
  output.add(fmt("proc set{slotName}*(self: {clsName}, value: NodeValue) =\n"))
  output.add(fmt("  ## Set slot '{slot.name}' on {cls.name}\n"))
  output.add(fmt("  self[].{slotName} = value\n\n"))
  return output

proc genSlotAccessors*(cls: ClassInfo): string =
  ## Generate all slot accessors for a class
  result = ""
  
  if cls.slots.len == 0:
    return
  
  result.add("# Slot accessors\n")
  result.add("################################\n\n")
  
  for slot in cls.slots:
    if not slot.isInherited:
      result.add(genSlotGetter(cls, slot))
      result.add(genSlotSetter(cls, slot))
  
  return result