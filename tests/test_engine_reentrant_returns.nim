import std/[unittest, tables, strutils]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/runtime/runtime

proc isolatedShim(interp: var Interpreter, self: Instance,
                  args: seq[NodeValue]): NodeValue {.nimcall.} =
  let message = MessageNode(receiver: LiteralNode(value: args[0]), selector: "value:",
                            arguments: @[Node(LiteralNode(value: toValue(41)))])
  try:
    result = evalCallbackNonFatal(interp, message)
  except ValueError as failure:
    interp.globals[]["IsolatedRejected"] = toValue(failure.msg.contains("BlockCannotReturn"))
    result = toValue(17)

proc applyShim(interp: var Interpreter, self: Instance,
               args: seq[NodeValue]): NodeValue {.nimcall.} =
  initRuntime()
  try:
    discard sendMessage(currentRuntime[], args[0], "value:", @[toValue(41)])
    interp.globals[]["Continued"] = toValue(true)
  finally:
    interp.globals[]["CompiledCleanup"].instVal.elements.add(toValue(2))
  toValue(99)

let context = newSchedulerContext()
var interp = context.mainProcess.getInterpreter()
loadStdlib(interp)
let (_, setupError) = interp.evalStatements("""
ReturnProbe := Object derive: #().
ReturnProbe>>apply: block [ ^ block value: 41 ].
ReturnProbe>>run [
  [self apply: [:n | [^ n + 1] ensure: [Trace add: 1]]]
    ensure: [Trace add: 3].
  ^ 99
].
ReturnProbe>>makeEscaped [ ^ [:n | ^ n + 1] ].
ReturnProbe>>localCallback [ ^ self apply: [:n | n + 1] ].
ReturnProbe>>nilReturn [ self apply: [:n | ^ nil]. ^ 99 ].
ReturnProbe>>nested [ self apply: [:n | self apply: [:m | ^ n + m]]. ^ 99 ].
ReturnProbe>>replaced [
  [self apply: [:n | [^ n] ensure: [Error signal: "replacement"]]]
    ensure: [Trace add: 3].
  ^ 99
].
ReturnProbe>>cleanupReturn [
  self apply: [:n | [^ n] ensure: [^ 7]]. ^ 99
].
ReturnProbe>>isolated: block [ ^ block value: 41 ].
ReturnProbe>>runIsolated [ self isolated: [:n | ^ n]. ^ 99 ].
ReturnProbe>>nestedIsolated [
  self apply: [:n | self isolated: [:m | ^ m]]. ^ 99
].
ReturnProbe>>nearestHome [
  [self nested] ensure: [Trace add: 3]. ^ 71
].
ReturnProbe>>pendingOperand [ ^ 5 + self nested ].
ReturnProbe>>guarded [
  [self apply: [:n | ^ n + 1]] on: Error do: [:ex | ^ 999]. ^ 99
].
ReturnProbe>>guardedCleanup [
  [[self apply: [:n | ^ n + 1]] ensure: [Error signal: "cleanup"]]
    on: Error do: [:ex | ^ 17]. ^ 99
].
ReturnProbe>>allInterpretedGuard [ [^ 42] on: Error do: [:ex | ^ 999]. ^ 99 ].
""")
doAssert setupError.len == 0, setupError

proc reset() =
  let (_, error) = interp.evalStatements("Trace := Array new. CompiledCleanup := Array new. Continued := false. IsolatedRejected := false.")
  doAssert error.len == 0, error

