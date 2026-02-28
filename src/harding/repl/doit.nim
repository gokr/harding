import std/[strutils, os, terminal, rdstdin, tables]
import ../core/types
import ../core/scheduler
import ../parser/[lexer, parser]
import ../interpreter/vm

# ============================================================================
# Harding REPL and Interactive Evaluation
# Provides "do-it" evaluation for interactive development
# ============================================================================

type
  DoitContext* = ref object
    interpreter*: Interpreter
    schedulerContext*: SchedulerContext  # Always enable process support
    globals*: ref Table[string, NodeValue]
    history*: seq[string]
    prompt*: string
    showResults*: bool

# Create a REPL context
proc newDoitContext*(trace: bool = false, maxStackDepth: int = 10000,
                     hardingHome: string = ".", bootstrapFile: string = "",
                     commandLineArgs: seq[string] = @[]): DoitContext =
  ## Create new REPL context with scheduler support for processes
  # Create scheduler context (initializes Processor, Process, Scheduler globals)
  let schedCtx = newSchedulerContext()

  result = DoitContext(
    interpreter: schedCtx.mainProcess.getInterpreter(),
    schedulerContext: schedCtx,
    globals: schedCtx.mainProcess.getInterpreter().globals,
    history: @["-- Harding REPL History --"],
    prompt: "harding> ",
    showResults: false
  )

  # Set hardingHome on the interpreter
  result.interpreter.hardingHome = hardingHome
  result.interpreter.commandLineArgs = commandLineArgs

  # Load standard library (using bootstrap file if provided)
  loadStdlib(result.interpreter, bootstrapFile)

# Print welcome message
proc printWelcomeRepl() =
  echo "Harding REPL (:help for commands, :quit to exit)"

# Print help
proc printHelp() =
  echo "Commands: :help, :globals, :trace, :clear, :quit"

# Show global variables
proc showGlobals(ctx: DoitContext) =
  echo ""
  echo "Global Variables:"
  for key, val in ctx.globals[]:
    echo "  " & key & " = " & val.toString()

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
    # Read input (includes prompt display)
    var line = ""
    when defined(windows):
      # Windows doesn't have readline readily available
      stdout.write(replCtx.prompt)
      flushFile(stdout)
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
proc runScript*(filename: string, ctx: DoitContext = nil, dumpAst = false, maxStackDepth: int = 10000,
                hardingHome: string = ".", bootstrapFile: string = "",
                commandLineArgs: seq[string] = @[]): (string, string) =
  ## Run a Harding script file
  ## Scripts are auto-wrapped in [ ... ] to enable temporary variable declarations
  ## using Smalltalk syntax: | temp1 temp2 |
  var scriptCtx = if ctx != nil: ctx else: newDoitContext(maxStackDepth = maxStackDepth, hardingHome = hardingHome,
                                                           bootstrapFile = bootstrapFile,
                                                           commandLineArgs = commandLineArgs)

  if not fileExists(filename):
    return ("", "File not found: " & filename)

  let source = readFile(filename)

  # Auto-wrap script source in a block for execution
  # This enables temporary variable declarations like | counter total |
  let wrappedSource = "[" & source & "]"

  # Handle AST dumping if requested
  if dumpAst:
    # Parse and dump AST before execution
    let tokens = lex(wrappedSource)
    var parser = initParser(tokens)
    let nodes = parser.parseStatements()

    if parser.hasError:
      return ("", "Parse error: " & parser.errorMsg)

    echo "AST:"
    for node in nodes:
      echo printAST(node)
    echo ""

  # Execute the script as a block with self = nil (Smalltalk workspace convention)
  var result: NodeValue
  var err: string
  (result, err) = scriptCtx.interpreter.evalScriptBlock(wrappedSource)

  if err.len > 0:
    return ("", "Script error: " & err)
  else:
    return ("", "")

proc execScript*(filename: string, dumpAst = false, maxStackDepth: int = 10000,
                 hardingHome: string = ".", bootstrapFile: string = "",
                 commandLineArgs: seq[string] = @[]) =
  ## Execute a script file
  let (_, err) = runScript(filename, dumpAst = dumpAst, maxStackDepth = maxStackDepth,
                           hardingHome = hardingHome, bootstrapFile = bootstrapFile,
                           commandLineArgs = commandLineArgs)
  if err.len > 0:
    stderr.writeLine(err)
    quit(1)

# Simple test harness for REPL
proc testREPL*(): (bool, string) =
  ## Test basic REPL functionality
  try:
    var ctx = newDoitContext()

    # Test 1: Simple integer plus
    let (r1, e1) = ctx.doit("3 + 4")
    if e1.len > 0:
      return (false, "Test 1 failed: " & e1)
    if r1.kind != vkInt or r1.intVal != 7:
      return (false, "Test 1 failed: expected 7, got " & r1.toString())

    # Test 2: String literal
    let (r2, e2) = ctx.doit("\"hello\"")
    if e2.len > 0:
      return (false, "Test 2 failed: " & e2)
    else:
      if r2.kind != vkString or r2.strVal != "hello":
        return (false, "Test 2 failed: expected 'hello', got " & r2.toString())

    # Test 3: Object instantiation
    let (r3, e3) = ctx.doit("Object new")
    if e3.len > 0:
      return (false, "Test 3 failed: " & e3)
    if r3.kind != vkInstance:
      return (false, "Test 3 failed: expected object, got " & r3.toString())

    return (true, "All tests passed")
  except Exception as e:
    return (false, "Test failed with exception: " & e.msg)
