import std/[unittest, tables]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/interpreter/objects
import ../src/harding/runtime/runtime

# Interpreted-to-compiled dispatch.
#
# Compiled methods are exposed to the interpreter as generated shim procs with
# class and selector baked in; these test shims stand in for generated code.

proc doubleShim(interp: var Interpreter, self: Instance,
                args: seq[NodeValue]): NodeValue {.nimcall.} =
  NodeValue(kind: vkInt, intVal: args[0].intVal * 2)

proc greetShim(interp: var Interpreter, self: Instance,
               args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Inspects its receiver, proving identity survives the crossing.
  let name = if self != nil and self.class != nil: self.class.name else: "?"
  NodeValue(kind: vkString, strVal: "hello from " & name)

var nativeNilCalls = 0

proc nilOnce(self: NodeValue, args: seq[NodeValue]): NodeValue =
  inc nativeNilCalls
  nilValue()

proc missingInside(self: NodeValue, args: seq[NodeValue]): NodeValue =
  inc nativeNilCalls
  sendMessage(nil, toValue(1), "missingInCompiledBody", @[])

proc roundTripShim(interp: var Interpreter, self: Instance,
                   args: seq[NodeValue]): NodeValue {.nimcall.} =
  sendMessageInterpreted(interp, NodeValue(kind: vkInstance, instVal: self),
                         "interpreted:", args)

proc classSelfShim(interp: var Interpreter, self: NodeValue,
                   args: seq[NodeValue]): NodeValue {.nimcall.} =
  self

proc classDoubleShim(interp: var Interpreter, self: NodeValue,
                     args: seq[NodeValue]): NodeValue {.nimcall.} =
  toValue(args[0].intVal * 2)

proc newTestInterpreter(): Interpreter =
  let ctx = newSchedulerContext()
  result = ctx.mainProcess.getInterpreter()
  result.hardingHome = "."
  loadStdlib(result)

proc defineClass(interp: Interpreter, name, selector: string): Class =
  ## A class whose method exists but has no native implementation yet.
  var cls = newClass(superclasses = @[objectClass], name = name)
  let meth = createCoreMethod(selector)
  cls.methods[selector] = meth
  cls.allMethods[selector] = meth
  interp.globals[][name] = cls.toValue()
  cls

suite "Class-side engine boundary":
  let ctx = newSchedulerContext()
  var interp = ctx.mainProcess.getInterpreter()
  interp.hardingHome = "."
  loadStdlib(interp)

  teardown:
    unbindCompiledMethodsFrom(interp)

  test "class shims preserve the real class receiver and inherited identity":
    let (_, err) = interp.evalStatements("""
      ClassShimParent := Object derive: #().
      ClassShimParent class>>identity [ ^ nil ].
      ClassShimParent>>identity [ ^ 7 ].
      ClassShimChild := ClassShimParent derive: #().
    """)
    require err.len == 0
    check bindCompiledMethodShim(interp, "ClassShimParent", "identity",
                                cast[pointer](classSelfShim), isClassMethod = true)
    let parent = interp.globals[]["ClassShimParent"]
    let child = interp.globals[]["ClassShimChild"]
    check sendMessageInterpreted(interp, parent, "identity", @[]).classVal == parent.classVal
    check sendMessageInterpreted(interp, child, "identity", @[]).classVal == child.classVal
    let instance = NodeValue(kind: vkInstance, instVal: newInstance(parent.classVal))
    check sendMessageInterpreted(interp, instance, "identity", @[]).intVal == 7
    check not bindCompiledMethodShim(interp, "ClassShimParent", "identity",
                                    cast[pointer](classSelfShim), isClassMethod = true)

  test "class arguments and runtime replacements use live class-side lookup":
    let (_, err) = interp.evalStatements("""
      ClassShimGuard := Object derive: #().
      ClassShimGuard class>>double: n [ ^ 0 ].
      ClassShimOverride := ClassShimGuard derive: #().
      ClassShimOverride class>>double: n [ ^ nil ].
    """)
    require err.len == 0
    registerCompiledClassMethod("ClassShimGuard", "double:",
      proc(self: NodeValue, args: seq[NodeValue]): NodeValue = toValue(args[0].intVal * 2))
    check bindCompiledMethodShim(interp, "ClassShimGuard", "double:",
                                cast[pointer](classDoubleShim), isClassMethod = true)
    let parent = interp.globals[]["ClassShimGuard"]
    let child = interp.globals[]["ClassShimOverride"]
    check sendMessage(nil, parent, "double:", @[toValue(21)]).intVal == 42
    check isNilValue(sendMessage(nil, child, "double:", @[toValue(21)]))
    let (_, replaceError) = interp.evalStatements("ClassShimGuard class>>double: n [ ^ n + 1 ]")
    require replaceError.len == 0
    check sendMessage(nil, parent, "double:", @[toValue(21)]).intVal == 22
    check sendMessageInterpreted(interp, parent, "double:", @[toValue(21)]).intVal == 22

  test "allocation follows receiver host identity and nil is a handled result":
    discard defineClass(interp, "AllocationOwner", "identity")
    check bindCompiledMethodShim(interp, "AllocationOwner", "identity",
                                cast[pointer](greetShim))
    let owner = interp.globals[]["AllocationOwner"]
    let (_, err) = interp.evalStatements("AllocationTarget := Object derive: #(). AllocationTarget class>>new [ ^ nil ].")
    require err.len == 0
    let allocated = boundNewInstance(owner, "AllocationTarget")
    check allocated.handled
    check isNilValue(allocated.value)
    check not boundNewInstance(toValue(1), "AllocationTarget").handled
    expect ValueError:
      discard boundNewInstance(owner, "AbsentAllocationTarget")
    # A different host uses distinct live owner identity, not a global class name.
    var other = Interpreter(globals: new(Table[string, NodeValue]))
    defer: unbindCompiledMethodsFrom(other)
    let otherOwner = defineClass(other, "AllocationOwner", "identity")
    check bindCompiledMethodShim(other, "AllocationOwner", "identity", cast[pointer](greetShim))
    let otherTarget = newClass(name = "AllocationTarget")
    let factory = createCoreMethod("new")
    factory.setNativeValueImpl(cast[pointer](classSelfShim))
    factory.hasInterpreterParam = true
    otherTarget.classMethods["new"] = factory
    otherTarget.allClassMethods["new"] = factory
    other.globals[]["AllocationTarget"] = toValue(otherTarget)
    let fromOther = boundNewInstance(toValue(otherOwner), "AllocationTarget")
    check fromOther.handled
    check fromOther.value.classVal == otherTarget
    interp.globals[]["LiveSetting"] = toValue(11)
    other.globals[]["LiveSetting"] = toValue(22)
    check boundGlobalValue(owner, "LiveSetting").value.intVal == 11
    check boundGlobalValue(toValue(otherOwner), "LiveSetting").value.intVal == 22
    check boundGlobalWrite(owner, "LiveSetting", toValue(31)).value.intVal == 31
    check interp.globals[]["LiveSetting"].intVal == 31
    check other.globals[]["LiveSetting"].intVal == 22
    check isNilValue(boundGlobalWrite(toValue(otherOwner), "LiveSetting", nilValue()).value)
    check isNilValue(other.globals[]["LiveSetting"])
    check not boundGlobalWrite(toValue(1), "LiveSetting", toValue(99)).handled
    check boundGlobalValue(owner, "MissingGlobal").handled
    check isNilValue(boundGlobalValue(owner, "MissingGlobal").value)
    check sendMessageBound(toValue(otherOwner), toValue(otherTarget), "new", @[]).classVal == otherTarget
    check isNilValue(boundNewInstance(owner, "AllocationTarget").value)
    unbindCompiledMethodsFrom(interp)
    check not boundNewInstance(owner, "AllocationTarget").handled
    check not boundGlobalValue(owner, "LiveSetting").handled
    check not boundGlobalWrite(owner, "LiveSetting", toValue(99)).handled
    check interp.globals[]["LiveSetting"].intVal == 31
    check boundNewInstance(toValue(otherOwner), "AllocationTarget").handled

  test "bound super sends use lexical direct parents and restore context after errors":
    let (_, err) = interp.evalStatements("""
      SuperLeft := Object derive: #().
      SuperLeft>>value [ ^ 10 ].
      SuperRight := Object derive: #().
      SuperRight>>value [ ^ 20 ].
      SuperLexical := SuperLeft derive: #().
      SuperLexical addSuperclass: SuperRight.
      SuperLexical>>identity [ ^ nil ].
      SuperGrandchild := SuperLexical derive: #().
      SuperGrandchild>>value [ ^ 99 ].
    """)
    require err.len == 0
    check bindCompiledMethodShim(interp, "SuperLexical", "identity", cast[pointer](greetShim))
    let receiver = NodeValue(kind: vkInstance, instVal: newInstance(interp.globals[]["SuperGrandchild"].classVal))
    let previousReceiver = interp.currentReceiver
    let previousActivation = interp.currentActivation
    let previousDepth = interp.activationStack.len
    let previousSuppress = interp.suppressUncaughtExit
    check sendSuperMessage(receiver, "SuperLexical", "value", @[]).intVal == 10
    check sendSuperMessage(receiver, "SuperLexical", "value", @[], "SuperRight").intVal == 20
    expect ValueError:
      discard sendSuperMessage(receiver, "SuperLexical", "absentSuperSelector", @[])
    expect ValueError:
      discard sendSuperMessage(receiver, "SuperLexical", "value", @[], "Object")
    check interp.currentReceiver == previousReceiver
    check interp.currentActivation == previousActivation
    check interp.activationStack.len == previousDepth
    check interp.suppressUncaughtExit == previousSuppress
    check sendSuperMessage(receiver, "SuperLexical", "value", @[]).intVal == 10

  test "unknown class selector and existing native class primitive are not rebound":
    let (_, err) = interp.evalStatements("ClassShimNative := Object derive: #(). ClassShimNative class>>identity [ ^ nil ]")
    require err.len == 0
    check bindCompiledMethodShim(interp, "ClassShimNative", "identity",
                                cast[pointer](classSelfShim), isClassMethod = true)
    let cls = interp.globals[]["ClassShimNative"].classVal
    let nativePointer = cls.classMethods["identity"].nativeValueImpl
    check not bindCompiledMethodShim(interp, "ClassShimNative", "identity",
                                    cast[pointer](classDoubleShim), isClassMethod = true)
    check cls.classMethods["identity"].nativeValueImpl == nativePointer
    check not bindCompiledMethodShim(interp, "ClassShimNative", "absent",
                                    cast[pointer](classSelfShim), isClassMethod = true)

  test "detach restores interpreted bodies and allows rebind without replacing user edits":
    let (_, err) = interp.evalStatements("""
      DetachProbe := Object derive: #().
      DetachProbe>>value: n [ ^ n + 1 ].
      DetachProbe class>>identity [ ^ nil ].
    """)
    require err.len == 0
    let cls = interp.globals[]["DetachProbe"]
    let receiver = NodeValue(kind: vkInstance, instVal: newInstance(cls.classVal))
    check bindCompiledMethodShim(interp, "DetachProbe", "value:", cast[pointer](doubleShim))
    check bindCompiledMethodShim(interp, "DetachProbe", "identity", cast[pointer](classSelfShim), true)
    check sendMessageInterpreted(interp, receiver, "value:", @[toValue(3)]).intVal == 6
    unbindCompiledMethodsFrom(interp)
    check cls.classVal.methods["value:"].nativeImpl == nil
    check cls.classVal.classMethods["identity"].nativeValueImpl == nil
    check sendMessageInterpreted(interp, receiver, "value:", @[toValue(3)]).intVal == 4
    check isNilValue(sendMessageInterpreted(interp, cls, "identity", @[]))
    check bindCompiledMethodShim(interp, "DetachProbe", "value:", cast[pointer](doubleShim))
    check bindCompiledMethodShim(interp, "DetachProbe", "identity", cast[pointer](classSelfShim), true)
    let (_, replacementError) = interp.evalStatements("DetachProbe>>value: n [ ^ n + 10 ]")
    require replacementError.len == 0
    unbindCompiledMethodsFrom(interp)
    check sendMessageInterpreted(interp, receiver, "value:", @[toValue(3)]).intVal == 13
    unbindCompiledMethodsFrom(interp)

suite "Value-based mixed dispatch":
  let ctx = newSchedulerContext()
  var interp = ctx.mainProcess.getInterpreter()
  interp.hardingHome = "."
  loadStdlib(interp)
  let (_, setupError) = interp.evalStatements("""
    MixedProbe := Object derivePublic: #(stored).
    MixedProbe>>echo: argument [ ^ argument ].
    MixedProbe>>remember: argument [ stored := argument. ^ self ].
    MixedProbe>>empty [ ^ nil ].
    MixedProbe>>explode [ Error signal: "mixed failure" ].
    MixedProbe class>>answer [ ^ 42 ].
    MixedProbe>>round: n [ ^ 0 ].
    MixedProbe>>double: n [ ^ 0 ].
    MixedProbe>>interpreted: n [ ^ self double: n ].
  """)
  doAssert setupError.len == 0, setupError
  let cls = interp.globals[]["MixedProbe"].classVal
  let receiver = NodeValue(kind: vkInstance, instVal: newInstance(cls))

  setup:
    hybridInterpreter = interp
    hybridScheduler = ctx

  teardown:
    hybridInterpreter = nil
    hybridScheduler = nil
    unbindCompiledMethodsFrom(interp)

  test "objects and source-like strings cross as values":
    let payload = toValue("quotes \"\n; Error signal: \"not code\"")
    check sendMessageHybrid(receiver, "echo:", @[payload]).strVal == payload.strVal
    check sendMessageHybrid(receiver, "remember:", @[receiver]).instVal == receiver.instVal
    check sendMessageHybrid(receiver, "stored", @[]).instVal == receiver.instVal
    check sendMessageHybrid(NodeValue(kind: vkClass, classVal: cls), "answer", @[]).intVal == 42

  test "nil is a result, never a request to execute again":
    check isNilValue(sendMessageHybrid(receiver, "empty", @[]))
    let native = newInstance(newClass(name = "MixedNativeNil"))
    native.isNimProxy = true
    # A retained owner represents real native-layout storage, without dereferencing it.
    native.compiledOwner = RootRef()
    native.nimValue = cast[pointer](native.compiledOwner)
    registerCompiledMethod("MixedNativeNil", "empty", nilOnce)
    nativeNilCalls = 0
    check isNilValue(sendMessageHybrid(NodeValue(kind: vkInstance, instVal: native), "empty", @[]))
    check nativeNilCalls == 1

  test "hosted helpers refuse native ownership and preserve interpreted nil results":
    discard defineClass(interp, "HostedHelperOwner", "double:")
    let owner = interp.globals[]["HostedHelperOwner"]
    check bindCompiledMethodShim(interp, "HostedHelperOwner", "double:", cast[pointer](doubleShim))
    let nativeArray = compiledArray(@[toValue(1)])
    check not hostedBuiltin(owner, nativeArray, "size", @[]).handled
    let native = newInstance(newClass(name = "UnboundHelperNative"))
    native.isNimProxy = true
    native.compiledOwner = RootRef()
    native.nimValue = cast[pointer](native.compiledOwner)
    check not hostedBuiltin(owner, NodeValue(kind: vkInstance, instVal: native), "size", @[]).handled
    check not hostedBuiltin(owner, receiver, "==", @[receiver]).handled
    check not hostedBuiltin(owner, toValue(1), "abs", @[]).handled
    let answer = hostedBuiltin(owner, receiver, "empty", @[])
    check answer.handled
    check isNilValue(answer.value)
    unbindCompiledMethodsFrom(interp)
    check not hostedBuiltin(owner, receiver, "empty", @[]).handled

  test "runtime reference storage is initialized and released repeatedly":
    for iteration in 0..<3:
      shutdownRuntime()
      initRuntime()
      require currentRuntime != nil
      check currentRuntime[].classes.len == 0

  test "native collection owners retain native storage and identity":
    let collection = compiledArray(@[toValue(1)])
    let alias = collection
    discard sendMessageHybrid(collection, "add:", @[toValue(2)])
    check sendMessageHybrid(alias, "size", @[]).intVal == 2
    check sendMessageHybrid(collection, "class", @[]).classVal == collection.instVal.class

  test "missing interpreted sends report failure rather than silently returning nil":
    expect ValueError:
      discard sendMessageHybrid(receiver, "absentSelector", @[])
    check sendMessageHybrid(receiver, "echo:", @[receiver]).instVal == receiver.instVal

  test "a failure inside a native body does not trigger interpreted retry":
    let native = newInstance(newClass(name = "MixedNativeFailure"))
    native.isNimProxy = true
    native.compiledOwner = RootRef()
    native.nimValue = cast[pointer](native.compiledOwner)
    registerCompiledMethod("MixedNativeFailure", "run", missingInside)
    nativeNilCalls = 0
    expect CompiledHardingError:
      discard sendMessageHybrid(NodeValue(kind: vkInstance, instVal: native), "run", @[])
    check nativeNilCalls == 1

  test "block identity and captured state survive argument passing":
    let (values, err) = interp.evalStatements("Maker := [ | count | count := 0. [count := count + 1. count] ] value")
    require err.len == 0
    let original = values[^1]
    let echoed = sendMessageHybrid(receiver, "echo:", @[original])
    require echoed.kind == vkBlock
    check echoed.blockVal == original.blockVal
    check sendMessageInterpreted(interp, echoed, "value", @[]).intVal == 1
    check sendMessageInterpreted(interp, original, "value", @[]).intVal == 2

  test "native-layout proxies cannot silently enter the interpreted slot path":
    let native = newInstance(newClass(name = "MixedLayoutProbe"))
    native.isNimProxy = true
    native.compiledOwner = RootRef()
    native.nimValue = cast[pointer](native.compiledOwner)
    expect ValueError:
      discard sendMessageInterpreted(interp, NodeValue(kind: vkInstance, instVal: native),
                                     "echo:", @[toValue(1)])

  test "interpreted compiled interpreted compiled round trip":
    check bindCompiledMethodShim(interp, "MixedProbe", "round:", cast[pointer](roundTripShim))
    check bindCompiledMethodShim(interp, "MixedProbe", "double:", cast[pointer](doubleShim))
    check sendMessageHybrid(receiver, "round:", @[toValue(21)]).intVal == 42

  test "host errors propagate without quitting and later sends recover":
    let previousSuppress = interp.suppressUncaughtExit
    let previousDepth = interp.activationStack.len
    expect ValueError:
      discard sendMessageHybrid(receiver, "explode", @[])
    check interp.suppressUncaughtExit == previousSuppress
    check interp.activationStack.len == previousDepth
    check sendMessageHybrid(receiver, "echo:", @[toValue(7)]).intVal == 7

suite "Interpreted to compiled dispatch":
  # Generated ABI coverage: tests/test_engine_boundary_generated.py builds its
  # own module and embedded host under build/; see PLAN.md section 6.
  test "a bound compiled method is reachable from interpreted code":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    var cls = defineClass(interp, "BoundProbe", "double:")
    check bindCompiledMethodShim(interp, "BoundProbe", "double:", cast[pointer](doubleShim))
    check cls.methods["double:"].nativeImpl != nil

    let (result, err) = interp.evalStatements("(BoundProbe new) double: 21")
    check err.len == 0
    check result[^1].intVal == 42

  test "receiver identity survives the boundary":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    discard defineClass(interp, "GreetProbe", "greet")
    check bindCompiledMethodShim(interp, "GreetProbe", "greet", cast[pointer](greetShim))

    let (result, err) = interp.evalStatements("(GreetProbe new) greet")
    check err.len == 0
    check result[^1].strVal == "hello from GreetProbe"

  test "arguments cross the boundary unchanged":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    discard defineClass(interp, "ArgProbe", "double:")
    check bindCompiledMethodShim(interp, "ArgProbe", "double:", cast[pointer](doubleShim))

    let (result, err) = interp.evalStatements("(ArgProbe new) double: (10 + 11)")
    check err.len == 0
    check result[^1].intVal == 42

  test "an existing native implementation keeps precedence":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    var cls = defineClass(interp, "NativeKeeps", "value")
    let handWritten = cast[pointer](doubleShim)
    cls.methods["value"].nativeImpl = handWritten
    cls.methods["value"].hasInterpreterParam = true

    check not bindCompiledMethodShim(interp, "NativeKeeps", "value", cast[pointer](greetShim))
    check cls.methods["value"].nativeImpl == handWritten

  test "binding an unknown class or selector fails without side effects":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    discard defineClass(interp, "Present", "known")

    check not bindCompiledMethodShim(interp, "AbsentClass", "known", cast[pointer](doubleShim))
    check not bindCompiledMethodShim(interp, "Present", "absent", cast[pointer](doubleShim))

  test "warm compiled cache falls back after interpreted replacement":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    let cls = defineClass(interp, "GuardProbe", "double:")
    registerCompiledMethod("GuardProbe", "double:",
      proc(self: NodeValue, args: seq[NodeValue]): NodeValue =
        toValue(args[0].intVal * 2))
    check bindCompiledMethodShim(interp, "GuardProbe", "double:", cast[pointer](doubleShim))
    let instance = newInstance(cls)
    instance.isNimProxy = true
    let receiver = NodeValue(kind: vkInstance, instVal: instance)
    var cache: CompiledSendCache
    check sendMessageCached(nil, receiver, "double:", @[toValue(21)], cache).intVal == 42
    check sendMessageCached(nil, receiver, "double:", @[toValue(21)], cache).intVal == 42
    let (_, err) = interp.evalStatements("GuardProbe>>double: n [ ^ n + 1 ]")
    require err.len == 0
    check sendMessageCached(nil, receiver, "double:", @[toValue(21)], cache).intVal == 22
    check sendMessage(nil, receiver, "double:", @[toValue(21)]).intVal == 22
    check dispatchCompiledMethodFromClass(receiver, "GuardProbe", "double:", @[toValue(21)]).intVal == 22

  test "runtime subclass override wins over inherited compiled code":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    discard defineClass(interp, "GuardParent", "double:")
    registerCompiledMethod("GuardParent", "double:",
      proc(self: NodeValue, args: seq[NodeValue]): NodeValue = toValue(42))
    check bindCompiledMethodShim(interp, "GuardParent", "double:", cast[pointer](doubleShim))
    let (_, err) = interp.evalStatements("GuardChild := GuardParent derive: #(). GuardChild>>double: n [ ^ nil ]")
    require err.len == 0
    let cls = interp.globals[]["GuardChild"].classVal
    let instance = newInstance(cls)
    instance.isNimProxy = true
    var cache: CompiledSendCache
    check isNilValue(sendMessageCached(nil, NodeValue(kind: vkInstance, instVal: instance),
                                      "double:", @[toValue(21)], cache))

  test "unchanged inherited shim keeps the compiled implementation":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    discard defineClass(interp, "InheritedGuardParent", "double:")
    check bindCompiledMethodShim(interp, "InheritedGuardParent", "double:", cast[pointer](doubleShim))
    let (_, err) = interp.evalStatements("InheritedGuardChild := InheritedGuardParent derive: #()")
    require err.len == 0
    let cls = interp.globals[]["InheritedGuardChild"].classVal
    let instance = newInstance(cls)
    var cache: CompiledSendCache
    check sendMessageCached(nil, NodeValue(kind: vkInstance, instVal: instance),
                            "double:", @[toValue(21)], cache).intVal == 42
    unbindCompiledMethodsFrom(interp)

  test "binding is idempotent":
    var interp = newTestInterpreter()
    defer: unbindCompiledMethodsFrom(interp)
    var cls = defineClass(interp, "IdemProbe", "double:")
    check bindCompiledMethodShim(interp, "IdemProbe", "double:", cast[pointer](doubleShim))
    let first = cls.methods["double:"].nativeImpl
    check not bindCompiledMethodShim(interp, "IdemProbe", "double:", cast[pointer](greetShim))
    check cls.methods["double:"].nativeImpl == first
