import std/[unittest, tables, strutils]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/runtime/runtime
import ../src/harding/runtime/compiled_support
import ../src/harding/interpreter/frame_pool

let context = newSchedulerContext()
var interp = context.mainProcess.getInterpreter()
interp.hardingHome = "."
loadStdlib(interp)

var returnTarget = CompiledReturnTarget(active: true)

proc returningBlock(): NodeValue {.cdecl.} =
  raiseNonLocalReturn(returnTarget, toValue(42))

proc failingBlock(): NodeValue {.cdecl.} =
  raiseCompiledError(compiledErrorValue("Error", "original failure"))

interp.globals[]["NativeReturn"] = createBlock0(returningBlock, 0)
interp.globals[]["NativeFailure"] = createBlock0(failingBlock, 0)

proc callback(source: string): NodeValue =
  let (value, error) = interp.doit(source)
  doAssert error.len == 0, error
  value

suite "Engine transfer cleanup and identity":
  test "return without cleanup preserves its target and value":
    var reachedHome = false
    try:
      discard sendMessageInterpreted(interp, interp.globals[]["NativeReturn"], "value", @[])
    except NonLocalReturnException as transfer:
      reachedHome = true
      check transfer.target == returnTarget
      check transfer.value.intVal == 42
    check reachedHome

  test "return preserves its original target and value after nested cleanup":
    discard interp.evalStatements("Trace := Array new")
    let body = callback("[[[NativeReturn value] ensure: [Trace add: 1]] ensure: [Trace add: 2]]")
    var reachedHome = false
    try:
      discard sendMessageInterpreted(interp, body, "value", @[])
    except NonLocalReturnException as transfer:
      reachedHome = true
      check transfer.target == returnTarget
      check transfer.value.intVal == 42
    check reachedHome
    let (trace, error) = interp.doit("Trace")
    require error.len == 0
    check trace.instVal.elements == @[toValue(1), toValue(2)]
    check interp.workQueue.len == 0
    check interp.activationStack.len == 0

  test "uncaught error retains its diagnostic after nested cleanup":
    discard interp.evalStatements("Trace := Array new")
    let body = callback("[[[NativeFailure value] ensure: [Trace add: 1]] ensure: [Trace add: 2]]")
    var reported = false
    try:
      discard sendMessageInterpreted(interp, body, "value", @[])
    except CatchableError as failure:
      reported = true
      check failure.msg.contains("original failure")
    check reported
    let (trace, error) = interp.doit("Trace")
    require error.len == 0
    check trace.instVal.elements == @[toValue(1), toValue(2)]
    check interp.workQueue.len == 0
    check interp.activationStack.len == 0

  test "cleanup errors replace a return while remaining cleanup runs":
    discard interp.evalStatements("Trace := Array new")
    let body = callback("[[[NativeReturn value] ensure: [NativeFailure value]] ensure: [Trace add: 2]]")
    var reported = false
    try:
      discard sendMessageInterpreted(interp, body, "value", @[])
    except NonLocalReturnException:
      check false
    except CatchableError as failure:
      reported = true
      check failure.msg.contains("original failure")
    check reported
    let (trace, error) = interp.doit("Trace")
    require error.len == 0
    check trace.instVal.elements == @[toValue(2)]

  test "cleanup returns replace an error and run remaining cleanup":
    discard interp.evalStatements("Trace := Array new")
    let body = callback("[[[NativeFailure value] ensure: [NativeReturn value]] ensure: [Trace add: 2]]")
    var reachedHome = false
    try:
      discard sendMessageInterpreted(interp, body, "value", @[])
    except NonLocalReturnException as transfer:
      reachedHome = true
      check transfer.target == returnTarget
      check transfer.value.intVal == 42
    check reachedHome
    let (trace, error) = interp.doit("Trace")
    require error.len == 0
    check trace.instVal.elements == @[toValue(2)]

  test "inactive compiled return home signals catchable BlockCannotReturn":
    returnTarget.active = false
    defer: returnTarget.active = true
    let body = callback("[[NativeReturn value] on: BlockCannotReturn do: [:error | 17]]")
    check sendMessageInterpreted(interp, body, "value", @[]).intVal == 17

  test "repeated transfers preserve targets without accumulating cleanup":
    let body = callback("[[NativeReturn value] ensure: [Trace add: 1]]")
    for iteration in 0..<32:
      discard interp.evalStatements("Trace := Array new")
      var reachedHome = false
      try:
        discard sendMessageInterpreted(interp, body, "value", @[])
      except NonLocalReturnException as transfer:
        reachedHome = true
        check transfer.target == returnTarget
        check transfer.value.intVal == 42
      check reachedHome
      check interp.globals[]["Trace"].instVal.elements == @[toValue(1)]
      check interp.cleanupStack.len == 0
      check interp.workQueue.len == 0
      check interp.activationStack.len == 0

  test "pooled frames release transfer payloads":
    let frame = acquireFrame()
    frame.transferFailure = newException(ValueError, "retained")
    releaseFrame(frame)
    check frame.transferFailure == nil
