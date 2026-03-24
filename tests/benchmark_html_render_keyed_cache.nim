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
  sortedVals[mid]

proc newWebInterp(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initSymbolTable()
  loadStdlib(result)
  let setup = result.evalStatements("""
    Harding load: "lib/web/Bootstrap.hrd".
  """)
  if setup[1].len > 0:
    raise newException(ValueError, "Setup failed: " & setup[1])

proc runCase(name: string, code: string, runs: int = 3): float =
  var samples: seq[float] = @[]
  for _ in 0..<runs:
    var interp = newWebInterp()
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
  echo fmt("{name:>24}: median {med:>8.2f} ms (best {best:>8.2f}, worst {worst:>8.2f})")
  med

when isMainModule:
  configureLogging(lvlWarn)
  echo "Html keyed cache benchmark"
  echo "=========================="

  let uncachedRender = """
    Counter := 0.
    I := 0.
    [I < 100] whileTrue: [
      Output := Html canvas: [:h |
        h div: [
          h h1: "Benchmark page".
          h p: "Static section alpha".
          h p: "Static section beta".
          h p: "Static section gamma".
          h ul: [
            h li: "One".
            h li: "Two".
            h li: "Three"
          ].
          h p: [ Counter := Counter + 1. "Counter: " , Counter printString ] dyn.
          h p: "Trailing footer"
        ]
      ].
      I := I + 1
    ].
    Result := Output size
  """

  let cachedRender = """
    Counter := 0.
    Template := Html canvas: #benchHtmlDyn with: [:h |
      h div: [
        h h1: "Benchmark page".
        h p: "Static section alpha".
        h p: "Static section beta".
        h p: "Static section gamma".
        h ul: [
          h li: "One".
          h li: "Two".
          h li: "Three"
        ].
        h p: [ Counter := Counter + 1. "Counter: " , Counter printString ] dyn.
        h p: "Trailing footer"
      ]
    ].
    I := 0.
    [I < 100] whileTrue: [
      Output := Template render.
      I := I + 1
    ].
    Result := Output size
  """

  let cacheInspection = """
    Counter := 0.
    Template := Html canvas: #benchHtmlDynInspect with: [:h |
      h div: [
        h h1: "Benchmark page".
        h p: "Static section alpha".
        h p: "Static section beta".
        h p: "Static section gamma".
        h ul: [
          h li: "One".
          h li: "Two".
          h li: "Three"
        ].
        h p: [ Counter := Counter + 1. "Counter: " , Counter printString ] dyn.
        h p: "Trailing footer"
      ]
    ].
    Cache := TemplateCache at: #benchHtmlDynInspect ifAbsent: [ nil ].
    Cache isNil ifTrue: [ ^ "cache-miss" ].
    Count := Cache segments isNil ifTrue: [ -1 ] ifFalse: [ Cache segments size ].
    ^ Count printString
  """

  discard runCase("uncached canvas", uncachedRender)
  discard runCase("keyed dyn template", cachedRender)

  var interp = newWebInterp()
  let inspected = interp.evalStatements(cacheInspection)
  if inspected[1].len > 0:
    raise newException(ValueError, "cache inspection failed: " & inspected[1])
  echo "       captured segments: " & inspected[0][^1].strVal
