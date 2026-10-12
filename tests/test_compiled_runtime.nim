import std/unittest
import ../src/harding/core/types
import ../src/harding/runtime/runtime

proc overriddenNotNil(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkBool, boolVal: false)

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
