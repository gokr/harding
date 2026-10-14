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

proc proxyReceiver(name: string): NodeValue =
  let instance = newInstance(newClass(name = name))
  instance.isNimProxy = true
  NodeValue(kind: vkInstance, instVal: instance)

suite "Compiled monomorphic send caches":
  test "receiver and selector changes never reuse a wrong target":
    let rt = newRuntime()
    let first = proxyReceiver("CacheReceiverOne")
    let second = proxyReceiver("CacheReceiverTwo")
    registerCompiledMethod("CacheReceiverOne", "answer", defaultAllocation)
    registerCompiledMethod("CacheReceiverTwo", "answer", replacementAllocation)
    registerCompiledMethod("CacheReceiverOne", "other", replacementAllocation)
    var cache: CompiledSendCache
    check sendMessageCached(rt, first, "answer", @[], cache).intVal == 1
    check sendMessageCached(rt, first, "answer", @[], cache).intVal == 1
    check sendMessageCached(rt, second, "answer", @[], cache).intVal == 2
    check sendMessageCached(rt, first, "other", @[], cache).intVal == 2

  test "cached nil results are successful sends":
    let rt = newRuntime()
    let receiver = proxyReceiver("CacheNilReceiver")
    proc nilAnswer(self: NodeValue, args: seq[NodeValue]): NodeValue =
      NodeValue(kind: vkNil)
    registerCompiledMethod("CacheNilReceiver", "answer", nilAnswer)
    var cache: CompiledSendCache
    check sendMessageCached(rt, receiver, "answer", @[], cache).kind == vkNil
    check sendMessageCached(rt, receiver, "answer", @[], cache).kind == vkNil

  test "method replacement and superclass changes invalidate targets":
    let rt = newRuntime()
    let receiver = proxyReceiver("CacheChild")
    registerCompiledMethod("CacheParentOne", "answer", defaultAllocation)
    registerCompiledMethod("CacheParentTwo", "answer", replacementAllocation)
    registerSuperclass("CacheChild", "CacheParentOne")
    var cache: CompiledSendCache
    check sendMessageCached(rt, receiver, "answer", @[], cache).intVal == 1
    registerCompiledMethod("CacheParentOne", "answer", replacementAllocation)
    check sendMessageCached(rt, receiver, "answer", @[], cache).intVal == 2
    registerSuperclass("CacheChild", "CacheParentTwo")
    check sendMessageCached(rt, receiver, "answer", @[], cache).intVal == 2
    registerCompiledMethod("CacheChild", "answer", defaultAllocation)
    check sendMessageCached(rt, receiver, "answer", @[], cache).intVal == 1

  test "fallback and later method installation remain observable":
    let rt = newRuntime()
    let receiver = proxyReceiver("CacheLateMethod")
    var cache: CompiledSendCache
    check sendMessageCached(rt, receiver, "notNil", @[], cache).boolVal
    registerCompiledMethod("CacheLateMethod", "notNil", overriddenNotNil)
    check not sendMessageCached(rt, receiver, "notNil", @[], cache).boolVal
    check sendMessageCached(rt, NodeValue(kind: vkNil), "isNil", @[], cache).boolVal

  test "user exception methods override the built-in protocol":
    let rt = newRuntime()
    let value = compiledErrorValue("Error", "original")
    value.instVal.isNimProxy = true
    registerCompiledMethod("Error", "message", replacementAllocation)
    var cache: CompiledSendCache
    # A user-defined message method wins, as it does in the interpreter.
    check sendMessageCached(rt, value, "message", @[], cache).intVal == 2
    # signal/pass/retry still take the built-in protocol path.
    check sendMessageCached(rt, value, "defaultAction", @[], cache).kind == vkInstance

  test "template evaluates receiver and arguments exactly once":
    let rt = newRuntime()
    let value = proxyReceiver("CacheEvaluationOnce")
    var calls = 0
    proc receiver(): NodeValue =
      inc calls
      return value
    proc arguments(): seq[NodeValue] =
      inc calls
      return @[]
    registerCompiledMethod("CacheEvaluationOnce", "answer", defaultAllocation)
    check cachedSend(rt, receiver(), "answer", arguments()).intVal == 1
    check calls == 2

  test "reentrant calls may replace a cache without corrupting the outer target":
    let rt = newRuntime()
    let outer = proxyReceiver("CacheReentrantOuter")
    let inner = proxyReceiver("CacheReentrantInner")
    var cache: CompiledSendCache
    proc innerAnswer(self: NodeValue, args: seq[NodeValue]): NodeValue =
      NodeValue(kind: vkInt, intVal: 2)
    proc outerAnswer(self: NodeValue, args: seq[NodeValue]): NodeValue =
      let answer = sendMessageCached(rt, inner, "answer", @[], cache)
      NodeValue(kind: vkInt, intVal: answer.intVal + 1)
    registerCompiledMethod("CacheReentrantInner", "answer", innerAnswer)
    registerCompiledMethod("CacheReentrantOuter", "answer", outerAnswer)
    check sendMessageCached(rt, outer, "answer", @[], cache).intVal == 3
    check sendMessageCached(rt, outer, "answer", @[], cache).intVal == 3

