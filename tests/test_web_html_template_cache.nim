#!/usr/bin/env nim
#
# Tests for block-aware Html template caching
# Covers static string DSL compatibility, dynamic block content,
# dynamic attrs, and component context rendering.
#

import std/[strutils, unittest]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

proc newWebInterp(loadTodo: bool = false): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initSymbolTable()
  loadStdlib(result)

  var setup = "Harding load: \"lib/web/Bootstrap.hrd\"."
  if loadTodo:
    setup = setup & " Harding load: \"lib/web/todo/Bootstrap.hrd\"."

  let setupResult = result.evalStatements(setup)
  if setupResult[1].len > 0:
    raise newException(ValueError, setupResult[1])

proc expectString(value: NodeValue): string =
  check(value.kind == vkString)
  value.strVal

proc expectArray(value: NodeValue): seq[NodeValue] =
  check(value.kind == vkInstance)
  check(value.instVal.kind == ikArray)
  value.instVal.elements

suite "Web Html template cache":
  test "plain Html DSL still returns static strings":
    var interp = newWebInterp()
    let (result, err) = interp.doit("Html div: #{#class -> \"badge\"} with: \"Hello\"")
    check(err.len == 0)
    check(expectString(result) == "<div class=\"badge\">Hello</div>")

  test "block content becomes a reusable dynamic template":
    var interp = newWebInterp()
    let script = """
      Counter := 0.
      Template := Html div: #{#class -> "badge"} with: [ Counter := Counter + 1. Counter printString ].
      Outputs := Array new.
      Outputs add: (Template renderString).
      Outputs add: (Template renderString).
      Outputs
    """
    let results = interp.evalStatements(script)
    check(results[1].len == 0)
    let outputs = expectArray(results[0][^1])
    check(expectString(outputs[0]) == "<div class=\"badge\">1</div>")
    check(expectString(outputs[1]) == "<div class=\"badge\">2</div>")

  test "dynamic attrs are escaped and nil attrs are omitted":
    var interp = newWebInterp()
    let script = """
      Counter := 0.
      Template := Html div: #{
        #"data-count" -> [ Counter := Counter + 1. Counter printString ]
        #"data-note" -> [ "A&B<C>" ]
        #"data-skip" -> [ nil ]
      } with: "".
      Outputs := Array new.
      Outputs add: (Template renderString).
      Outputs add: (Template renderString).
      Outputs
    """
    let results = interp.evalStatements(script)
    check(results[1].len == 0)
    let outputs = expectArray(results[0][^1])
    let first = expectString(outputs[0])
    let second = expectString(outputs[1])
    check(first.contains("data-count=\"1\""))
    check(second.contains("data-count=\"2\""))
    check(first.contains("data-note=\"A&amp;B&lt;C&gt;\""))
    check(not first.contains("data-skip="))

  test "cached component templates can use render context":
    var interp = newWebInterp()
    let script = """
      OuterTemplate := nil.
      OuterComponent := Component derivePublic: #().

      OuterComponent class>>template [
        | parts |
        OuterTemplate isNil ifTrue: [
          parts := Array new.
          parts add: "before ".
          parts add: (Html fragmentWith: [:component | component className]).
          parts add: " after".
          OuterTemplate := Html div: #{#class -> "outer"} with: parts
        ].
        ^ OuterTemplate
      ].

      OuterComponent>>render [ ^ self class template ].

      Parent := OuterComponent basicNew.
      Parent renderString
    """
    let results = interp.evalStatements(script)
    check(results[1].len == 0)
    check(expectString(results[0][^1]) == "<div class=\"outer\">before OuterComponent after</div>")

  test "todo components render without leaking block placeholders":
    var interp = newWebInterp(loadTodo = true)
    let script = """
      Repo := TodoRepository new.
      Repo addTitle: "<done>".
      (TodoPageComponent repository: Repo) renderString
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    let html = expectString(result)
    check(html.contains("id=\"todo-panel\""))
    check(html.contains("&lt;done&gt;"))
    check(not html.contains("<block>"))
