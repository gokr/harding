import std/unittest
import ../src/harding/parser/lexer
import ../src/harding/parser/parser

suite "Comment and symbol syntax":
  test "ordinary comments require whitespace or end of input":
    for source in ["#", "# comment", "#\tcomment", "# ===== separator"]:
      let tokens = lex(source)
      check tokens.len == 1
      check tokens[0].kind == tkEOF
    let tokens = lex("#comment")
    check tokens[0].kind == tkSymbol
    check tokens[0].value == "comment"

  test "operator symbols consume the entire operator":
    for name in ["<", ">", "<=", ">=", "~=", "==", "~~", "+", "-", "*",
                 "/", "//", "\\\\", "&", "|", "@", "%", "<<", ">>"]:
      let tokens = lex("#" & name & ",")
      require tokens.len == 3
      check tokens[0].kind == tkSymbol
      check tokens[0].value == name
      check tokens[1].kind == tkComma

  test "documentation tokens preserve text and source positions":
    let tokens = lex("## First line\n## Second line\nObject")
    check tokens[0].kind == tkComment
    check tokens[0].value == "First line"
    check tokens[0].line == 1
    check tokens[2].kind == tkComment
    check tokens[2].value == "Second line"
    check tokens[4].kind == tkIdent
    check tokens[4].line == 3

  test "documentation is ignored in nested expressions and at EOF":
    for source in ["## Docs\nObject", "Object ## trailing", "[ ## body\n1 ]",
                   "( ## expression\n1)", "#(1, ## element\n2)"]:
      let (_, parsed) = parse(source)
      check not parsed.hasError

  test "documentation before script temporaries does not hide them":
    var parsed = initParser(lex("## Script docs\n| x |\nx := 1. x"))
    let script = parsed.parseScript()
    require not parsed.hasError
    require script != nil
    check script.temporaries == @["x"]

  test "shebang and literal prefixes stay distinct":
    let tokens = lex("#!/usr/bin/env harding\n#(1) #{\"a\" -> 2}")
    check tokens[0].kind == tkSeparator
    check tokens[1].kind == tkArrayStart
    let (_, parsed) = parse("#(1, 2). #{\"a\" -> 2}")
    check not parsed.hasError