suite "Reentrant engine returns":
  test "all-interpreted control returns to live home":
    reset()
    let (value, error) = interp.doit("ReturnProbe new run")
    require error.len == 0
    check value.intVal == 42
    check interp.globals[]["Trace"].instVal.elements == @[toValue(1), toValue(3)]

  test "interpreted return abandons compiled caller and runs both engines' cleanup":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new run")
    require error.len == 0
    check value.intVal == 42
    check not interp.globals[]["Continued"].boolVal
    check interp.globals[]["Trace"].instVal.elements == @[toValue(1), toValue(3)]
    check interp.globals[]["CompiledCleanup"].instVal.elements == @[toValue(2)]
    check interp.activationStack.len == 0
    check interp.cleanupStack.len == 0
    check interp.exceptionHandlers.len == 0
    check interp.engineActivationScopes.len == 0

  test "ordinary callbacks continue in compiled caller":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new localCallback")
    require error.len == 0
    check value.intVal == 99
    check interp.globals[]["Continued"].boolVal

  test "nested engine calls return to the original interpreted invocation":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    for iteration in 0..<8:
      let (value, error) = interp.doit("ReturnProbe new nested")
      require error.len == 0
      check value.intVal == 82
      check not interp.globals[]["Continued"].boolVal
      check interp.engineActivationScopes.len == 0
      check interp.cleanupStack.len == 0

  test "nil return value is not replaced by the compiled result":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new nilReturn")
    require error.len == 0
    check isNilValue(value)
    check not interp.globals[]["Continued"].boolVal

  test "cleanup return replaces a pending interpreted return":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new cleanupReturn")
    require error.len == 0
    check value.intVal == 7
    check not interp.globals[]["Continued"].boolVal

  test "cleanup error crosses compiled finally before reaching the outer handler":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("[ReturnProbe new replaced] on: Error do: [:ex | ex message]")
    require error.len == 0
    check value.strVal == "replacement"
    check interp.globals[]["Trace"].instVal.elements == @[toValue(3)]
    check interp.globals[]["CompiledCleanup"].instVal.elements == @[toValue(2)]
    check not interp.globals[]["Continued"].boolVal

  test "isolated host callbacks cannot return into their suspended caller":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "isolated:", cast[pointer](isolatedShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("[ReturnProbe new runIsolated] on: BlockCannotReturn do: [:ex | 17]")
    require error.len == 0
    check value.intVal == 99
    check interp.globals[]["IsolatedRejected"].boolVal

  test "isolated callback hides homes from nested engine entries too":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "isolated:", cast[pointer](isolatedShim))
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new nestedIsolated")
    require error.len == 0
    check value.intVal == 99
    check interp.globals[]["IsolatedRejected"].boolVal
    check interp.globals[]["Continued"].boolVal
    check interp.engineActivationScopes.len == 0

  test "return stops at its actual home and leaves its caller running":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new nearestHome")
    require error.len == 0
    check value.intVal == 71
    check interp.globals[]["Trace"].instVal.elements == @[toValue(3)]
    check interp.globals[]["CompiledCleanup"].instVal.elements == @[toValue(2), toValue(2)]

  test "return preserves operands pending in the home caller":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new pendingOperand")
    require error.len == 0
    check value.intVal == 87

  test "ordinary Error handlers do not intercept a valid return transfer":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new guarded")
    require error.len == 0
    check value.intVal == 42
    check not interp.globals[]["Continued"].boolVal
    check interp.exceptionHandlers.len == 0

  test "home handlers stay installed while its pending cleanup runs":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("ReturnProbe new guardedCleanup")
    require error.len == 0
    check value.intVal == 17
    check interp.exceptionHandlers.len == 0

  test "all-interpreted non-local return also removes abandoned handlers":
    reset()
    let (value, error) = interp.doit("ReturnProbe new allInterpretedGuard")
    require error.len == 0
    check value.intVal == 42
    check interp.exceptionHandlers.len == 0

  test "interpreted error identity survives the compiled caller":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("Failure := Error new. [ReturnProbe new apply: [:n | Failure signal]] on: Error do: [:ex | ex == Failure]")
    require error.len == 0
    check value.boolVal
    check not interp.globals[]["Continued"].boolVal
    check interp.exceptionHandlers.len == 0

  test "expired home remains catchable BlockCannotReturn":
    reset()
    require bindCompiledMethodShim(interp, "ReturnProbe", "apply:", cast[pointer](applyShim))
    defer: unbindCompiledMethodsFrom(interp)
    let (value, error) = interp.doit("[ReturnProbe new apply: ReturnProbe new makeEscaped] on: BlockCannotReturn do: [:ex | 17]")
    require error.len == 0
    check value.intVal == 17
