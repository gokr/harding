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
    Harding load: "lib/web/todo/Bootstrap.hrd".
    TodoApp resetRepository.
  """)
  if setup[1].len > 0:
    raise newException(ValueError, "Setup failed: " & setup[1])

proc runCase(name: string, code: string, runs: int = 7): float =
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
  echo fmt("{name:>22}: median {med:>8.2f} ms (best {best:>8.2f}, worst {worst:>8.2f})")
  med

when isMainModule:
  configureLogging(lvlWarn)
  echo "Harding Todo Render Benchmark"
  echo "============================="

  let daisyRender = """
    I := 0.
    [I < 75] whileTrue: [
      Output := ((TodoPageComponent repository: TodoApp repository) renderString).
      I := I + 1
    ].
    Result := Output size
  """

  let classicRender = """
    I := 0.
    [I < 75] whileTrue: [
      Output := ((TodoClassicPageComponent repository: TodoApp repository routePrefix: "/classic" panelId: "classic-todo-panel") renderString).
      I := I + 1
    ].
    Result := Output size
  """

  discard runCase("daisy render", daisyRender)
  discard runCase("classic render", classicRender)
