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

suite "Html2 dyn cache":
  test "keyed template captures segments and updates dyn content":
    var interp = newWebInterp()
    let script = """
      Counter := 0.
      Template := Html canvas: #dynSegments with: [:h |
        h div: [
          h h1: "Title".
          h p: [ Counter := Counter + 1. Counter printString ] dyn
        ]
      ].
      Cache := TemplateCache at: #dynSegments.
      (Cache segments size printString) , "|" , (Template render) , "|" , (Template render)
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal.startsWith("3|"))
    check(result.strVal.contains("<p>1</p>"))
    check(result.strVal.contains("<p>2</p>"))

  test "keyed template resolves dyn attributes with context":
    var interp = newWebInterp()
    let script = """
      Person := Object derivePublic: #(name).
      Person>>nameText [ ^ name ].
      Obj := Person new.
      Obj::name := "Alice".
      Template := Html canvas: #dynAttrs with: [:h |
        h attr: #class value: ([ :person | person nameText ] dyn).
        h div: "Hello"
      ] context: Obj.
      Template render
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal == "<div class=\"Alice\">Hello</div>")

  test "auto cache key uses current activation with suffix":
    var interp = newWebInterp()
    let script = """
      Probe := Object derivePublic: #(counter lastKey).
      Probe>>renderWidget [
        lastKey := Html autoCacheKey: #widget.
        ^ (Html canvasAuto: #widget with: [:h |
          h div: [
            h p: [ Counter := counter isNil ifTrue: [ 0 ] ifFalse: [ counter ].
                   Counter := Counter + 1.
                   counter := Counter.
                   Counter printString ] dyn
          ]
        ] context: self) renderString
      ].
      Obj := Probe new.
      First := Obj renderWidget.
      Second := Obj renderWidget.
      Obj::lastKey , "|" , First , "|" , Second
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal.contains("Probe>>renderWidget@"))
    check(result.strVal.contains("<p>1</p>"))
    check(result.strVal.contains("<p>2</p>"))

suite "Todo template Html2":
  test "template todo page renders without dyn placeholders":
    var interp = newWebInterp(loadTodo = true)
    let script = """
      Repo := TodoRepository new.
      Repo addTitle: "<done>".
      (TodoTemplatePageComponent repository: Repo routePrefix: "/template" panelId: "template-todo-panel") renderString
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    let html = result.strVal
    check(html.contains("template-todo-panel"))
    check(html.contains("&lt;done&gt;"))
    check(not html.contains("HtmlDynamicBlock"))
