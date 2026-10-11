#!/usr/bin/env nim
#
# Tests for the current Html renderer and component-level render caching.
# Covers direct rendering, dynamic block content, dynamic attrs and escaping,
# component cache reuse/invalidation, and todo component rendering.
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

suite "Web Html rendering":
  test "plain Html DSL renders static strings":
    var interp = newWebInterp()
    let (result, err) = interp.doit("""
      Html render: [:h |
        h class: "badge".
        h div: "Hello"
      ]
    """)
    check(err.len == 0)
    check(expectString(result) == "<div class=\"badge\">Hello</div>")

  test "block content is re-evaluated on each render":
    var interp = newWebInterp()
    let script = """
      Counter := 0.
      Template := [:h |
        Counter := Counter + 1.
        h class: "badge".
        h div: [ h span: Counter printString ]
      ].
      Outputs := Array new.
      Outputs add: (Html render: Template).
      Outputs add: (Html render: Template).
      Outputs
    """
    let results = interp.evalStatements(script)
    check(results[1].len == 0)
    let outputs = expectArray(results[0][^1])
    check(expectString(outputs[0]) == "<div class=\"badge\"><span>1</span></div>")
    check(expectString(outputs[1]) == "<div class=\"badge\"><span>2</span></div>")

  test "dynamic attributes are escaped and nil attributes are omitted":
    var interp = newWebInterp()
    let script = """
      Counter := 0.
      Template := [:h |
        Counter := Counter + 1.
        h attr: #"data-count" value: Counter printString.
        h attr: #"data-note" value: "A&B<C>".
        h attr: #"data-skip" value: nil.
        h div: ""
      ].
      Outputs := Array new.
      Outputs add: (Html render: Template).
      Outputs add: (Html render: Template).
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

  test "nested components render through the shared canvas":
    var interp = newWebInterp()
    let script = """
      OuterComponent := Component derivePublic: #().
      InnerComponent := Component derivePublic: #().

      InnerComponent>>render [ ^ Html render: [:h | h span: "inner" ] ].

      OuterComponent>>render [
        ^ Html render: [:h |
          h class: "outer".
          h div: [ h renderComponent: InnerComponent new ]
        ]
      ].

      OuterComponent new renderString
    """
    let results = interp.evalStatements(script)
    check(results[1].len == 0)
    check(expectString(results[0][^1]) == "<div class=\"outer\"><span>inner</span></div>")

  test "todo components render without leaking block placeholders":
    var interp = newWebInterp(loadTodo = true)
    let script = """
      Repo := TodoRepository new.
      Repo addTitle: "<done>".
      (TodoPageComponent repository: Repo routePrefix: "" panelId: "todo-panel") renderString
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    let html = expectString(result)
    check(html.contains("id=\"todo-panel\""))
    check(html.contains("&lt;done&gt;"))
    check(not html.contains("<block>"))

suite "Web component render cache":
  test "cached component output is reused until tracked state changes":
    var interp = newWebInterp()
    let script = """
      Builds := 0.
      State := TrackedValue value: 0.
      StateComponent := Component derivePublic: #().
      StateComponent>>render [
        Builds := Builds + 1.
        ^ Html render: [:h | h div: [ h span: State value printString ] ]
      ].
      StateComponent>>renderCacheKey [ ^ "state-component" ].

      First := StateComponent new renderString.
      Second := StateComponent new renderString.
      State value: 5.
      Third := StateComponent new renderString.
      (First = Second) printString & "|" & (First = Third) printString & "|" & (Builds = 2) printString & "|" & Third
    """
    let (result, err) = interp.doit(script)
    check(err.len == 0)
    check(result.strVal.startsWith("true|false|true|"))
    check(result.strVal.contains("<span>5</span>"))
