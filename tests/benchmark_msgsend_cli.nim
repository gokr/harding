#!/usr/bin/env nim

import std/[os, osproc, times, algorithm, strformat, strutils]

proc median(values: seq[float]): float =
  var sortedVals = values
  sortedVals.sort()
  let mid = sortedVals.len div 2
  if sortedVals.len mod 2 == 0:
    return (sortedVals[mid - 1] + sortedVals[mid]) / 2.0
  return sortedVals[mid]

proc runExpression(binPath: string, expression: string): float =
  let start = epochTime()
  let cmdResult = execCmdEx(binPath & " -e \"" & expression.replace("\"", "\\\"") & "\"")
  let elapsed = (epochTime() - start) * 1000.0
  if cmdResult.exitCode != 0:
    raise newException(ValueError, "benchmark command failed: " & cmdResult.output)
  elapsed

proc runCase(binPath: string, name: string, expression: string, runs: int = 7) =
  var samples: seq[float] = @[]
  for _ in 0..<runs:
    samples.add(runExpression(binPath, expression))

  var best = samples[0]
  var worst = samples[0]
  for value in samples:
    if value < best:
      best = value
    if value > worst:
      worst = value

  let med = median(samples)
  echo fmt("{name:>22}: median {med:>8.2f} ms (best {best:>8.2f}, worst {worst:>8.2f})")

when isMainModule:
  let binaryPath = if paramCount() > 0: paramStr(1) else: "./harding_release"
  if not fileExists(binaryPath):
    raise newException(ValueError, "binary not found: " & binaryPath)

  echo "Harding CLI Message Send Benchmark"
  echo "================================="

  runCase(binaryPath, "integer arithmetic sends",
    "I := 1. Sum := 0. [I <= 200000] whileTrue: [Sum := Sum + (I * 3). I := I + 1]. Sum")

  runCase(binaryPath, "string method sends",
    "I := 0. Total := 0. [I < 200000] whileTrue: [Total := Total + (\"abcdef\" size). I := I + 1]. Total")

  runCase(binaryPath, "class lookup sends",
    "I := 0. Hits := 0. [I < 200000] whileTrue: [((42 class) name = \"Integer\") ifTrue: [Hits := Hits + 1]. I := I + 1]. Hits")
