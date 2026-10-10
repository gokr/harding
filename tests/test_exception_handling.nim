import std/[unittest]
import ../src/harding/core/types
import ../src/harding/interpreter/[vm]

var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
loadStdlib(sharedInterp)

suite "Exception Handling":
  var interp {.used.}: Interpreter
  setup:
    interp = sharedInterp

  teardown:
    # Clear exception handlers and eval stack to prevent state leakage
    interp.exceptionHandlers.setLen(0)
    interp.evalStack.setLen(0)
    # Clear work queue of any pending frames
    interp.workQueue.setLen(0)
    # Clear exception context registry to prevent interference
    exceptionContextRegistry.setLen(0)
    # Clear activation stack to prevent captured variable leakage between tests
    interp.activationStack.setLen(0)
    interp.currentActivation = nil

  test "basic on:do: catches exception":
    let result = interp.evalStatements("""
      Result := [ Error signal: "test" ] on: Error do: [ :ex | "caught" ]
    """)
    check(result[0][^1].strVal == "caught")

  test "nested on:do: with inner handling":
    let result = interp.evalStatements("""
      Result := [
        [ Error signal: "inner" ] on: Error do: [ :ex | "inner caught" ]
      ] on: Error do: [ :ex | "outer caught" ]
    """)
    check(result[0][^1].strVal == "inner caught")

  test "handler receives exception message":
    let result = interp.evalStatements("""
      Result := [ Error signal: "my message" ] on: Error do: [ :ex | ex message ]
    """)
    check(result[0][^1].strVal == "my message")

  test "normal completion returns block result":
    let result = interp.evalStatements("""
      Result := [ "normal result" ] on: Error do: [ :ex | "caught" ]
    """)
    check(result[0][^1].strVal == "normal result")

  test "subclass caught by parent handler":
    let result = interp.evalStatements("""
      Result := [ Error signal: "subclass" ] on: Exception do: [ :ex | "caught by parent" ]
    """)
    check(result[0][^1].strVal == "caught by parent")

  test "ifError catches errors":
    let result = interp.evalStatements("""
      Result := [ Error signal: "oops" ] ifError: [ :ex | "handled" ]
    """)
    check(result[0][^1].strVal == "handled")

  test "handler fall-through acts as return value":
    let result = interp.evalStatements("""
      Result := [ Error signal: "test" ] on: Error do: [ :ex | "handled" ]
    """)
    check(result[0][^1].strVal == "handled")

  test "return: provides value to on:do:":
    let result = interp.evalStatements("""
      Result := [ Error signal: "test" ] on: Error do: [ :ex | ex return: 42 ]
    """)
    check(result[0][^1].intVal == 42)

  test "pass delegates to outer handler":
    let result = interp.evalStatements("""
      Result := [
        [ Error signal: "test" ] on: Error do: [ :ex | ex pass ]
      ] on: Error do: [ :ex | "outer caught" ]
    """)
    check(result[0][^1].strVal == "outer caught")

  test "normal after exception handling":
    let result = interp.evalStatements("""
      Result := [ "normal" ] on: Error do: [ :ex | "caught" ]
    """)
    check(result[0][^1].strVal == "normal")

  test "error abandons remaining protected statements":
    let evaluated = interp.evalStatements("""
      Result := [Error signal: "stop". "incorrect"] on: Error do: [:ex | "caught"]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "caught"

  test "handler failures bypass the executing handler":
    let evaluated = interp.evalStatements("""
      Result := [[Error signal: "first"] on: Error do: [:ex | Error signal: "second"]]
        on: Error do: [:outer | outer message]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "second"

  test "error resumption reports an error to the outer handler":
    let evaluated = interp.evalStatements("""
      Result := [[Error signal: "first"] on: Error do: [:ex | ex resume: 42]]
        on: Error do: [:outer | outer message]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "Cannot resume a non-resumable exception"

  test "DivisionByZero catches integer division by zero":
    let result = interp.evalStatements("""
      Result := [ 10 // 0 ] on: DivisionByZero do: [ :ex | 42 ]
    """)
    check(result[0][^1].intVal == 42)

  test "DivisionByZero catches float division by zero":
    let result = interp.evalStatements("""
      Result := [ 10.0 / 0.0 ] on: DivisionByZero do: [ :ex | 99 ]
    """)
    check(result[0][^1].intVal == 99)

  test "DivisionByZero catches integer modulo by zero":
    let result = interp.evalStatements("""
      Result := [ 10 % 0 ] on: DivisionByZero do: [ :ex | 7 ]
    """)
    check(result[0][^1].intVal == 7)

  test "notification handler result is the signal's result":
    let evaluated = interp.evalStatements("""
      Result := [Notification signal: "notice"] on: Notification do: [:ex | "handled"]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "handled"

  test "notification does not unwind the signaling computation":
    let evaluated = interp.evalStatements("""
      Result := [Notification signal: "notice". "continued"]
        on: Notification do: [:ex | ex resume: 7]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "continued"

  test "notification resume supplies the signal value":
    let evaluated = interp.evalStatements("""
      Result := [Notification signal: "notice"] on: Notification do: [:ex | ex resume: 42]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].intVal == 42

  test "notification pass reaches an outer handler":
    let evaluated = interp.evalStatements("""
      Result := [
        [Notification signal: "notice"] on: Notification do: [:ex | ex pass]
      ] on: Notification do: [:outer | "outer handled"]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "outer handled"

  test "notification handler failures propagate as errors":
    let evaluated = interp.evalStatements("""
      Result := [[Notification signal: "notice"] on: Notification do: [:ex | Error signal: "failed"]]
        on: Error do: [:outer | outer message]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "failed"

  test "notification rejects retry and return:":
    let retried = interp.evalStatements("""
      Result := [[Notification signal: "notice"] on: Notification do: [:ex | ex retry]]
        on: Error do: [:outer | outer message]
    """)
    check retried[1].len == 0
    check retried[0][^1].strVal == "Notification does not support retry"
    let returned = interp.evalStatements("""
      Result := [[Notification signal: "notice"] on: Notification do: [:ex | ex return: 1]]
        on: Error do: [:outer | outer message]
    """)
    check returned[1].len == 0
    check returned[0][^1].strVal == "Notification does not support return:"

  test "pass skips non-matching outer handler":
    let result = interp.evalStatements("""
      Result := [
        [
          [ Error signal: "pass route" ] on: Error do: [ :ex | ex pass ]
        ] on: Notification do: [ :ex | "notification outer" ]
      ] on: Error do: [ :ex | "error outer" ]
    """)
    check(result[0][^1].strVal == "error outer")
