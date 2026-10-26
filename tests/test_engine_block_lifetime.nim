import std/[unittest, tables]
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ../src/harding/runtime/runtime
import ../src/harding/runtime/compiled_support

proc freshHost(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  loadStdlib(result)

var
  savedCallback: NodeValue
  releasedOwners = 0

type LifetimeOwner = object of RootObj
  armed: bool

proc `=destroy`(owner: LifetimeOwner) =
  if owner.armed:
    inc releasedOwners

proc ownershipProbe(): BlockNode =
  var host = Interpreter(rootObject: Instance(kind: ikObject))
  host.rootObject.compiledOwner = (ref LifetimeOwner)(armed: true)
  result = BlockNode()
  bindInterpretedBlockHost(host, result)

proc retainingShim(interp: var Interpreter, self: Instance,
                   args: seq[NodeValue]): NodeValue {.nimcall.} =
  savedCallback = args[0]
  toValue(true)

proc retainedBlock(): NodeValue =
  var host = freshHost()
  host.globals[]["LifetimeSetting"] = toValue(42)
  let (value, error) = host.doit("[LifetimeSetting]")
  doAssert error.len == 0, error
  bindInterpretedBlockHost(host, value.blockVal)
  value

suite "Interpreted callback host lifetime":
  test "registry retains and explicitly releases a non-scheduler interpreter":
    let before = releasedOwners
    let callback = ownershipProbe()
    check releasedOwners == before
    block:
      let host = interpretedBlockHost(callback)
      require host != nil
      releaseInterpretedBlockHost(host)
    check releasedOwners == before + 1
    expect ValueError:
      discard interpretedBlockHost(callback)

  test "non-scheduler host remains live after the local reference exits":
    let blockValue = retainedBlock()
    var host = interpretedBlockHost(blockValue.blockVal)
    require host != nil
    defer: unbindCompiledMethodsFrom(host)
    check host.schedulerContextPtr == nil
    check sendMessage(nil, blockValue, "value", @[]).intVal == 42

  test "detach invalidates old handles without retaining the interpreter":
    let blockValue = retainedBlock()
    var host = interpretedBlockHost(blockValue.blockVal)
    unbindCompiledMethodsFrom(host)
    host = nil
    expect ValueError:
      discard sendMessage(nil, blockValue, "value", @[])
    expect ValueError:
      discard interpretedBlockHost(blockValue.blockVal)

  test "fresh host generation cannot revive a detached block":
    let stale = retainedBlock()
    let oldHost = interpretedBlockHost(stale.blockVal)
    unbindCompiledMethodsFrom(oldHost)
    let current = retainedBlock()
    let newHost = interpretedBlockHost(current.blockVal)
    defer: unbindCompiledMethodsFrom(newHost)
    check sendMessage(nil, current, "value", @[]).intVal == 42
    expect ValueError:
      discard sendMessage(nil, stale, "value", @[])

  test "same-host attachment is idempotent and live host cannot be stolen":
    let blockValue = retainedBlock()
    let first = interpretedBlockHost(blockValue.blockVal)
    var second = freshHost()
    defer:
      unbindCompiledMethodsFrom(first)
      unbindCompiledMethodsFrom(second)
    bindInterpretedBlockHost(first, blockValue.blockVal)
    expect ValueError:
      bindInterpretedBlockHost(second, blockValue.blockVal)
    expect ValueError:
      discard sendMessageInterpreted(second, blockValue, "value", @[])
    check interpretedBlockHost(blockValue.blockVal) == first

  test "explicit host entry can reattach after detach":
    let blockValue = retainedBlock()
    var host = interpretedBlockHost(blockValue.blockVal)
    unbindCompiledMethodsFrom(host)
    check sendMessageInterpreted(host, blockValue, "value", @[]).intVal == 42
    check sendMessage(nil, blockValue, "value", @[]).intVal == 42
    unbindCompiledMethodsFrom(host)
    unbindCompiledMethodsFrom(host)
    expect ValueError:
      discard sendMessage(nil, blockValue, "value", @[])

  test "blocks returned by interpreted methods carry their host":
    var host = freshHost()
    defer: unbindCompiledMethodsFrom(host)
    let (_, error) = host.evalStatements("LifetimeFactory := Object derive: #(). LifetimeFactory>>callback [ ^ [42] ].")
    require error.len == 0
    let factory = NodeValue(kind: vkInstance, instVal: newInstance(host.globals[]["LifetimeFactory"].classVal))
    let blockValue = sendMessageInterpreted(host, factory, "callback", @[])
    require blockValue.kind == vkBlock
    check interpretedBlockHost(blockValue.blockVal) == host
    check sendMessage(nil, blockValue, "value", @[]).intVal == 42

  test "native argument handoff retains a non-scheduler evaluation host":
    var host = freshHost()
    let (_, error) = host.evalStatements("LifetimeSink := Object derive: #(). LifetimeSink>>retain: block [ ^ nil ].")
    require error.len == 0
    require bindCompiledMethodShim(host, "LifetimeSink", "retain:", cast[pointer](retainingShim))
    let (_, handoffError) = host.doit("LifetimeSink new retain: [42]")
    require handoffError.len == 0
    host = nil
    let owner = interpretedBlockHost(savedCallback.blockVal)
    require owner != nil
    check owner.schedulerContextPtr == nil
    check sendMessage(nil, savedCallback, "value", @[]).intVal == 42
    unbindCompiledMethodsFrom(owner)
    expect ValueError:
      discard sendMessage(nil, savedCallback, "value", @[])
    savedCallback = nilValue()

  test "isolated evaluation callback retains the evaluation not its caller":
    var caller = freshHost()
    defer: unbindCompiledMethodsFrom(caller)
    let (_, error) = caller.evalStatements("LifetimeSink := Object derive: #(). LifetimeSink>>retain: block [ ^ nil ].")
    require error.len == 0
    var callerRef = caller
    require bindCompiledMethodShim(callerRef, "LifetimeSink", "retain:", cast[pointer](retainingShim))
    let evaluation = caller.evaluateIsolated("LifetimeSink new retain: [41 + 1]")
    require evaluation.error.len == 0
    let owner = interpretedBlockHost(savedCallback.blockVal)
    require owner != nil
    check owner != caller
    unbindCompiledMethodsFrom(caller)
    check sendMessage(nil, savedCallback, "value", @[]).intVal == 42
    unbindCompiledMethodsFrom(owner)
    expect ValueError:
      discard sendMessage(nil, savedCallback, "value", @[])
    savedCallback = nilValue()

  test "reattaching one block does not revive its detached siblings":
    var host = freshHost()
    defer: unbindCompiledMethodsFrom(host)
    let (first, firstError) = host.doit("[1]")
    let (second, secondError) = host.doit("[2]")
    require firstError.len == 0 and secondError.len == 0
    bindInterpretedBlockHost(host, first.blockVal)
    bindInterpretedBlockHost(host, second.blockVal)
    unbindCompiledMethodsFrom(host)
    check sendMessageInterpreted(host, first, "value", @[]).intVal == 1
    expect ValueError:
      discard sendMessage(nil, second, "value", @[])

  test "returned nested blocks preserve captures through detach and reattachment":
    var host = freshHost()
    defer: unbindCompiledMethodsFrom(host)
    let (maker, error) = host.doit("[| count | count := 0. [:step | count := count + step]]")
    require error.len == 0
    let counter = sendMessageInterpreted(host, maker, "value", @[])
    check sendMessage(nil, counter, "value:", @[toValue(2)]).intVal == 2
    unbindCompiledMethodsFrom(host)
    expect ValueError:
      discard sendMessage(nil, counter, "value:", @[toValue(3)])
    check sendMessageInterpreted(host, counter, "value:", @[toValue(3)]).intVal == 5

  test "global and super return handoffs register returned closures":
    var host = freshHost()
    defer: unbindCompiledMethodsFrom(host)
    let (_, error) = host.evalStatements("""
      LifetimeParent := Object derive: #().
      LifetimeParent>>callback [ ^ [42] ].
      LifetimeChild := LifetimeParent derive: #().
      LifetimeChild>>retain: block [ ^ nil ].
      LifetimeGlobal := [43].
    """)
    require error.len == 0
    require bindCompiledMethodShim(host, "LifetimeChild", "retain:", cast[pointer](retainingShim))
    let receiver = NodeValue(kind: vkInstance, instVal: newInstance(host.globals[]["LifetimeChild"].classVal))
    let globalBlock = boundGlobalValue(receiver, "LifetimeGlobal").value
    let parentBlock = sendSuperMessage(receiver, "LifetimeChild", "callback", @[])
    check interpretedBlockHost(globalBlock.blockVal) == host
    check interpretedBlockHost(parentBlock.blockVal) == host
    check sendMessage(nil, globalBlock, "value", @[]).intVal == 43
    check sendMessage(nil, parentBlock, "value", @[]).intVal == 42
    unbindCompiledMethodsFrom(host)
    expect ValueError:
      discard sendMessage(nil, globalBlock, "value", @[])
    expect ValueError:
      discard sendMessage(nil, parentBlock, "value", @[])

  test "shared-image evaluation can invoke a callback owned by an earlier evaluation":
    var caller = freshHost()
    defer: unbindCompiledMethodsFrom(caller)
    let first = caller.evaluateIsolated("SharedCallback := [42]. [SharedCallback value] ensure: SharedCallback")
    require first.error.len == 0
    let callback = caller.globals[]["SharedCallback"]
    let owner = interpretedBlockHost(callback.blockVal)
    require owner != nil
    check owner != caller
    defer: unbindCompiledMethodsFrom(owner)
    let second = caller.evaluateIsolated("[SharedCallback value] ensure: SharedCallback")
    require second.error.len == 0
    check second.value.intVal == 42
    check interpretedBlockHost(callback.blockVal) == owner

  test "repeated detach generations do not revive stale callbacks":
    let stale = BlockNode()
    var host = Interpreter()
    bindInterpretedBlockHost(host, stale)
    releaseInterpretedBlockHost(host)
    for iteration in 0..<128:
      let current = BlockNode()
      bindInterpretedBlockHost(host, current)
      check interpretedBlockHost(current) == host
      expect ValueError:
        discard interpretedBlockHost(stale)
      releaseInterpretedBlockHost(host)
      expect ValueError:
        discard interpretedBlockHost(current)
    host = nil
    expect ValueError:
      discard interpretedBlockHost(stale)

  test "native blocks never acquire interpreted hosts":
    proc nativeCallback(): NodeValue {.cdecl.} = toValue(7)
    let native = createBlock0(nativeCallback, 0)
    let host = freshHost()
    defer: unbindCompiledMethodsFrom(host)
    bindInterpretedBlockHost(host, native.blockVal)
    check interpretedBlockHost(native.blockVal) == nil
    check sendMessage(nil, native, "value", @[]).intVal == 7
