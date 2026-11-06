import std/unittest
import ../src/harding/core/types
import ../src/harding/runtime/runtime

proc first(self: NodeValue, args: seq[NodeValue]): NodeValue = toValue(11)
proc second(self: NodeValue, args: seq[NodeValue]): NodeValue = toValue(22)

suite "Compiled value method dispatch":
  test "immediate registrations and replacements reach generic and cached sends":
    for entry in [("Integer", toValue(5)), ("String", toValue("text")),
                  ("True", toValue(true)), ("False", toValue(false)),
                  ("UndefinedObject", nilValue())]:
      let (name, receiver) = entry
      var cache: CompiledSendCache
      registerCompiledMethod(name, "graniteValueProbe", first)
      check sendMessage(nil, receiver, "graniteValueProbe", @[]).intVal == 11
      check sendMessageCached(nil, receiver, "graniteValueProbe", @[], cache).intVal == 11
      registerCompiledMethod(name, "graniteValueProbe", second)
      check sendMessageCached(nil, receiver, "graniteValueProbe", @[], cache).intVal == 22
      check sendMessage(nil, receiver, "graniteValueProbe", @[]).intVal == 22