proc recoveredSelector(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkString, strVal: args[0].symVal)

suite "Compiled user-class reflection":
  test "class values and direct parents preserve declaration identity and order":
    let rt = newRuntime()
    registerCompiledClass("ReflectionNativeChild", defaultAllocation)
    registerCompiledClass("ReflectionNativeLeft", defaultAllocation)
    registerCompiledClass("ReflectionNativeRight", defaultAllocation)
    registerSuperclass("ReflectionNativeChild", "ReflectionNativeLeft")
    registerSuperclass("ReflectionNativeChild", "ReflectionNativeRight")
    let receiver = proxyReceiver("ReflectionNativeChild")
    let cls = compiledClassValue("ReflectionNativeChild")
    check sendMessage(rt, receiver, "class", @[]).classVal == cls.classVal
    check sendMessage(rt, cls, "class", @[]).classVal == cls.classVal
    check sendMessage(rt, cls, "name", @[]).strVal == "ReflectionNativeChild"
    check sendMessage(rt, receiver, "className", @[]).strVal == "ReflectionNativeChild"
    for value in [receiver, cls]:
      let parents = sendMessage(rt, value, "superclassNames", @[])
      check parents.arrayVal.len == 2
      check parents.arrayVal[0].strVal == "ReflectionNativeLeft"
      check parents.arrayVal[1].strVal == "ReflectionNativeRight"
    let base = compiledBaseClassValue("Object")
    check base.kind == vkClass
    check base.classVal == compiledBaseClassValue("Object").classVal
    registerSuperclass("ReflectionNativeLeft", "Object")
    check sendMessage(rt, receiver, "isKindOf:", @[base]).boolVal
    check sendMessage(rt, receiver, "isKindOf:", @[compiledBaseClassValue("Root")]).boolVal
    check not sendMessage(rt, receiver, "isKindOf:", @[compiledBaseClassValue("Mixin")]).boolVal
    check sendMessage(rt, receiver, "isKindOf:",
                      @[compiledClassValue("ReflectionNativeRight")]).boolVal
    for target in [toValue("ReflectionNativeRight"), toSymbol("ReflectionNativeRight"), toValue(42)]:
      check not sendMessage(rt, receiver, "isKindOf:", @[target]).boolVal
    registerSuperclass("ReflectionNativeRight", "ReflectionNativeAncestor")
    registerCompiledClass("ReflectionNativeAncestor", defaultAllocation)
    check sendMessage(rt, receiver, "isKindOf:",
                      @[compiledClassValue("ReflectionNativeAncestor")]).boolVal
    registerSuperclass("ReflectionNativeAncestor", "ReflectionNativeChild")
    registerCompiledClass("ReflectionNativeUnrelated", defaultAllocation)
    check not sendMessage(rt, receiver, "isKindOf:",
                          @[compiledClassValue("ReflectionNativeUnrelated")]).boolVal

