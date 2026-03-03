# Harding Slot Tests
#
# Tests for the new class-based object model with declared slots
#

import std/[unittest, tables]
import ../src/harding/interpreter/objects
import ../src/harding/core/types

suite "Slots (class-based model)":
  setup:
    # Clean state before each test - reinitialize globals
    initGlobals()  # This will only reset if empty, but needed for clean slate
    if globals.len > 0:
      globals.clear()
    clearSymbolTable()

  test "Root class has no slots":
    let root = initRootClass()

    check root.hasSlots == false
    check root.slotNames.len == 0
    check root.allSlotNames.len == 0

  test "Object class has no slots by default":
    discard initRootClass()
    let obj = initObjectClass()

    check obj.hasSlots == false
    check obj.slotNames.len == 0
    check obj.allSlotNames.len == 0

  test "can create class with slots":
    discard initRootClass()
    let personClass = newClass(superclasses = @[rootClass], slotNames = @["name", "age"], name = "Person")

    check personClass.hasSlots == true
    check personClass.slotNames.len == 2
    check personClass.allSlotNames.len == 2
    check "name" in personClass.slotNames
    check "age" in personClass.slotNames

  test "can create instance with slots":
    discard initRootClass()
    let personClass = newClass(superclasses = @[rootClass], slotNames = @["name", "age"], name = "Person")
    let person = newInstance(personClass)

    check person.kind == ikObject
    check person.slots.len == 2
    check person.slots[0].kind == vkNil
    check person.slots[1].kind == vkNil

  test "slots initialize to nil":
    discard initRootClass()
    let personClass = newClass(superclasses = @[rootClass], slotNames = @["name", "age"], name = "Person")
    let person = newInstance(personClass)

    check person.slots[0].kind == vkNil
    check person.slots[1].kind == vkNil

  test "can get and set slot values":
    discard initRootClass()
    let personClass = newClass(superclasses = @[rootClass], slotNames = @["name", "age"], name = "Person")
    var person = newInstance(personClass)

    # Initially nil
    check person.slots[0].kind == vkNil

    # Set values
    person.slots[0] = NodeValue(kind: vkString, strVal: "Alice")
    person.slots[1] = NodeValue(kind: vkInt, intVal: 30)

    # Verify values
    check person.slots[0].kind == vkString
    check person.slots[0].strVal == "Alice"
    check person.slots[1].kind == vkInt
    check person.slots[1].intVal == 30

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

  test "multi-level inheritance of slots":
    discard initRootClass()

    # Level 1: Animal
    let animalClass = newClass(superclasses = @[rootClass], slotNames = @["species"], name = "Animal")

    # Level 2: Person extends Animal
    let personClass = newClass(superclasses = @[animalClass], slotNames = @["name"], name = "Person")

    # Level 3: Employee extends Person
    let employeeClass = newClass(superclasses = @[personClass], slotNames = @["employeeID"], name = "Employee")

    # Verify all ivars present in Employee
    check employeeClass.slotNames.len == 1
    check employeeClass.allSlotNames.len == 3
    check "species" in employeeClass.allSlotNames
    check "name" in employeeClass.allSlotNames
    check "employeeID" in employeeClass.allSlotNames

    # Verify instance has 3 slots
    let employee = newInstance(employeeClass)
    check employee.slots.len == 3

  test "class without slots creates instance without slots":
    discard initRootClass()
    let simpleClass = newClass(superclasses = @[rootClass], slotNames = @[], name = "Simple")

    check simpleClass.hasSlots == false
    check simpleClass.slotNames.len == 0
    check simpleClass.allSlotNames.len == 0

  test "can mix slotted and non-slotted in inheritance chain":
    discard initRootClass()

    # Create non-slotted parent
    let parentClass = newClass(superclasses = @[rootClass], slotNames = @[], name = "Parent")
    check parentClass.hasSlots == false

    # Create slotted child
    let childClass = newClass(superclasses = @[parentClass], slotNames = @["value"], name = "Child")
    check childClass.hasSlots == true
    check childClass.slotNames.len == 1
    check childClass.allSlotNames.len == 1

    # Verify instance
    let child = newInstance(childClass)
    check child.slots.len == 1

  test "slot access works by index position":
    discard initRootClass()
    let personClass = newClass(superclasses = @[rootClass], slotNames = @["name", "age", "address"], name = "Person")
    var person = newInstance(personClass)

    person.slots[0] = NodeValue(kind: vkString, strVal: "Alice")
    person.slots[1] = NodeValue(kind: vkInt, intVal: 30)
    person.slots[2] = NodeValue(kind: vkString, strVal: "Monaco")

    check person.slots[0].strVal == "Alice"
    check person.slots[1].intVal == 30
    check person.slots[2].strVal == "Monaco"

  test "slot initialization values":
    discard initRootClass()
    let personClass = newClass(superclasses = @[rootClass], slotNames = @["name", "age", "active"], name = "Person")
    var person = newInstance(personClass)

    # All slots should start as nil
    for i in 0..<person.slots.len:
      check person.slots[i].kind == vkNil

    # After initialization
    person.slots[0] = NodeValue(kind: vkString, strVal: "Bob")
    person.slots[1] = NodeValue(kind: vkInt, intVal: 25)
    person.slots[2] = NodeValue(kind: vkBool, boolVal: true)

    check person.slots[0].strVal == "Bob"
    check person.slots[1].intVal == 25
    check person.slots[2].boolVal == true

  test "slot names are case-sensitive":
    discard initRootClass()
    let testClass = newClass(superclasses = @[rootClass], slotNames = @["name", "Name"], name = "Test")

    # Both should be distinct slot names
    check testClass.slotNames[0] == "name"
    check testClass.slotNames[1] == "Name"
    check testClass.slotNames.len == 2
    check testClass.allSlotNames.len == 2

  test "instance can store any NodeValue type in slots":
    discard initRootClass()
    let flexibleClass = newClass(superclasses = @[rootClass], slotNames = @["intValue", "boolValue", "strValue", "nilValue"], name = "Flexible")
    var inst = newInstance(flexibleClass)

    inst.slots[0] = NodeValue(kind: vkInt, intVal: 42)
    inst.slots[1] = NodeValue(kind: vkBool, boolVal: true)
    inst.slots[2] = NodeValue(kind: vkString, strVal: "hello")
    inst.slots[3] = NodeValue(kind: vkNil)

    check inst.slots[0].intVal == 42
    check inst.slots[1].boolVal == true
    check inst.slots[2].strVal == "hello"
    check inst.slots[3].kind == vkNil

  test "class knows if it has slots":
    discard initRootClass()

    let emptyClass = newClass(superclasses = @[rootClass], slotNames = @[], name = "Empty")
    let slottedClass = newClass(superclasses = @[rootClass], slotNames = @["value"], name = "Slotted")

    check emptyClass.hasSlots == false
    check slottedClass.hasSlots == true

  test "class maintains slot name order":
    discard initRootClass()
    let orderedClass = newClass(superclasses = @[rootClass], slotNames = @["c", "b", "a"], name = "Ordered")

    check orderedClass.slotNames[0] == "c"
    check orderedClass.slotNames[1] == "b"
    check orderedClass.slotNames[2] == "a"

  test "instance class reference is correct":
    discard initRootClass()
    let myClass = newClass(superclasses = @[rootClass], slotNames = @["x"], name = "MyClass")
    let inst = newInstance(myClass)

    check inst.class == myClass
    check inst.class.name == "MyClass"
