#!/usr/bin/env nim

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

proc newWebInterp(loadTodo: bool = false): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initSymbolTable()
  initProcessorGlobal(result)
  loadStdlib(result)

  var setup = "Harding load: \"lib/web/Bootstrap.hrd\"."
  if loadTodo:
    setup = setup & " Harding load: \"lib/web/todo/Bootstrap.hrd\"."

  let setupResult = result.evalStatements(setup)
  if setupResult[1].len > 0:
    raise newException(ValueError, setupResult[1])

suite "Html render helpers":
  test "render builds html directly":
    var interp = newWebInterp()
    let script = """
      Html render: [:h |
        h div: [
          h h1: "Title".
          h p: "Body"
        ]
      ]
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal == "<div><h1>Title</h1><p>Body</p></div>")

  test "render with context builds html directly":
    var interp = newWebInterp()
    let script = """
      Html render: [:h |
        h attr: #class value: "Alice".
        h div: "Hello"
      ] context: nil
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal == "<div class=\"Alice\">Hello</div>")

suite "Todo render cache":
  test "todo page renders without dyn placeholders":
    var interp = newWebInterp(loadTodo = true)
    let script = """
      Repo := TodoRepository new.
      Repo addTitle: "<done>".
      (TodoPageComponent repository: Repo routePrefix: "" panelId: "todo-panel") renderString
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    let html = result.strVal
    check(html.contains("todo-panel"))
    check(html.contains("&lt;done&gt;"))
    check(not html.contains("HtmlDynamicBlock"))

  test "todo item cache reuses output and invalidates on tracked state change":
    var interp = newWebInterp(loadTodo = true)
    let script = """
      Repo := TodoApp resetRepository.
      Item1 := TodoItemComponent todo: (Repo all at: 0) routePrefix: "" panelId: "todo-panel".
      First := Item1 renderString.
      Item2 := TodoItemComponent todo: (Repo all at: 0) routePrefix: "" panelId: "todo-panel".
      Second := Item2 renderString.
      Repo toggle: 1.
      Item3 := TodoItemComponent todo: (Repo all at: 0) routePrefix: "" panelId: "todo-panel".
      Third := Item3 renderString.
      (First = Second) printString , "|" , (First = Third) printString , "|" , Third
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal.startsWith("true|false|"))
    check(result.strVal.contains("Mark active"))
