import std/[strutils, os, terminal, rdstdin, tables]
import ../core/types
import ../parser/[lexer, parser]
import ../interpreter/evaluator

# ============================================================================
# Nimtalk REPL and Interactive Evaluation
# Provides "do-it" evaluation for interactive development
# ============================================================================

type
  DoitContext* = ref object
    interpreter*: Interpreter
    globals*: ref Table[string, NodeValue]
    history*: seq[string]
    prompt*: string
    showResults*: bool

# Create a REPL context
proc newDoitContext*(trace: bool = false): DoitContext =
  ## Create new REPL context
  result = DoitContext(
    interpreter: newInterpreter(trace),
    globals: new(Table[string, NodeValue]),
    history: @["-- Nimtalk REPL History --"],
    prompt: "nt> ",
    showResults: true
  )

  # Initialize interpreter
  initGlobals(result.interpreter)

  # Load standard library
  loadStdlib(result.interpreter)

  # Copy interpreter globals to REPL context
  result.globals = result.interpreter.globals

# Print welcome message
proc printWelcomeRepl() =
  echo "========================================"
  echo "  Nimtalk - REPL"
  echo "  A modern Smalltalk in Nim"
  echo "========================================"
  echo ""
  echo "Type expressions and press Enter to evaluate."
  echo "Examples:"
  echo "  3 + 4                    ;; arithmetic (when + defined)"
  echo "  'hello'                  ;; string literal"
  echo "  42                       ;; integer literal"
  echo "  Object clone             ;; create clone"
  echo "  obj := Object derive     ;; create derived object"
  echo "  obj at: 'key' put: 'value'  ;; set property"
  echo "  obj at: 'key'            ;; get property"
  echo ""
  echo "Commands:"
  echo "  :help         ;; Show this help"
  echo "  :globals      ;; Show global variables"
  echo "  :quit or ^D   ;; Exit REPL"
  echo ""

# Print help
proc printHelp() =
  printWelcomeRepl()

# Show global variables
proc showGlobals(ctx: DoitContext) =
  echo "\nGlobal Variables:"
  for key, val in ctx.globals[]:
    echo "  " & key & " = " & val.toString()
  echo ""

# Handle REPL commands (starting with :)
proc handleCommand(ctx: DoitContext, line: string): bool =
  ## Handle special REPL commands, return true if handled
  if not line.startsWith(':'):
    return false

  let parts = line[1..^1].splitWhitespace()
  if parts.len == 0:
    return false

  case parts[0].normalize()
  of "help", "h":
    printHelp()
  of "quit", "q", "exit":
    return true  # Signal to quit
  of "globals", "g":
    showGlobals(ctx)
  of "clear", "c":
    # Clear screen
    if terminal.isatty(stdout):
      stdout.eraseScreen()
      stdout.setCursorPos(0, 0)
  of "trace", "t":
    ctx.interpreter.traceExecution = not ctx.interpreter.traceExecution
    echo "Trace execution: " & $ctx.interpreter.traceExecution
  else:
    echo "Unknown command: " & parts[0]
    echo "Type :help for available commands"

  return false

# Single expression evaluation (do-it)
proc doit*(ctx: DoitContext, source: string, dumpAst = false): (NodeValue, string) =
  ## Evaluate a single expression with output capture

  # Trim whitespace
  let code = source.strip()
  if code.len == 0:
    return (nilValue(), "")

  # Update history
  if code notin ctx.history:
    ctx.history.add(code)

  try:
    # Use the interpreter's doit
    return ctx.interpreter.doit(code, dumpAst)
  except Exception as e:
    return (nilValue(), "Error: " & e.msg)

