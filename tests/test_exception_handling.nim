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

  test "DivisionByZero catches integer division by zero":
    let result = interp.evalStatements("""
      Result := [ 10 // 0 ] on: DivisionByZero do: [ :ex | ex resume: 42 ]
    """)
    check(result[0][^1].intVal == 42)

  test "DivisionByZero catches float division by zero":
    let result = interp.evalStatements("""
      Result := [ 10.0 / 0.0 ] on: DivisionByZero do: [ :ex | ex resume: 99 ]
    """)
    check(result[0][^1].intVal == 99)
