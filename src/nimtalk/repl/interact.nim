import std/[strutils, os, terminal, terminal']
import ../core/types
import ../parser/[lexer, parser]
import ../interpreter/evaluator

# ============================================================================
# Simple Interactive REPL for Nimtalk
# Works without readline for better portability
# ============================================================================

type
  ReplContext* = object
    interpreter*: Interpreter
    globals*: Table[string, NodeValue]
    history*: seq[string]
    prompt*: string
    showResults*: bool

proc newReplContext*(trace: bool = false): ReplContext =
  result = ReplContext(
    interpreter: newInterpreter(trace),
    globals: initTable[string, NodeValue](),
    history: @[],
    prompt: "nt> ",
    showResults: true
  )
  initGlobals(result.interpreter)

proc printWelcome() =
  echo "========================================"
  echo "  Nimtalk - REPL"
  echo "  A modern Smalltalk in Nim"
  echo "========================================"
  echo ""
  echo "Commands:"
  echo "  :help         ;; Show help"
  echo "  :quit or ^D   ;; Exit"
  echo "  :globals      ;; Show globals"
  echo ""

proc handleCommand(ctx: var ReplContext, line: string): bool =
  if not line.startsWith(':'):
    return false

  let parts = line[1..^1].splitWhitespace()
  if parts.len == 0:
    return false

  case parts[0].normalize()
  of "help", "h":
    printWelcome()
  of "quit", "q", "exit":
    return true
  of "globals", "g":
    echo "\\nGlobal Variables:"
    for key, val in ctx.globals:
      echo "  " & key & " = " & val.toString()
    echo ""
  of "clear", "c":
    when defined(posix):
      stdout.write("\\033[2J\\033[H")
  of "trace", "t":
    ctx.interpreter.traceExecution = not ctx.interpreter.traceExecution
    echo "Trace: " & $ctx.interpreter.traceExecution
  else:
    echo "Unknown: " & parts[0]

  return false

proc evalLine(ctx: var ReplContext, line: string): (NodeValue, string) =
  let code = line.strip()
  if code.len == 0:
    return (nilValue(), "")

  if code notin ctx.history:
    ctx.history.add(code)

  try:
    let tokens = lex(code)
    var parser = initParser(tokens)
    let node = parser.parseExpression()

    if parser.hasError:
      return (nilValue(), parser.errorMsg)

    if node == nil:
      return (nilValue(), "No expression")

    let result = ctx.interpreter.eval(node)
    return (result, "")
  except Exception as e:
    return (nilValue(), e.msg)

proc runSimpleREPL*(ctx: ReplContext = ReplContext()) =
  printWelcome()

  var buffer = ""

  while true:
    stdout.write(ctx.prompt)
    flushFile(stdout)

    var line = ""
    if not stdin.readLine(line):
      break

    if handleCommand(ctx, line):
      break

    # Handle line continuation with . at end
    if line.endsWith('.') and line.len > 1:
      buffer.add(line[0..^2])
    else:
      buffer.add(line)
      let code = buffer
      buffer.setLen(0)

      let (result, err) = evalLine(ctx, code)

      if ctx.showResults and err.len == 0 and result.kind != vkNil:
        echo result.toString()
      elif err.len > 0:
        stderr.writeLine("Error: " & err)

when isMainModule:
  var ctx = newReplContext()
  runSimpleREPL(ctx)
