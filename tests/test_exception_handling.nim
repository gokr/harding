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

suite "Ensure Cleanup":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  teardown:
    interp.exceptionHandlers.setLen(0)
    interp.evalStack.setLen(0)
    interp.workQueue.setLen(0)
    exceptionContextRegistry.setLen(0)
    interp.cleanupStack.setLen(0)
    interp.activationStack.setLen(0)
    interp.currentActivation = nil

  test "cleanup runs on normal completion and the body result is kept":
    let result = interp.evalStatements("""
      Log := "".
      Result := [ "body" ] ensure: [ Log := Log & "cleanup" ].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal == "body")

  test "cleanup runs exactly once on normal completion":
    let result = interp.evalStatements("""
      Count := 0.
      [ "body" ] ensure: [ Count := Count + 1 ].
      Count
    """)
    check(result[1].len == 0)
    check(result[0][^1].intVal == 1)

  test "cleanup runs when the body signals":
    let result = interp.evalStatements("""
      Count := 0.
      Result := [[ Error signal: "boom" ] ensure: [ Count := Count + 1 ]]
        on: Error do: [ :ex | ex message ].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal == "boom")

  test "a cleanup that signals is caught by the protecting handler once":
    let result = interp.evalStatements("""
      Count := 0.
      Result := [[ "body" ] ensure: [ Count := Count + 1. Error signal: "cleanup failed" ]]
        on: Error do: [ :ex | "caught: " & ex message ].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal == "caught: cleanup failed")

  test "nested cleanups run innermost first":
    let result = interp.evalStatements("""
      Order := "".
      [ [ "inner" ] ensure: [ Order := Order & "1" ] ] ensure: [ Order := Order & "2" ].
      Order
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal == "12")

  test "cleanup runs once per retry attempt":
    let result = interp.evalStatements("""
      Attempts := 0.
      Cleanups := 0.
      Result := [
        [ Attempts := Attempts + 1.
          Attempts < 3 ifTrue: [ Error signal: "again" ].
          Attempts ]
          ensure: [ Cleanups := Cleanups + 1 ]
      ] on: Error do: [ :ex | ex retry ].
      (Result asString) & ":" & (Attempts asString) & ":" & (Cleanups asString)
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal == "3:3:3")

  test "cleanup return supersedes normal completion":
    let result = interp.evalStatements("""
      Winner := Object derive: #().
      Winner>>run [ [ "body" ] ensure: [ ^ "cleanup won" ]. ^ "unreachable" ].
      Result := Winner new run.
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal == "cleanup won")

  test "cleanup return supersedes a pending error and runs outer cleanup":
    let evaluated = interp.evalStatements("""
      Order := "".
      Winner := Object derive: #().
      Winner>>run [
        [[Error signal: "body failed"] ensure: [Order := Order & "1". ^ "cleanup won"]]
          ensure: [Order := Order & "2"]
      ].
      Value := [Winner new run] on: Error do: [:ex | "incorrect"].
      Value & ":" & Order
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "cleanup won:12"

  test "return to a finished home signals BlockCannotReturn":
    let result = interp.evalStatements("""
      Maker := Object derive: #().
      Maker>>make [ ^ [^ 42] ].
      blk := Maker new make.
      Result := [blk value] on: Error do: [ :ex | ex message ].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal ==
      "Block cannot return: home activation is no longer active")

  test "a finished home does not stop ordinary closure evaluation":
    let result = interp.evalStatements("""
      Maker := Object derive: #().
      Maker>>make [ | n | n := 0. ^ [n := n + 1. n] ].
      blk := Maker new make.
      Result := (blk value asString) & ":" & (blk value asString).
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].strVal == "1:2")

  test "cleanup runs on a non-local return and the return wins":
    let result = interp.evalStatements("""
      Count := 0.
      Returns := Object derive: #().
      Returns>>run [ [ ^ 11 ] ensure: [ Count := Count + 1 ] ].
      Result := Returns new run.
      (Result asString) & ":" & (Count asString)
    """)
    check(result[1].len == 0)
    # Both the returned value and the cleanup side effect must hold.
    check(result[0][^1].strVal == "11:1")
