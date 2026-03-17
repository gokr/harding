#!/usr/bin/env nim
#
# Tests for HtmlCanvas DSL with template caching
#

import std/[unittest, strutils]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

proc newWebInterp(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initSymbolTable()
  loadStdlib(result)
  
  # Load the web libraries
  let setupResult = result.evalStatements("""
    Harding load: "lib/web/Bootstrap.hrd"
  """)
  if setupResult[1].len > 0:
    raise newException(ValueError, setupResult[1])

suite "HtmlCanvas DSL":
  var interp {.used.}: Interpreter

  setup:
    interp = newWebInterp()

  test "static content renders correctly":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h div: [ h h1: "Title"; h p: "Content" ]
      ]
    """)
    check(err.len == 0)
    check(result.strVal == "<div><h1>Title</h1><p>Content</p></div>")

  test "dynamic block content evaluates each time":
    let script = """
      Counter := 0.
      Template := Html canvas: #dynamicTest with: [:h |
        h div: [ h span: [ Counter := Counter + 1. Counter printString ] ]
      ].
      First := Template render.
      Second := Template render.
      First , " " , Second
    """
    let (result, err) = interp.evalStatements(script)
    check(err.len == 0)
    check("1" in result[0][^1].strVal)
    check("2" in result[0][^1].strVal)

  test "symbol selector performs on context":
    let script = """
      TestObj := Object derivePublic: #(name).
      TestObj>>getName [ ^"Alice" ].
      
      Obj := TestObj new.
      Obj::name := "Bob".
      
      Html canvas: [:h |
        h div: [ h span: #getName ]
      ] withContext: Obj
    """
    let (result, err) = interp.evalStatements(script)
    check(err.len == 0)
    check(result[0][^1].strVal == "<div><span>Alice</span></div>")

  test "attribute cascades accumulate":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h class: "foo"; class: "bar"; id: "main".
        h div: "content"
      ]
    """)
    check(err.len == 0)
    check(result.strVal.contains("class=\"foo bar\""))
    check(result.strVal.contains("id=\"main\""))

  test "void tags auto-close":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h div: [ h input; h br; h hr ]
      ]
    """)
    check(err.len == 0)
    check(result.strVal == "<div><input><br><hr></div>")

  test "boolean attributes work":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h input; h disabled; h required.
        h div: ""
      ]
    """)
    check(err.len == 0)
    check(result.strVal.contains("disabled"))
    check(result.strVal.contains("required"))

  test "escaping works for special characters":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h div: "<script>alert('xss')</script>"
      ]
    """)
    check(err.len == 0)
    check(not result.strVal.contains("<script>"))
    check(result.strVal.contains("&lt;script&gt;"))

  test "raw content bypasses escaping":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h div: [ h raw: "<!-- comment -->" ]
      ]
    """)
    check(err.len == 0)
    check(result.strVal.contains("<!-- comment -->"))

  test "<< operator for raw output":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h div: [ h << "<span>raw</span>" ]
      ]
    """)
    check(err.len == 0)
    check(result.strVal.contains("<span>raw</span>"))

  test "nil attributes are omitted":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h class: nil; id: "test".
        h div: ""
      ]
    """)
    check(err.len == 0)
    check(not result.strVal.contains("class"))
    check(result.strVal.contains("id=\"test\""))

  test "complex nested structure":
    let (result, err) = interp.doit("""
      Html canvas: [:h |
        h section: [
          h header: [
            h h1: "Header"
          ].
          h main: [
            h article: [
              h h2: "Article".
              h p: "Paragraph"
            ]
          ].
          h footer: [
            h p: "Footer"
          ]
        ]
      ]
    """)
    check(err.len == 0)
    check(result.strVal.contains("<section>"))
    check(result.strVal.contains("<header>"))
    check(result.strVal.contains("<main>"))
    check(result.strVal.contains("<article>"))
    check(result.strVal.contains("<footer>"))
    check(result.strVal.contains("</section>"))

suite "HtmlCanvas Caching":
  var interp {.used.}: Interpreter

  setup:
    interp = newWebInterp()

  test "cached template reuses structure":
    let script = """
      RenderCount := 0.
      
      MyTemplate := Html canvas: #testCache with: [:h |
        RenderCount := RenderCount + 1.
        h div: [ h span: "cached" ]
      ].
      
      First := MyTemplate.
      Second := MyTemplate.
      Third := MyTemplate.
      
      RenderCount
    """
    let result = interp.evalStatements(script)
    check(result[1].len == 0)
    # Template built once, so RenderCount should be 1
    check(result[0][^1].intVal == 1)

  test "non-cached canvas builds each time":
    let script = """
      RenderCount := 0.
      
      MyTemplate := Html canvas: [:h |
        RenderCount := RenderCount + 1.
        h div: [ h span: "not cached" ]
      ].
      
      First := MyTemplate.
      Second := MyTemplate.
      
      RenderCount
    """
    let result = interp.evalStatements(script)
    check(result[1].len == 0)
    # No caching, so RenderCount should be 2
    check(result[0][^1].intVal == 2)
