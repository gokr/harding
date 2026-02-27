import std/unittest
import std/os
import std/osproc
import std/strutils
import std/strtabs
import ../src/harding/core/types
import ../src/harding/interpreter/[vm]

## Tests for Smalltalk-Style Exception Handling
## Phase 1: Core existing functionality tests

var sharedInterp: Interpreter
const uncaughtTestEnv = "HARDING_UNCAUGHT_TEST_MODE"
const uncaughtModeError = "errorSignal"
const uncaughtModePass = "passNoOuter"

if existsEnv(uncaughtTestEnv):
  var uncaughtInterp = newInterpreter()
  initGlobals(uncaughtInterp)
  loadStdlib(uncaughtInterp)
  let mode = getEnv(uncaughtTestEnv)
  case mode
  of uncaughtModePass:
    discard uncaughtInterp.evalStatements("""
      [ Error signal: "pass through" ] on: Error do: [ :ex | ex pass ]
    """)
  else:
    # Expected behavior: this exits via uncaught exception default action.
    discard uncaughtInterp.evalStatements("""
      Error signal: "no handler here"
    """)
  # If execution reaches here, uncaught behavior did not terminate as expected.
  quit(2)

proc setupTestEnvironment() =
  sharedInterp = newInterpreter()
  initGlobals(sharedInterp)
  loadStdlib(sharedInterp)

proc resetInterpreterState(interp: var Interpreter) =
  interp.exceptionHandlers.setLen(0)
  interp.evalStack.setLen(0)
  interp.workQueue.setLen(0)
  interp.activationStack.setLen(0)
  interp.currentActivation = nil
  interp.currentReceiver = nil
  exceptionContextRegistry.setLen(0)

proc runUncaughtCase(mode: string): tuple[output: string, exitCode: int] =
  var env = newStringTable(modeCaseSensitive)
  env[uncaughtTestEnv] = mode
  let command = "\"" & getAppFilename() & "\""
  execCmdEx(command, env = env)

suite "Signal Point Preservation":

  setup:
    if sharedInterp.isNil:
      setupTestEnvironment()
    resetInterpreterState(sharedInterp)

  test "signal context accessible from exception":
    ## The exception should have access to its signal context
    let result = sharedInterp.evalStatements("""
      Result := [ Error signal: "test" ] on: Error do: [ :ex | 
        ex signalContext
      ]
    """)
    
    # Should return true (signalContext exists)
    check(result[0].len > 0)
    check(result[0][^1].boolVal == true)

  test "activation stack depth recorded at signal":
    ## The exception should record the stack depth at signal point
    let result = sharedInterp.evalStatements("""
      Result := [ Error signal: "test" ] on: Error do: [ :ex | 
        ex signalActivationDepth
      ]
    """)
    
    check(result[0].len > 0)
    check(result[0][^1].intVal > 0)  # Should have at least 1 activation

  test "full activation stack accessible from handler":
    skip() # TODO: Don't truncate activation stack

suite "Handler Actions":

  setup:
    if sharedInterp.isNil:
      setupTestEnvironment()
    resetInterpreterState(sharedInterp)

  test "resume continues from signal point":
    ## Exception>>resume causes signal to return nil, execution continues after signal
    let result = sharedInterp.evalStatements("""
      Result := [
        [
          Notification signal: "test".
          42
        ] on: Notification do: [ :ex | ex resume ]
      ] value
    """)

    # After resume, signal returns nil and execution continues to 42
    check(result[0].len > 0)
    check(result[0][^1].intVal == 42)

  test "resume: provides return value":
    ## Exception>>resume: should return the provided value from signal
    let result = sharedInterp.evalStatements("""
      Result := [
        [
          | val |
          val := Notification signal: "test".
          val
        ] on: Notification do: [ :ex | ex resume: 42 ]
      ] value
    """)
    
    check(result[0].len > 0)
    check(result[0][^1].intVal == 42)

  test "retry re-executes protected block":
    ## Exception>>retry causes the protected block to re-execute from the start
    ## Use an outer block to properly scope the attempts variable
    let result = sharedInterp.evalStatements("""
      Result := [
        | attempts |
        attempts := 0.
        [
          attempts := attempts + 1.
          attempts < 3 ifTrue: [ Error signal: "not yet" ].
          attempts
        ] on: Error do: [ :ex | ex retry ]
      ] value
    """)

    check(result[1].len == 0)
    check(result[0].len > 0)
    check(result[0][^1].intVal == 3)

  test "outer evaluates in outer handler context":
    skip() # outer is not yet implemented

suite "Resumption Semantics":

  setup:
    if sharedInterp.isNil:
      setupTestEnvironment()
    resetInterpreterState(sharedInterp)

  test "Error is not resumable":
    let result = sharedInterp.evalStatements("""
      Result := Error new isResumable
    """)
    check(result[0].len > 0)
    check(result[0][^1].boolVal == false)

  test "Notification is resumable":
    let result = sharedInterp.evalStatements("""
      Result := Notification new isResumable
    """)
    check(result[0].len > 0)
    check(result[0][^1].boolVal == true)

suite "Uncaught Exception Handling":

  test "uncaught exception exits with stack trace":
    let run = runUncaughtCase(uncaughtModeError)
    check(run.exitCode != 0)
    check("=== Uncaught Exception ===" in run.output)
    check("Error: no handler here" in run.output)
    check("Stack trace:" in run.output)

  test "uncaught pass exits with stack trace":
    let run = runUncaughtCase(uncaughtModePass)
    check(run.exitCode != 0)
    check("=== Uncaught Exception ===" in run.output)
    check("Error: pass through" in run.output)
    check("Stack trace:" in run.output)

  test "process suspended for debugger":
    skip() # Requires debugger infrastructure