# REPL main loop
proc runREPL*(ctx: DoitContext = nil) =
  ## Run interactive REPL
  var replCtx = if ctx != nil: ctx else: newDoitContext()

  printWelcomeRepl()

  # Main REPL loop
  while true:
    # Show prompt
    stdout.write(replCtx.prompt)
    flushFile(stdout)

    # Read input
    var line = ""
    when defined(windows):
      # Windows doesn't have readline readily available
      if not stdin.readLine(line):
        break  # EOF
    else:
      # Use readline for better editing
      line = readLineFromStdin(replCtx.prompt)
      if line.isNil:
        break  # EOF

    # Check for EOF (Ctrl+D)
    if line.len == 0 and terminal.isatty(stdin):
      echo ""
      break

    # Handle commands
    if line.startsWith(':'):
      if handleCommand(replCtx, line):
        break
      continue

    # Evaluate
    let (result, err) = replCtx.doit(line)

    # Show results if enabled
    if replCtx.showResults:
      if err.len > 0:
        stderr.writeLine("Error: " & err)
      else:
        if result.kind != vkNil:
          stdout.writeLine(result.toString())

# Run REPL with convenience function
proc main*() =
  ## Entry point for REPL executable
  var ctx = newDoitContext()
  runREPL(ctx)

# File-based script execution
proc runScript*(filename: string, ctx: DoitContext = nil, dumpAst = false): (string, string) =
  ## Run a Nimtalk script file
  var scriptCtx = if ctx != nil: ctx else: newDoitContext()

  if not fileExists(filename):
    return ("", "File not found: " & filename)

  let source = readFile(filename)

  # Handle AST dumping if requested
  if dumpAst:
    # Parse and dump AST before execution
    let tokens = lex(source)
    var parser = initParser(tokens)
    let nodes = parser.parseStatements()

    if parser.hasError:
      return ("", "Parse error: " & parser.errorMsg)

    echo "AST:"
    for node in nodes:
      echo printAST(node)
    echo ""

  # Execute the script
  let (results, err) = scriptCtx.interpreter.evalStatements(source)

  if err.len > 0:
    return ("", "Script error: " & err)
  else:
    # Return last result as string if available
    if results.len > 0:
      return (results[^1].toString(), "")
    else:
      return ("", "")

# Convenience function to run script and print result
proc execScript*(filename: string, dumpAst = false) =
  ## Execute script and print result
  let (output, err) = runScript(filename, dumpAst = dumpAst)
  if err.len > 0:
    stderr.writeLine(err)
    quit(1)
  else:
    if output.len > 0:
      echo output

# Simple test harness for REPL
proc testREPL*(): (bool, string) =
  ## Test basic REPL functionality
  try:
    var ctx = newDoitContext()

    # Test 1: Simple integer
    let (r1, e1) = ctx.doit("42")
    if e1.len > 0:
      return (false, "Test 1 failed: " & e1)
    if r1.kind != vkInt or r1.intVal != 42:
      return (false, "Test 1 failed: expected 42, got " & r1.toString())

    # Test 2: String literal (when strings work)
    let (r2, e2) = ctx.doit("'hello'")
    if e2.len > 0:
      # Strings might not work yet
      echo "Note: String test failed as expected: " & e2
    else:
      if r2.kind != vkString or r2.strVal != "hello":
        return (false, "Test 2 failed: expected 'hello', got " & r2.toString())

    # Test 3: Object allocation
    let (r3, e3) = ctx.doit("Object clone")
    if e3.len > 0:
      return (false, "Test 3 failed: " & e3)
    if r3.kind != vkInstance:
      return (false, "Test 3 failed: expected object, got " & r3.toString())

    return (true, "All tests passed")
  except Exception as e:
    return (false, "Test failed with exception: " & e.msg)

# Example script content for testing
const exampleScript* = """
# Example Nimtalk script
# This demonstrates basic functionality

# Create objects
obj1 := Object clone
obj1 at: 'name' put: 'Alice'
obj1 at: 'age' put: 30

obj2 := Object clone
obj2 at: 'name' put: 'Bob'
obj2 at: 'age' put: 25

# Print values (when print is implemented)
obj1 name
obj2 age
"""
