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

suite "Interpreted to compiled dispatch":
  # The generated-module variant lives in build/test_engine_boundary_generated.nim
  # because it depends on a generated artifact; see PLAN.md section 6.
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
