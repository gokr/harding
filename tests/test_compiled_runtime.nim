import std/unittest
import ../src/harding/core/types
import ../src/harding/runtime/runtime

proc overriddenNotNil(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkBool, boolVal: false)

proc defaultAllocation(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkInt, intVal: 1)

proc replacementAllocation(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkInt, intVal: 2)

suite "Compiled runtime nil predicates":
  test "nil and immediate values":
    let rt = newRuntime()
    check sendMessage(rt, nilValue(), "isNil", @[]).boolVal
    check not sendMessage(rt, nilValue(), "notNil", @[]).boolVal
    let number = NodeValue(kind: vkInt, intVal: 42)
    check not sendMessage(rt, number, "isNil", @[]).boolVal
    check sendMessage(rt, number, "notNil", @[]).boolVal

  test "registered methods take precedence over builtin fallback":
    let rt = newRuntime()
    let cls = newClass(name = "NilPredicateOverrideTest")
    let instance = newInstance(cls)
    instance.isNimProxy = true
    let receiver = NodeValue(kind: vkInstance, instVal: instance)
    registerCompiledMethod(cls.name, "notNil", overriddenNotNil)
    check not sendMessage(rt, receiver, "notNil", @[]).boolVal

suite "Compiled guarded allocation":
  test "default allocator guard is invalidated by replacement":
    let name = "GuardedAllocationTest"
    registerCompiledClass(name, defaultAllocation)
    check canDirectAllocate(name, defaultAllocation)
    let previousVersion = compiledClassDispatchVersion
    registerCompiledClass(name, replacementAllocation)
    check compiledClassDispatchVersion != previousVersion
    check not canDirectAllocate(name, defaultAllocation)

  test "inherited new overrides and superclass changes invalidate guard":
    let name = "GuardedAllocationChildTest"
    let parent = "GuardedAllocationParentTest"
    registerCompiledClass(name, defaultAllocation)
    check canDirectAllocate(name, defaultAllocation)
    var previousVersion = compiledClassDispatchVersion
    registerCompiledClassMethod(parent, "new", replacementAllocation)
    check compiledClassDispatchVersion != previousVersion
    previousVersion = compiledClassDispatchVersion
    registerSuperclass(name, parent)
    check compiledClassDispatchVersion != previousVersion
    check not canDirectAllocate(name, defaultAllocation)
    check sendMessage(newRuntime(), compiledClassValue(name), "new", @[]).intVal == 2
