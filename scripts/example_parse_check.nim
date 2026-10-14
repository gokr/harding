## Syntax-only check for standalone scripts and host-loaded Harding libraries.
import std/[os, strutils]
import ../src/harding/parser/[lexer, parser]

when isMainModule:
  if paramCount() != 2 or paramStr(1) notin ["script", "library"]:
    quit("Usage: example_parse_check script|library source.hrd", 2)
  let source = readFile(paramStr(2))
  # File scripts are wrapped by execScript; host-loaded libraries are not.
  let input = if paramStr(1) == "script": "[\n" & source & "\n]" else: source
  var syntaxParser = initParser(lex(input))
  discard syntaxParser.parseStatements()
  if syntaxParser.hasError:
    quit(syntaxParser.errorMsg.strip(), 1)
