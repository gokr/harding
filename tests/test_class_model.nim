#
# test_class_model.nim - Unit tests for Object Model
#

import std/[unittest, tables, strutils]
import ../src/nimtalk/core/types
import ../src/nimtalk/interpreter/[objects, activation]

suite "Class Object Model":

  setup:
    # Create fresh classes for each test
    let rootClass = newClass(name = "Object")
    rootClass.allMethods = initTable[string, BlockNode]()
    rootClass.allClassMethods = initTable[string, BlockNode]()

  test "Class creation with basic fields":
    let cls = newClass(name = "TestClass")
    check(cls.name == "TestClass")
    check(cls.parents.len == 0)
    check(cls.subclasses.len == 0)
    check(cls.slotNames.len == 0)
    check(cls.allSlotNames.len == 0)
    check(cls.methods.len == 0)
    check(cls.allMethods.len == 0)
    check(cls.hasSlots == false)

  test "Class creation with slots":
    let cls = newClass(slotNames = @["name", "age"], name = "Person")
    check(cls.slotNames.len == 2)
    check(cls.slotNames[0] == "name")
    check(cls.slotNames[1] == "age")
    check(cls.hasSlots == true)

  test "Instance creation":
    let cls = newClass(slotNames = @["x", "y"], name = "Point")
    cls.allSlotNames = @["x", "y"]  # Simulate parent layout

    let inst = newInstance(cls)
    check(inst.class == cls)
    check(inst.slots.len == 2)
    check(inst.slots[0].kind == vkNil)
    check(inst.slots[1].kind == vkNil)

  test "Slot access by index":
    let cls = newClass(slotNames = @["value"], name = "Cell")
    cls.allSlotNames = @["value"]

    let inst = newInstance(cls)
    setSlot(inst, 0, toValue(42))
    check(getSlot(inst, 0).kind == vkInt)
    check(getSlot(inst, 0).intVal == 42)

  test "Slot index lookup":
    let cls = newClass(slotNames = @["a", "b", "c"], name = "ABC")
    cls.allSlotNames = @["a", "b", "c"]

    check(getSlotIndex(cls, "a") == 0)
    check(getSlotIndex(cls, "b") == 1)
    check(getSlotIndex(cls, "c") == 2)
    check(getSlotIndex(cls, "nonexistent") == -1)

  test "Derive class inherits parent slots":
    let parent = newClass(slotNames = @["x"], name = "Parent")
    parent.allSlotNames = @["x"]

    let child = newClass(parents = @[parent], slotNames = @["y"], name = "Child")
    child.allSlotNames = parent.allSlotNames & child.slotNames

    check(child.allSlotNames.len == 2)
    check(child.allSlotNames[0] == "x")
    check(child.allSlotNames[1] == "y")
    check(child.hasSlots == true)

  test "Slot conflict detection":
    let parent = newClass(slotNames = @["name"], name = "Parent")
    # parent.allSlotNames is already set by newClass

    # Should raise error during class creation due to slot name conflict
    expect ValueError:
      discard newClass(parents = @[parent], slotNames = @["name"], name = "Child")

  test "Subclass registration":
    let parent = newClass(name = "Parent")
    let child = newClass(parents = @[parent], name = "Child")

    # newClass automatically registers child as subclass
    check(parent.subclasses.len == 1)
    check(parent.subclasses[0] == child)

  test "Method merging on derive":
    let parent = newClass(name = "Parent")
    let meth1 = BlockNode()
    meth1.isMethod = true
    parent.allMethods["greet"] = meth1

    let child = newClass(parents = @[parent], name = "Child")
    # Copy parent's merged methods (shallow copy)
    child.allMethods = parent.allMethods

    check("greet" in child.allMethods)
    check(child.allMethods["greet"] == meth1)

  test "Own methods override inherited":
    let parent = newClass(name = "Parent")
    let parentMeth = BlockNode()
    parentMeth.isMethod = true
    parent.allMethods["greet"] = parentMeth

    let child = newClass(parents = @[parent], name = "Child")
    child.allMethods = parent.allMethods

    let childMeth = BlockNode()
    childMeth.isMethod = true
    child.methods["greet"] = childMeth
    child.allMethods["greet"] = childMeth

    check(child.allMethods["greet"] == childMeth)

  test "Invalidation propagates to subclasses":
    let grandparent = newClass(name = "Grandparent")
    let parent = newClass(parents = @[grandparent], name = "Parent")
    let child = newClass(parents = @[parent], name = "Child")

    # Add initial method to grandparent
    let meth1 = BlockNode()
    meth1.isMethod = true
    addMethodToClass(grandparent, "foo", meth1, false)

    # Check that foo is inherited through the chain
    check("foo" in parent.allMethods)
    check("foo" in child.allMethods)

    # Add method to grandparent and trigger invalidation
    let meth2 = BlockNode()
    meth2.isMethod = true
    addMethodToClass(grandparent, "bar", meth2, false)

    # Check that bar propagated to all subclasses
    check("bar" in parent.allMethods)
    check("bar" in child.allMethods)

  test "Multiple inheritance method conflict error":
    let trait1 = newClass(name = "Trait1")
    let trait2 = newClass(name = "Trait2")

    let meth1 = BlockNode()
    meth1.isMethod = true
    # Use addMethodToClass to properly add methods (updates both methods and allMethods)
    addMethodToClass(trait1, "shared", meth1)

    let meth2 = BlockNode()
    meth2.isMethod = true
    addMethodToClass(trait2, "shared", meth2)

    # Deriving from both parents with conflicting methods should error
    expect ValueError:
      discard newClass(parents = @[trait1, trait2], name = "Child")

  test "Multiple inheritance with child override":
    let trait1 = newClass(name = "Trait1")
    let trait2 = newClass(name = "Trait2")

    let meth1 = BlockNode()
    meth1.isMethod = true
    trait1.allMethods["foo"] = meth1

    let meth2 = BlockNode()
    meth2.isMethod = true
    trait2.allMethods["bar"] = meth2

    # No conflict - each parent has different methods
    let child = newClass(parents = @[trait1, trait2], name = "Child")

    # Child should inherit both methods
    check(child.allMethods["foo"] == meth1)
    check(child.allMethods["bar"] == meth2)

    # Child can add its own override
    let overrideMeth = BlockNode()
    overrideMeth.isMethod = true
    child.methods["foo"] = overrideMeth
    child.allMethods["foo"] = overrideMeth

    check(child.allMethods["foo"] == overrideMeth)
    check(child.allMethods["bar"] == meth2)

  test "Instance method lookup":
    let cls = newClass(name = "Test")
    let meth = BlockNode()
    meth.isMethod = true
    cls.allMethods["test"] = meth

    check(lookupInstanceMethod(cls, "test") == meth)
    check(lookupInstanceMethod(cls, "nonexistent") == nil)

  test "Class method lookup":
    let cls = newClass(name = "Test")
    let meth = BlockNode()
    meth.isMethod = true
    cls.allClassMethods["new"] = meth

    check(lookupClassMethod(cls, "new") == meth)
    check(lookupClassMethod(cls, "nonexistent") == nil)

  test "Slot accessor AST node creation":
    let node = SlotAccessNode(
      slotName: "testSlot",
      slotIndex: 5,
      isAssignment: false
    )
    check(node.slotName == "testSlot")
    check(node.slotIndex == 5)
    check(node.isAssignment == false)

  test "Slot accessor node kind":
    let node = SlotAccessNode()
    node.slotName = "x"
    node.slotIndex = 0
    node.isAssignment = true

    # Check node kind is correctly identified
    check(node.kind == nkSlotAccess)

  test "rebuildAllTables merges correctly":
    let parent1 = newClass(name = "Parent1")
    let parent2 = newClass(name = "Parent2")

    parent1.allMethods["method1"] = BlockNode()
    parent1.allMethods["method1"].isMethod = true
    parent2.allMethods["method2"] = BlockNode()
    parent2.allMethods["method2"].isMethod = true

    let child = newClass(parents = @[parent1, parent2], name = "Child")
    rebuildAllTables(child)

    check("method1" in child.allMethods)
    check("method2" in child.allMethods)

  test "rebuildAllTables handles slot merging":
    let parent1 = newClass(slotNames = @["a"], name = "Parent1")
    parent1.allSlotNames = @["a"]

    let parent2 = newClass(slotNames = @["b"], name = "Parent2")
    parent2.allSlotNames = @["b"]

    let child = newClass(parents = @[parent1, parent2], slotNames = @["c"], name = "Child")
    rebuildAllTables(child)

    check(child.allSlotNames.len == 3)
    check("a" in child.allSlotNames)
    check("b" in child.allSlotNames)
    check("c" in child.allSlotNames)

  test "Class with no slots has hasSlots=false":
    let cls = newClass(name = "Empty")
    rebuildAllTables(cls)
    check(cls.hasSlots == false)

  test "Class with slots has hasSlots=true":
    let cls = newClass(slotNames = @["data"], name = "Data")
    rebuildAllTables(cls)
    check(cls.hasSlots == true)
