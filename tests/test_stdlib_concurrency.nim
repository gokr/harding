#
# test_stdlib_concurrency.nim - Tests for concurrency primitives
# Includes: Monitor, Semaphore, SharedQueue
#

import std/[unittest, os]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

# Shared interpreter initialized once for all suites
var sharedInterp: Interpreter
sharedInterp = newInterpreter()
initGlobals(sharedInterp)
initProcessorGlobal(sharedInterp)
loadStdlib(sharedInterp)

suite "Stdlib: Monitor":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Monitor new creates monitor":
    let result = interp.evalStatements("""
      M := Monitor new.
      Result := M
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "Monitor critical: executes block":
    let result = interp.evalStatements("""
      M := Monitor new.
      Sum := 0.
      M critical: [Sum := Sum + 10].
      Result := Sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

suite "Stdlib: Semaphore":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "Semaphore new creates semaphore":
    let result = interp.evalStatements("""
      S := Semaphore new.
      Result := S
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "Semaphore forMutualExclusion creates binary semaphore":
    let result = interp.evalStatements("""
      S := Semaphore forMutualExclusion.
      S signal.
      S wait.
      Result := 42
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "Semaphore signal increments count":
    let result = interp.evalStatements("""
      S := Semaphore new.
      S signal.
      S signal.
      Result := S count
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

suite "Stdlib: SharedQueue":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "SharedQueue new creates queue":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Result := Q
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "SharedQueue nextPut: adds item":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Q nextPut: 42.
      Result := Q size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)

  test "SharedQueue next retrieves item":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Q nextPut: 42.
      Item := Q next.
      Result := Item
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

  test "SharedQueue isEmpty checks emptiness":
    let result = interp.evalStatements("""
      Q := SharedQueue new.
      Empty := Q isEmpty.
      Q nextPut: 1.
      NotEmpty := Q isEmpty not.
      Result := NotEmpty
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)
