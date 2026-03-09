#!/usr/bin/env nim

import std/unittest

import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

suite "VM regressions":
  var interp: Interpreter

  setup:
    interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    initProcessorGlobal(interp)
    loadStdlib(interp)

  test "return after at:ifAbsent: stays in caller method":
    let result = interp.evalStatements("""
      Probe := Object derive: #(paths).
      Probe>>initialize [
        paths := Table new.
        ^ self
      ].
      Probe>>probe [
        paths at: "missing" ifAbsent: [ false ].
        ^ self className
      ].

      Result := Probe new initialize probe
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Probe")

  test "zero arg block can assign outer temp before first assignment":
    let result = interp.evalStatements("""
      Probe := Object derive.
      Probe>>probe [ | value thunk |
        thunk := [ value := 123 ].
        thunk value.
        ^ value
      ].

      Result := Probe new probe
    """)

    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 123)
