##
## test_echo.nim - Tests for the harding-echo package
##

import std/unittest
import harding/core/types
import harding/interpreter/vm
import harding_echo/package

suite "Echo Package Tests":
  var interp: Interpreter
  
  setup:
    interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)
    check installEchoPackage(interp)
  
  test "Echo returns the message":
    let (vals, err) = interp.evalStatements("""
      result := Echo echo: "test message"
    """)
    checkpoint err
    require err.len == 0
    check vals[^1].kind == vkString
    check vals[^1].strVal == "test message"
  
  test "Echo with prefix":
    let (vals, err) = interp.evalStatements("""
      result := Echo echo: "World" withPrefix: "Hello, "
    """)
    checkpoint err
    require err.len == 0
    check vals[^1].kind == vkString
    check vals[^1].strVal == "Hello, World"
  
  test "Echo count increments":
    let (vals, err) = interp.evalStatements("""
      Echo reset
      Echo echo: "first"
      Echo echo: "second"
      count := Echo count
    """)
    checkpoint err
    require err.len == 0
    check vals[^1].kind == vkInt
    check vals[^1].intVal == 2
  
  test "Echo reset works":
    let (vals, err) = interp.evalStatements("""
      Echo echo: "before"
      Echo reset
      count := Echo count
    """)
    checkpoint err
    require err.len == 0
    check vals[^1].kind == vkInt
    check vals[^1].intVal == 0

when isMainModule:
  echo "Running Echo package tests..."
