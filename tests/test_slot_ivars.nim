# Nimtalk Slot-based Instance Variables Tests
#
# Tests for the new object model with declared instance variables
#

import std/[unittest, tables, sequtils, strutils, algorithm]
import ../src/nimtalk/core/types
import ../src/nimtalk/interpreter/objects

suite "Slot-based Instance Variables (derive: message)":
  setup:
    # Initialize root object before each test
    discard initRootClass()

  test "can create object with instance variables":
    let person = initSlotObject(@["name", "age"])

    check person.hasSlotIVars()
    check person.hasSlots == true
    check person.slots.len == 2
    check person.slotNames.len == 2
    check person.slotNames.hasKey("name")
    check person.slotNames.hasKey("age")
    check person.slotNames["name"] == 0
    check person.slotNames["age"] == 1

  test "instance variables initialize to nil":
    let person = initSlotObject(@["name", "age"])

    check person.slots[0].kind == vkNil
    check person.slots[1].kind == vkNil

  test "can get and set slot values":
    var person = initSlotObject(@["name", "age"])

    # Initially nil
    check person.getSlot("name").kind == vkNil

    # Set values
    person.setSlot("name", NodeValue(kind: vkString, strVal: "Alice"))
    person.setSlot("age", NodeValue(kind: vkInt, intVal: 30))

    # Verify values
    check person.getSlot("name").kind == vkString
    check person.getSlot("name").strVal == "Alice"
    check person.getSlot("age").kind == vkInt
    check person.getSlot("age").intVal == 30

  test "symbol canonicalization works":
    # Clear symbol table first
    clearSymbolTable()

    # Create two symbols with same name
    let sym1 = getSymbol("name")
    let sym2 = getSymbol("name")

    # Should be identical (same object)
    check symbolEquals(sym1, sym2)
    check sym1.symVal == sym2.symVal

    # Different symbols should not be equal
    let sym3 = getSymbol("age")
    check not symbolEquals(sym1, sym3)

  test "symbol canonicalization across different calls":
    clearSymbolTable()

    # Simulate what parser would do
    let sym1 = getSymbol("initialize")
    let sameSym = getSymbol("initialize")
    let diffSym = getSymbol("derive")

    check symbolEquals(sym1, sameSym)
    check not symbolEquals(sym1, diffSym)

  test "symbol table maintains uniqueness":
    clearSymbolTable()

    # Create multiple symbols
    discard getSymbol("name")
    discard getSymbol("age")
    discard getSymbol("address")
    discard getSymbol("name")  # Duplicate

    # Should only have 3 unique symbols
    check symbolTable.len == 3
    check symbolTable.hasKey("name")
    check symbolTable.hasKey("age")
    check symbolTable.hasKey("address")

  test "getSlot returns nil for non-existent slots":
    let person = initSlotObject(@["name", "age"])

    check person.getSlot("nonexistent").kind == vkNil

  test "getSlotNames returns all ivar names in order":
    let person = initSlotObject(@["name", "age", "address"])
    let names = person.getSlotNames()

    check names.len == 3
    check names[0] == "name"
    check names[1] == "age"
    check names[2] == "address"

  test "RootObject has slots initialized correctly":
    let root = initRootObject()

    check root.hasSlots == false
    check root.slots.len == 0
    check root.slotNames.len == 0

  test "derive creates object without slots":
    let root = initRootObject()
    let child = deriveImpl(root, @[]).objVal

    check child.hasSlots == false
    check child.slots.len == 0

  test "derive: creates object with slots":
    let root = initRootObject()
    let ivars = @[NodeValue(kind: vkSymbol, symVal: "name"), NodeValue(kind: vkSymbol, symVal: "age")]
    let result = deriveWithIVarsImpl(root, @[NodeValue(kind: vkArray, arrayVal: ivars)])
    let child = result.objVal

    check child.hasSlots == true
    check child.slots.len == 2
    check child.slotNames.hasKey("name")
    check child.slotNames.hasKey("age")
    check child.parents.len == 1
    check child.parents[0] == root

  test "deriveinherits parent slots":
    let root = initRootObject()

    # Create parent with slots
    let parentIvars = @[NodeValue(kind: vkSymbol, symVal: "name")]
    let parentResult = deriveWithIVarsImpl(root, @[NodeValue(kind: vkArray, arrayVal: parentIvars)])
    let parent = parentResult.objVal

    # Create child with additional slots
    let childIvars = @[NodeValue(kind: vkSymbol, symVal: "age")]
    let childResult = deriveWithIVarsImpl(parent, @[NodeValue(kind: vkArray, arrayVal: childIvars)])
    let child = childResult.objVal

    # Child should have both parent and child ivars
    check child.hasSlots == true
    check child.slots.len == 2
    check child.slotNames.hasKey("name")
    check child.slotNames.hasKey("age")
    check child.slotNames["name"] == 0
    check child.slotNames["age"] == 1
    check child.parents.len == 1
    check child.parents[0] == parent

  test "derivedetects duplicate ivar names":
    let root = initRootObject()

    # Create parent with "name"
    let parentIvars = @[NodeValue(kind: vkSymbol, symVal: "name")]
    let parentResult = deriveWithIVarsImpl(root, @[NodeValue(kind: vkArray, arrayVal: parentIvars)])
    let parent = parentResult.objVal

    # Try to create child with same "name"
    let childIvars = @[NodeValue(kind: vkSymbol, symVal: "name")]
    expect(ValueError):
      discard deriveWithIVarsImpl(parent, @[NodeValue(kind: vkArray, arrayVal: childIvars)])

  test "clone preserves slots":
    var person = initSlotObject(@["name", "age"])
    person.setSlot("name", NodeValue(kind: vkString, strVal: "Alice"))
    person.setSlot("age", NodeValue(kind: vkInt, intVal: 30))

    let cloned = clone(person).objVal

    check cloned.hasSlots == true
    check cloned.slots.len == 2
    check cloned.slotNames.hasKey("name")
    check cloned.slotNames.hasKey("age")
    check cloned.getSlot("name").strVal == "Alice"
    check cloned.getSlot("age").intVal == 30

  test "clone creates independent copy":
    var person = initSlotObject(@["name"])
    person.setSlot("name", NodeValue(kind: vkString, strVal: "Alice"))

    var cloned = clone(person).objVal
    cloned.setSlot("name", NodeValue(kind: vkString, strVal: "Bob"))

    # Original should be unchanged
    check person.getSlot("name").strVal == "Alice"
    check cloned.getSlot("name").strVal == "Bob"

  test "multi-level inheritance of slots":
    let root = initRootObject()

    # Level 1: Animal
    let animalIvars = @[NodeValue(kind: vkSymbol, symVal: "species")]
    let animalResult = deriveWithIVarsImpl(root, @[NodeValue(kind: vkArray, arrayVal: animalIvars)])
    let animal = animalResult.objVal

    # Level 2: Person extends Animal
    let personIvars = @[NodeValue(kind: vkSymbol, symVal: "name")]
    let personResult = deriveWithIVarsImpl(animal, @[NodeValue(kind: vkArray, arrayVal: personIvars)])
    let person = personResult.objVal

    # Level 3: Employee extends Person
    let employeeIvars = @[NodeValue(kind: vkSymbol, symVal: "employeeID")]
    let employeeResult = deriveWithIVarsImpl(person, @[NodeValue(kind: vkArray, arrayVal: employeeIvars)])
    let employee = employeeResult.objVal

    # Verify all ivars present
    check employee.slots.len == 3
    check employee.getSlotNames().len == 3
    check employee.slotNames.hasKey("species")
    check employee.slotNames.hasKey("name")
    check employee.slotNames.hasKey("employeeID")

  test "derivewith empty array creates non-slotted object":
    let root = initRootObject()
    let emptyIvars: seq[NodeValue] = @[]
    let result = deriveWithIVarsImpl(root, @[NodeValue(kind: vkArray, arrayVal: emptyIvars)])
    let child = result.objVal

    check child.hasSlots == false
    check child.slots.len == 0

  test "can mix slotted and non-slotted in prototype chain":
    let root = initRootObject()

    # Create non-slotted parent
    let parent = deriveImpl(root, @[]).objVal

    # Create slotted child
    let childIvars = @[NodeValue(kind: vkSymbol, symVal: "value")]
    let childResult = deriveWithIVarsImpl(parent, @[NodeValue(kind: vkArray, arrayVal: childIvars)])
    let child = childResult.objVal

    check parent.hasSlots == false
    check child.hasSlots == true
    check child.slots.len == 1
    check child.parents[0] == parent

  test "property bag operations don't affect slots":
    # DictionaryObj has both slots and properties
    var person = initDictionaryObject()
    person.slotNames = {"name": 0, "age": 1}.toTable
    person.slots = @[nilValue(), nilValue()]
    person.hasSlots = true

    # Set properties (should not affect slots)
    person.properties["extra"] = NodeValue(kind: vkString, strVal: "data")

    # Verify slots unchanged
    check person.slots.len == 2
    check person.properties.len == 1
    check person.getSlot("name").kind == vkNil

  test "slot operations don't affect properties":
    var person = initDictionaryObject()
    person.slotNames = {"name": 0}.toTable
    person.slots = @[nilValue()]
    person.hasSlots = true
    person.properties["extra"] = NodeValue(kind: vkString, strVal: "data")

    # Set slot (should not affect properties)
    person.setSlot("name", NodeValue(kind: vkString, strVal: "Alice"))

    check person.properties.len == 1
    check person.properties["extra"].strVal == "data"

  test "slot initialization values":
    let ivars = @["name", "age", "active"]
    let person = initSlotObject(ivars)

    # All slots should start as nil
    for i in 0..<person.slots.len:
      check person.slots[i].kind == vkNil

    # After initialization
    person.slots[0] = NodeValue(kind: vkString, strVal: "Bob")
    person.slots[1] = NodeValue(kind: vkInt, intVal: 25)
    person.slots[2] = NodeValue(kind: vkBool, boolVal: true)

    check person.getSlot("name").strVal == "Bob"
    check person.getSlot("age").intVal == 25
    check person.getSlot("active").boolVal == true

  test "slot access is case-sensitive":
    let person = initSlotObject(@["name", "Name"])

    check person.slotNames.hasKey("name")
    check person.slotNames.hasKey("Name")
    check person.slotNames["name"] != person.slotNames["Name"]
