import std/unittest
import ../src/harding/core/types
import ../src/harding/runtime/runtime

var initializations = 0
proc initialize(self: NodeValue, args: seq[NodeValue]): NodeValue =
  inc initializations
  self

initRuntime()

suite "Native Object allocation":
  test "new and basicNew allocate distinct instances with the canonical class":
    let cls = compiledBaseClassValue("Object")
    let first = sendMessage(currentRuntime[], cls, "new", @[])
    let second = sendMessage(currentRuntime[], cls, "basicNew", @[])
    check first.kind == vkInstance
    check second.kind == vkInstance
    check first.instVal != second.instVal
    check first.instVal.class == cls.classVal
    check second.instVal.class == cls.classVal
    check sendMessage(currentRuntime[], first, "class", @[]).classVal == cls.classVal
    check sendMessage(currentRuntime[], cls, "respondsTo:", @[toValue("new")]).boolVal
    check sendMessage(currentRuntime[], cls, "respondsTo:", @[toValue("basicNew")]).boolVal

  test "new invokes the live initializer while basicNew bypasses it":
    registerCompiledMethod("Object", "initialize", initialize)
    let cls = compiledBaseClassValue("Object")
    discard sendMessage(currentRuntime[], cls, "new", @[])
    check initializations == 1
    discard sendMessage(currentRuntime[], cls, "basicNew", @[])
    check initializations == 1
