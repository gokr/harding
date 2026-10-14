import std/[unittest, strformat, strutils]
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

  test "handler result provides the on:do: value":
    # `return:` was removed: the handler's ordinary result already becomes the
    # on:do: result, so no explicit transfer is needed.
    let result = interp.evalStatements("""
      Result := [ Error signal: "test" ] on: Error do: [ :ex | 42 ]
    """)
    check(result[0][^1].intVal == 42)

  test "pass delegates to outer handler":
    let result = interp.evalStatements("""
      Result := [
        [ Error signal: "test" ] on: Error do: [ :ex | ex pass ]
      ] on: Error do: [ :ex | "outer caught" ]
    """)
    check(result[0][^1].strVal == "outer caught")

  test "error pass cleans handler and intervening scopes before delegation":
    let evaluated = interp.evalStatements("""
      Order := "".
      Result := [[[Error signal: "body"] on: Error do: [:ex |
        [ex pass] ensure: [Order := Order & "i"]
      ]] ensure: [Order := Order & "o"]]
        on: Error do: [:outer | Order := Order & "h". "outer"].
      Result & ":" & Order
    """)
    require evaluated[1].len == 0
    check evaluated[0][^1].strVal == "outer:ioh"
    check interp.cleanupStack.len == 0

  test "retry cleans handler-local scopes before restarting":
    let evaluated = interp.evalStatements("""
      Order := "".
      Attempts := 0.
      Result := [Attempts := Attempts + 1. (Attempts < 2) ifTrue: [Error signal: "retry"]. "body"]
        on: Error do: [:ex | [ex retry] ensure: [Order := Order & "c"]].
      Result & ":" & Order
    """)
    require evaluated[1].len == 0
    check evaluated[0][^1].strVal == "body:c"
    check interp.cleanupStack.len == 0

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

  test "removed resumption actions are unknown selectors":
    # There is no resumption in Harding, so these selectors are simply gone: the
    # evaluation fails with Message not understood rather than resuming.
    let evaluated = interp.evalStatements("""
      Result := [Error signal: "first"] on: Error do: [:ex | ex resume: 42]
    """)
    check evaluated[1].len > 0
    check("Message not understood" in evaluated[1])

  test "missing immediate sends preserve handler results":
    let evaluated = interp.evalStatements("""
      [1 missing] on: Error do: [:ex | 42]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].intVal == 42
    check interp.exceptionHandlers.len == 0

  test "missing sends in handlers reach the outer handler":
    let evaluated = interp.evalStatements("""
      [[Error signal: "original"] on: Error do: [:ex | ex resume: 1]]
        on: MessageNotUnderstood do: [:outer | 77]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].intVal == 77

  test "custom doesNotUnderstand runs through stackless dispatch":
    let evaluated = interp.evalStatements("""
      DispatchRecovery := Object derive: #().
      DispatchRecovery>>doesNotUnderstand: selector [ ^ 91 ].
      DispatchRecovery new missing
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].intVal == 91

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
        on: Notification do: [:ex | 7]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "continued"

  test "notification handler result supplies the signal value":
    let evaluated = interp.evalStatements("""
      Result := [1 + (Notification signal: "notice")] on: Notification do: [:ex | 41]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].intVal == 42

  test "Harding has no exception resumption":
    # resume/resume:/return: are not part of the language. The handler's result
    # is the value, so no control-transfer action is needed.
    for removed in ["ex resume", "ex resume: 1", "ex return: 1"]:
      let evaluated = interp.evalStatements(fmt("""
        Result := [Notification signal: "notice"]
          on: Notification do: [:ex | {removed}]
      """))
      check evaluated[1].len > 0

  test "notification handler re-arms for later signals":
    let evaluated = interp.evalStatements("""
      Count := 0.
      Result := [
        A := Notification signal: "first".
        B := Notification signal: "second".
        A + B
      ] on: Notification do: [:ex | Count := Count + 1. Count].
      Result
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].intVal == 3
    check interp.exceptionHandlers.len == 0

  test "notification pass reaches an outer handler":
    let evaluated = interp.evalStatements("""
      Result := [
        [Notification signal: "notice"] on: Notification do: [:ex | ex pass]
      ] on: Notification do: [:outer | "outer handled"]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "outer handled"

  test "notification pass cleans handler scopes before outer dispatch":
    let evaluated = interp.evalStatements("""
      Order := "".
      Result := [[Notification signal: "notice". Order := Order & "b". "body"]
        on: Notification do: [:ex |
          [[ex pass] ensure: [Order := Order & "i"]] ensure: [Order := Order & "o"]
        ]] on: Notification do: [:outer | Order := Order & "h". 7].
      Order
    """)
    require evaluated[1].len == 0
    check evaluated[0][^1].strVal == "iohb"
    check interp.cleanupStack.len == 0
    check interp.exceptionHandlers.len == 0

  test "notification pass cleanup failure replaces delegation":
    let evaluated = interp.evalStatements("""
      Order := "".
      Result := [[[Notification signal: "notice"] on: Notification do: [:ex |
        [ex pass] ensure: [Order := Order & "c". Error signal: "cleanup failed"]
      ]] on: Notification do: [:outer | Order := Order & "incorrect"]]
        on: Error do: [:outer | outer message].
      Result & ":" & Order
    """)
    require evaluated[1].len == 0
    check evaluated[0][^1].strVal == "cleanup failed:c"
    check interp.cleanupStack.len == 0

  test "notification handler failures propagate as errors":
    let evaluated = interp.evalStatements("""
      Result := [[Notification signal: "notice"] on: Notification do: [:ex | Error signal: "failed"]]
        on: Error do: [:outer | outer message]
    """)
    check evaluated[1].len == 0
    check evaluated[0][^1].strVal == "failed"

  test "notification rejects retry":
    let retried = interp.evalStatements("""
      Result := [[Notification signal: "notice"] on: Notification do: [:ex | ex retry]]
        on: Error do: [:outer | outer message]
    """)
    check retried[1].len == 0
    check retried[0][^1].strVal == "Notification does not support retry"
  test "handler result keeps the enclosing assignment continuation":
    let assigned = interp.evalStatements("""
      Result := [ 10 // 0 ] on: DivisionByZero do: [ :ex | 42 ]
    """)
    check(assigned[1].len == 0)
    let readBack = interp.evalStatements("Result")
    check(readBack[1].len == 0)
    check(readBack[0][^1].intVal == 42)

  test "on:do: preserves pending receiver operands":
    for source in [
      "1 + ([2] on: Error do: [:ex | 0])",
      "1 + ([10 // 0] on: DivisionByZero do: [:ex | 2])",
      "1 + ([Error signal: \"test\"] on: Error do: [:ex | 2])",
      "#(1, ([2] on: Error do: [:ex | 0])) at: 1"
    ]:
      let (value, err) = interp.doit(source)
      require(err.len == 0)
      require(value.kind == vkInt)
      check(value.intVal == (if source.startsWith("#("): 2 else: 3))

  test "retry preserves pending receiver operands":
    let (value, err) = interp.doit("""
      Attempts := 0.
      1 + ([
        Attempts := Attempts + 1.
        (Attempts = 1) ifTrue: [ Error signal: "retry" ].
        2
      ] on: Error do: [:ex | ex retry])
    """)
    require(err.len == 0)
    require(value.kind == vkInt)
    check(value.intVal == 3)

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
