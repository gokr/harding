#!/usr/bin/env nim

import std/[times, strformat, logging, algorithm]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

proc median(values: seq[float]): float =
  var sortedVals = values
  sortedVals.sort()
  let mid = sortedVals.len div 2
  if sortedVals.len mod 2 == 0:
    return (sortedVals[mid - 1] + sortedVals[mid]) / 2.0
  return sortedVals[mid]

proc runCase(name: string, code: string, runs: int = 5): float =
  var samples: seq[float] = @[]
  for _ in 0..<runs:
    var interp = newInterpreter()
    initGlobals(interp)
    initSymbolTable()
    loadStdlib(interp)

    let start = cpuTime()
    let runResult = interp.evalStatements(code)
    let elapsed = (cpuTime() - start) * 1000.0

    if runResult[1].len > 0:
      raise newException(ValueError, fmt("{name} failed: {runResult[1]}"))
    samples.add(elapsed)

  let med = median(samples)
  var best = samples[0]
  var worst = samples[0]
  for value in samples:
    if value < best:
      best = value
    if value > worst:
      worst = value
  echo fmt("{name:>22}: median {med:>8.2f} ms (best {best:>8.2f}, worst {worst:>8.2f})")
  med

proc warmup() =
  var interp = newInterpreter()
  initGlobals(interp)
  initSymbolTable()
  loadStdlib(interp)
  discard interp.evalStatements("Result := 1 + 2")

when isMainModule:
  configureLogging(lvlWarn)

  echo "Harding Message Send Benchmark"
  echo "============================="
  warmup()

  let intArithmetic = """
    i := 1.
    sum := 0.
    [i <= 200000] whileTrue: [
      sum := sum + (i * 3).
      i := i + 1
    ].
    Result := sum
  """

  let stringSends = """
    i := 0.
    total := 0.
    [i < 200000] whileTrue: [
      total := total + ("abcdef" size).
      i := i + 1
    ].
    Result := total
  """

  let classSends = """
    i := 0.
    hits := 0.
    [i < 200000] whileTrue: [
      ((42 class) name = "Integer") ifTrue: [hits := hits + 1].
      i := i + 1
    ].
    Result := hits
  """

  discard runCase("integer arithmetic sends", intArithmetic)
  discard runCase("string method sends", stringSends)
  discard runCase("class lookup sends", classSends)