suite "Compiled identity sends":
  test "generic and cached sends cannot replace identity with an override":
    let rt = newRuntime()
    let first = proxyReceiver("IdentityReceiverTest")
    let second = proxyReceiver("IdentityReceiverTest")
    registerCompiledMethod("IdentityReceiverTest", "==", overriddenNotNil)
    registerCompiledMethod("IdentityReceiverTest", "~=", overriddenNotNil)
    var cache: CompiledSendCache
    check sendMessage(rt, first, "==", @[first]).boolVal
    check not sendMessage(rt, first, "==", @[second]).boolVal
    check sendMessageCached(rt, first, "==", @[first], cache).boolVal
    check sendMessageCached(rt, first, "~=", @[second], cache).boolVal
    check not sendMessageCached(rt, first, "~=", @[first], cache).boolVal
    registerCompiledClass("IdentityReceiverTest", defaultAllocation)
    let cls = compiledClassValue("IdentityReceiverTest")
    check sendMessage(rt, cls, "==", @[cls]).boolVal
    check not sendMessage(rt, cls, "==", @[first]).boolVal

  test "wrappers for retained compiled storage share identity":
    let owner = RootRef()
    let first = NodeValue(kind: vkInstance, instVal: Instance(kind: ikObject,
      compiledOwner: owner, isNimProxy: true))
    let second = NodeValue(kind: vkInstance, instVal: Instance(kind: ikObject,
      compiledOwner: owner, isNimProxy: true))
    let other = NodeValue(kind: vkInstance, instVal: Instance(kind: ikObject,
      compiledOwner: RootRef(), isNimProxy: true))
    check first.instVal != second.instVal
    check compiledIdentityEqual(first, second)
    check not compiledIdentityEqual(first, other)
    check sendMessage(newRuntime(), first, "==", @[second]).boolVal

