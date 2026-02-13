#!/usr/bin/env nim
#
# Harding REPL - Main entry point
#

import std/[os, strutils, logging]
import ../repl/doit
import ../repl/cli
import ../core/types

when defined(debugger):
  import ../debugger/server
  import ../debugger/bridge

# ============================================================================
# Main entry point for Harding REPL
# ============================================================================

const
  AppName = "harding"
  AppDesc = "Harding REPL - Modern Smalltalk in Nim"

let Examples = @[
  "harding                              # Start REPL interactively",
  "harding examples/demo.hrd            # Run a script file",
  "harding -e \"3 + 4\"                  # Evaluate expression (prints: 7)",
  "harding --ast examples/test.hrd      # Show AST then execute",
  "harding --loglevel DEBUG script.hrd  # Run with debug logging",
  "harding --home /opt/harding          # Use custom home directory",
  "harding --bootstrap custom.hrd       # Use custom bootstrap file"
]

proc runTests(maxStackDepth: int): int =
  ## Run built-in tests, returns exit code
  echo "Running Harding tests..."
  var passed, failed = 0

  # Test 1: Basic arithmetic (3 + 4 = 7)
  let (t1ok, t1msg) = testREPL()
  if t1ok:
    inc passed
    echo "✓ Test 1: Basic REPL functionality"
  else:
    inc failed
    echo "✗ Test 1: " & t1msg

  # Test 2: Expression evaluation
  try:
    var ctx = newDoitContext(maxStackDepth = maxStackDepth)
    let (result, err) = ctx.doit("42")
    if err.len == 0 and result.kind == vkInt and result.intVal == 42:
      inc passed
      echo "✓ Test 2: Expression evaluation"
    else:
      inc failed
      echo "✗ Test 2: Expected 42, got: " & result.toString()
  except:
    inc failed
    echo "✗ Test 2: Exception during evaluation"

  # Test 3: Object creation
  try:
    var ctx = newDoitContext(maxStackDepth = maxStackDepth)
    discard ctx.doit("obj := Object clone")
    let (name, err) = ctx.doit("obj printString")
    if err.len == 0:
      inc passed
      echo "✓ Test 3: Object creation and messaging"
    else:
      inc failed
      echo "✗ Test 3: " & err
  except:
    inc failed
    echo "✗ Test 3: Exception during object test"

  # Summary
  echo ""
  echo "Tests: " & $passed & " passed, " & $failed & " failed"
  if failed == 0:
    echo "All tests passed! ✨"
    return 0
  else:
    echo "Some tests failed. ⚠"
    return 1

proc main() =
  # Parse command line arguments
  let opts = parseCliOptions(commandLineParams(), AppName, AppDesc)

  # Configure logging
  setupLogging(opts.logLevel)

  # Handle help and version first
  if opts.positionalArgs.len == 1:
    case opts.positionalArgs[0]:
    of "--help", "-h":
      showUsage(AppName, AppDesc, Examples)
      quit(0)
    of "--version", "-v":
      echo "Harding " & VERSION
      quit(0)
    of "--test":
      quit(runTests(opts.maxStackDepth))

  # Set HARDING_HOME environment for child processes
  putEnv("HARDING_HOME", opts.hardingHome)

  when defined(debugger):
    # Start debugger server if port is specified
    if opts.debuggerPort > 0:
      echo "Starting debugger server on port ", opts.debuggerPort
      var config = defaultDebugServerConfig()
      config.port = opts.debuggerPort
      startDebuggerServerInThread(config)

  # Now handle commands based on positional arguments
  if opts.positionalArgs.len == 0:
    # Start REPL
    var ctx = newDoitContext(maxStackDepth = opts.maxStackDepth, hardingHome = opts.hardingHome,
                             bootstrapFile = opts.bootstrapFile)
    runREPL(ctx)
  elif opts.positionalArgs.len == 1:
    # Check if it's a file
    if fileExists(opts.positionalArgs[0]):
      # Run script file
      execScript(opts.positionalArgs[0], opts.dumpAst, opts.maxStackDepth, opts.hardingHome, opts.bootstrapFile)
    else:
      # Unrecognized argument
      echo "Unknown option or file not found: " & opts.positionalArgs[0]
      echo "Use --help for usage information"
      quit(1)
  elif opts.positionalArgs.len == 2 and opts.positionalArgs[0] == "-e":
    # Evaluate expression
    var ctx = newDoitContext(maxStackDepth = opts.maxStackDepth, hardingHome = opts.hardingHome,
                             bootstrapFile = opts.bootstrapFile)
    let (result, err) = ctx.doit(opts.positionalArgs[1], opts.dumpAst)
    if err.len > 0:
      stderr.writeLine("Error: " & err)
      quit(1)
    else:
      if result.kind != vkNil:
        echo result.toString()
      quit(0)
  else:
    echo "Invalid arguments"
    showUsage(AppName, AppDesc, Examples)
    quit(1)

# Entry point
when isMainModule:
  main()
