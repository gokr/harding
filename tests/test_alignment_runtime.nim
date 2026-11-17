import std/unittest
import ../src/harding/core/types
import ../src/harding/runtime/runtime
import ../src/harding/runtime/compiled_support
import ../src/harding/runtime/primitive_impls

proc protocolAnswer(self: NodeValue, args: openArray[NodeValue]): NodeValue =
  toValue("object-protocol")

proc classAnswer(self: NodeValue, args: openArray[NodeValue]): NodeValue =
  toValue("class-override")

proc defaultAlignmentAllocation(self: NodeValue, args: openArray[NodeValue]): NodeValue =
  compiledArray(@[])

suite "Alignment runtime boundaries":
  test "array primitive rejects boundary, negative and invalid indices":
    let receiver = compiledArray(@[toValue(1), toValue(2)])
    for index in [toValue(2), toValue(-1), toValue(8), toValue("bad")]:
      expect CompiledHardingError:
        discard primitiveArrayAtPut(receiver, @[index, toValue(9)])
    check receiver.instVal.elements.len == 2
    check receiver.instVal.elements[0].intVal == 1
    check primitiveArrayAtPut(receiver, @[toValue(1), toValue(7)]).intVal == 7
    check receiver.instVal.elements[1].intVal == 7

  test "raw array helper rejects invalid writes and answers the assigned value":
    let receiver = NodeValue(kind: vkArray, arrayVal: @[toValue(1)])
    for index in [toValue(1), toValue(-1), toValue(8), toValue("bad")]:
      expect CompiledHardingError:
        discard nt_at_kput_k(receiver, index, toValue(9))
      expect CompiledHardingError:
        discard sendMessage(nil, receiver, "at:put:", @[index, toValue(9)])
    check nt_at_kput_k(receiver, toValue(0), toValue(7)).intVal == 7

  test "unregistered array storage fallback signals instead of dropping writes":
    let cls = newClass(name = "AlignmentBareStorage")
    let receiver = NodeValue(kind: vkInstance,
      instVal: newArrayInstance(cls, @[toValue(1)]))
    for index in [toValue(1), toValue(-1), toValue("bad")]:
      expect CompiledHardingError:
        discard sendMessage(nil, receiver, "at:put:", @[index, toValue(9)])
    check receiver.instVal.elements.len == 1

  test "class protocol fallback does not need a Class superclass registration":
    registerCompiledClass("AlignmentProtocolClass", defaultAlignmentAllocation)
    registerCompiledMethod("Object", "alignmentProtocol", protocolAnswer)
    let receiver = compiledClassValue("AlignmentProtocolClass")
    require receiver.kind == vkClass
    check sendMessage(nil, receiver, "alignmentProtocol", @[]).strVal == "object-protocol"
    registerCompiledClassMethod("AlignmentProtocolClass", "alignmentProtocol", classAnswer)
    check sendMessage(nil, receiver, "alignmentProtocol", @[]).strVal == "class-override"

  test "class-side super misses do not use the ordinary Object protocol fallback":
    registerSuperclass("AlignmentSuperChild", "AlignmentSuperParent")
    registerCompiledMethod("Object", "alignmentOnlyInstance", protocolAnswer)
    expect CompiledHardingError:
      discard sendSuperMessage(compiledClassValue("AlignmentSuperChild"),
        "AlignmentSuperChild", "alignmentOnlyInstance", @[])
