import std/[unittest, tables]
import ../src/harding/core/types

suite "Declared slot storage contract":
  test "rejection is atomic and Integer converts only towards Float":
    let cls = newClass(slotNames = @["number", "real"], name = "ContractStorage")
    cls.slotContracts["number"] = SlotContract(kind: scInteger)
    cls.slotContracts["real"] = SlotContract(kind: scFloat)
    let instance = newInstance(cls)
    instance.writeInstanceSlot(0, toValue(7))
    for invalid in [nilValue(), toValue(1.5), toValue("text"), toValue(false)]:
      expect SlotTypeError:
        instance.writeInstanceSlot(0, invalid)
      check instance.readInstanceSlot(0).intVal == 7
    instance.writeInstanceSlot(1, toValue(3))
    check instance.readInstanceSlot(1).kind == vkFloat
    check instance.readInstanceSlot(1).floatVal == 3.0

  test "both nil representations are rejected for primitives":
    let contract = SlotContract(kind: scString)
    let wrappedNil = NodeValue(kind: vkInstance, instVal: nilInstance)
    check normalizeSlotValue(contract, nilValue()).error.len > 0
    if nilInstance != nil:
      check normalizeSlotValue(contract, wrappedNil).error.len > 0

  test "secondary parent defaults and contracts resolve in graph order":
    let left = newClass(name = "ContractLeft")
    let right = newClass(slotNames = @["quantity"], name = "ContractRight")
    right.slotContracts["quantity"] = SlotContract(kind: scInteger)
    right.setSlotDefault("quantity", toValue(42))
    let child = newClass(superclasses = @[left, right], name = "ContractBoth")
    let instance = newInstance(child)
    check instance.readInstanceSlot(0).intVal == 42
    expect SlotTypeError:
      instance.writeInstanceSlot(0, nilValue())
    check instance.readInstanceSlot(0).intVal == 42

  test "nullable object slots accept secondary ancestors and reject unrelated classes":
    let target = newClass(name = "ContractTarget")
    let secondary = newClass(superclasses = @[newClass(name = "ContractMain"), target], name = "ContractSecondary")
    let unrelated = newClass(name = "ContractUnrelated")
    let cls = newClass(slotNames = @["object"], name = "ContractOwner")
    cls.slotContracts["object"] = SlotContract(kind: scObject, objectType: target)
    let instance = newInstance(cls)
    let accepted = newInstance(secondary).toValue()
    instance.writeInstanceSlot(0, accepted)
    expect SlotTypeError:
      instance.writeInstanceSlot(0, newInstance(unrelated).toValue())
    check instance.readInstanceSlot(0).instVal == accepted.instVal
    instance.writeInstanceSlot(0, nilValue())
    check isNilValue(instance.readInstanceSlot(0))

  test "lookup cycle protection and dynamic masking remain finite":
    let first = newClass(slotNames = @["value"], name = "ContractCycleFirst")
    let second = newClass(name = "ContractCycleSecond")
    first.superclasses = @[second]
    second.superclasses = @[first]
    check first.slotContract("absent").kind == scDynamic
    first.slotContracts["value"] = SlotContract(kind: scDynamic)
    second.slotContracts["value"] = SlotContract(kind: scInteger)
    let instance = newInstance(first)
    instance.writeInstanceSlot(0, toValue("dynamic"))
    check instance.readInstanceSlot(0).strVal == "dynamic"
    # Do not leave an intentional managed cycle behind in the fixture.
    first.superclasses = @[]
    second.superclasses = @[]