suite "Compiled qualified super sends":
  test "qualifiers select a direct parent and preserve receiver and arguments":
    let receiver = proxyReceiver("QualifiedSuperDescendant")
    registerSuperclass("QualifiedSuperDescendant", "QualifiedSuperChild")
    registerSuperclass("QualifiedSuperChild", "QualifiedSuperFirst")
    registerSuperclass("QualifiedSuperChild", "QualifiedSuperSecond")
    registerCompiledMethod("QualifiedSuperFirst", "answer", defaultAllocation)
    registerCompiledMethod("QualifiedSuperSecond", "answer", replacementAllocation)
    check sendSuperMessage(receiver, "QualifiedSuperChild", "answer", @[]).intVal == 1
    check sendSuperMessage(receiver, "QualifiedSuperChild", "answer", @[],
                           "QualifiedSuperSecond").intVal == 2
    proc echoReceiver(self: NodeValue, args: seq[NodeValue]): NodeValue = self
    proc echoArgument(self: NodeValue, args: seq[NodeValue]): NodeValue = args[0]
    registerCompiledMethod("QualifiedSuperSecond", "receiver", echoReceiver)
    registerCompiledMethod("QualifiedSuperSecond", "argument:", echoArgument)
    check sendSuperMessage(receiver, "QualifiedSuperChild", "receiver", @[],
                           "QualifiedSuperSecond").instVal == receiver.instVal
    check sendSuperMessage(receiver, "QualifiedSuperChild", "argument:",
                           @[nilValue()], "QualifiedSuperSecond").kind == vkNil
    registerCompiledClass("QualifiedSuperDescendant", defaultAllocation)
    registerCompiledClassMethod("QualifiedSuperFirst", "answer", defaultAllocation)
    registerCompiledClassMethod("QualifiedSuperSecond", "answer", replacementAllocation)
    let classReceiver = compiledClassValue("QualifiedSuperDescendant")
    check sendSuperMessage(classReceiver, "QualifiedSuperChild", "answer", @[],
                           "QualifiedSuperSecond").intVal == 2
    registerCompiledClassMethod("QualifiedSuperSecond", "receiver", echoReceiver)
    check sendSuperMessage(classReceiver, "QualifiedSuperChild", "receiver", @[],
                           "QualifiedSuperSecond").classVal == classReceiver.classVal
    registerSuperclass("QualifiedSuperSecond", "QualifiedSuperAncestor")
    registerCompiledMethod("QualifiedSuperAncestor", "inheritedAnswer", replacementAllocation)
    registerCompiledClassMethod("QualifiedSuperAncestor", "inheritedAnswer", replacementAllocation)
    check sendSuperMessage(receiver, "QualifiedSuperChild", "inheritedAnswer", @[],
                           "QualifiedSuperSecond").intVal == 2
    check sendSuperMessage(classReceiver, "QualifiedSuperChild", "inheritedAnswer", @[],
                           "QualifiedSuperSecond").intVal == 2

  test "unrelated classes and indirect ancestors are not valid qualifiers":
    registerSuperclass("QualifiedSuperGuardChild", "QualifiedSuperGuardParent")
    registerSuperclass("QualifiedSuperGuardParent", "QualifiedSuperGuardAncestor")
    registerCompiledMethod("QualifiedSuperUnrelated", "answer", replacementAllocation)
    let receiver = proxyReceiver("QualifiedSuperGuardChild")
    for qualifier in ["QualifiedSuperUnrelated", "QualifiedSuperGuardAncestor", "UnknownSuperParent"]:
      var caught = false
      try:
        discard sendSuperMessage(receiver, "QualifiedSuperGuardChild", "answer", @[], qualifier)
      except ValueError as failure:
        caught = true
        check failure.msg == "Parent class '" & qualifier & "' not found in inheritance chain"
      check caught
    registerCompiledClass("QualifiedSuperGuardChild", defaultAllocation)
    expect ValueError:
      discard sendSuperMessage(compiledClassValue("QualifiedSuperGuardChild"),
                               "QualifiedSuperGuardChild", "answer", @[], "QualifiedSuperUnrelated")

suite "Compiled missing messages":
  test "immediate and class misses carry a catchable Harding error":
    let rt = newRuntime()
    for receiver in [NodeValue(kind: vkInt, intVal: 1), NodeValue(kind: vkNil)]:
      var caught = false
      try:
        discard sendMessage(rt, receiver, "absent", @[])
      except CompiledHardingError as failure:
        caught = true
        check failure.value.instVal.class.name == "MessageNotUnderstood"
        check failure.value.instVal.slots[0].strVal == "Message not understood: absent"
      check caught
    registerCompiledClass("MissingClassTest", defaultAllocation)
    expect CompiledHardingError:
      discard sendMessage(rt, compiledClassValue("MissingClassTest"), "absent", @[])

  test "custom inherited DNU may recover and may return nil":
    let rt = newRuntime()
    let receiver = proxyReceiver("DnuChildTest")
    registerSuperclass("DnuChildTest", "DnuParentTest")
    registerCompiledMethod("DnuParentTest", "doesNotUnderstand:", recoveredSelector)
    var cache: CompiledSendCache
    check sendMessageCached(rt, receiver, "absent", @[], cache).strVal == "absent"
    check sendMessageCached(rt, receiver, "another", @[], cache).strVal == "another"
    proc nilRecovery(self: NodeValue, args: seq[NodeValue]): NodeValue =
      NodeValue(kind: vkNil)
    registerCompiledMethod("DnuParentTest", "doesNotUnderstand:", nilRecovery)
    check sendMessageCached(rt, receiver, "absent", @[], cache).kind == vkNil

  test "super lookup failure raises rather than answering nil":
    let receiver = proxyReceiver("MissingSuperTest")
    expect CompiledHardingError:
      discard sendSuperMessage(receiver, "MissingSuperTest", "absent", @[])
