#!/usr/bin/env nim

import std/[times, strformat, logging, algorithm]
import ../src/harding/core/types
import ../src/harding/core/scheduler
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
  initProcessorGlobal(result)
  loadStdlib(result)
  let setup = result.evalStatements("""
    Harding load: "lib/web/Bootstrap.hrd".
    Harding load: "lib/web/todo/Bootstrap.hrd".
    TodoApp resetRepository.
  """)
  if setup[1].len > 0:
    raise newException(ValueError, "Setup failed: " & setup[1])

proc runCase(name: string, code: string, runs: int = 2): float =
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
  echo fmt("{name:>28}: median {med:>8.2f} ms (best {best:>8.2f}, worst {worst:>8.2f})")
  med

when isMainModule:
  configureLogging(lvlWarn)
  echo "Harding Todo Render Cache Benchmark"
  echo "=================================="

  let warmItemRender = """
    Todo := TodoApp repository all at: 0.
    Item := (TodoItemComponent todo: Todo routePrefix: "" panelId: "todo-panel").
    Item renderString.
    I := 0.
    [I < 50] whileTrue: [
      Output := Item renderString.
      I := I + 1
    ].
    Result := Output size
  """

  let warmPanelRender = """
    Panel := (TodoPanelComponent repository: TodoApp repository routePrefix: "" panelId: "todo-panel").
    Panel renderString.
    I := 0.
    [I < 20] whileTrue: [
      Output := Panel renderString.
      I := I + 1
    ].
    Result := Output size
  """

  let warmPageRender = """
    Page := (TodoPageComponent repository: TodoApp repository routePrefix: "" panelId: "todo-panel").
    Page renderString.
    I := 0.
    [I < 10] whileTrue: [
      Output := Page renderString.
      I := I + 1
    ].
    Result := Output size
  """

  let invalidatingItemRender = """
    Repo := TodoApp repository.
    Todo := Repo all at: 0.
    I := 0.
    [I < 25] whileTrue: [
      Output := ((TodoItemComponent todo: Todo routePrefix: "" panelId: "todo-panel") renderString).
      Todo toggleCompleted.
      I := I + 1
    ].
    Result := Output size
  """

  let invalidatingPanelRender = """
    Repo := TodoApp repository.
    Panel := (TodoPanelComponent repository: Repo routePrefix: "" panelId: "todo-panel").
    I := 0.
    [I < 10] whileTrue: [
      Output := Panel renderString.
      Repo toggle: 1.
      I := I + 1
    ].
    Result := Output size
  """

  discard runCase("warm item render", warmItemRender)
  discard runCase("warm panel render", warmPanelRender)
  discard runCase("warm page render", warmPageRender)
  discard runCase("invalidating item render", invalidatingItemRender)
  discard runCase("invalidating panel render", invalidatingPanelRender)
