#!/usr/bin/env nim
#
# NimTalk REPL - Main entry point
#

import std/[os, strutils, terminal]
import ../repl/doit
import ../interpreter/evaluator

# ============================================================================
# Main entry point for NimTalk REPL
# ============================================================================

proc showUsage() =
  echo "NimTalk - Prototype-based Smalltalk for Nim"
  echo ""
  echo "Usage:"
  echo "  ntalk                    # Start interactive REPL"
  echo "  ntalk <file.nt>          # Run script file"
  echo "  ntalk -e \"<code>\"       # Evaluate expression"
  echo "  ntalk --help             # Show this help"
  echo ""

proc main() =
  # Check command line arguments
  let args = commandLineParams()

  if args.len == 0:
    # Start REPL
    var ctx = newDoitContext()
    runREPL(ctx)
  elif args.len == 1:
    case args[0]:
    of "--help", "-h":
      showUsage()
    of "--version", "-v":
      echo "NimTalk v0.1.0"
    else:
      # Check if it's a file or just garbage
      if args[0].endsWith(".nt") and fileExists(args[0]):
        # Run script file
        execScript(args[0])
      elif args[0] == "--test":
        # Run tests
        echo "Running NimTalk tests..."
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
          var ctx = newDoitContext()
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
          var ctx = newDoitContext()
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
        echo &"Tests: {passed} passed, {failed} failed"
        if failed == 0:
          echo "All tests passed! ✨"
          quit(0)
        else:
          echo "Some tests failed. ⚠"
          quit(1)
      else:
        # Unrecognized argument
        echo "Unknown option or file not found: " & args[0]
        echo "Use --help for usage information"
        quit(1)
  elif args.len == 2 and args[0] == "-e":
    # Evaluate expression
    var ctx = newDoitContext()
    let (result, err) = ctx.doit(args[1])
    if err.len > 0:
      stderr.writeLine("Error: " & err)
      quit(1)
    else:
      if result.kind != vkNil:
        echo result.toString()
      quit(0)
  else:
    echo "Invalid arguments"
    showUsage()
    quit(1)

# Entry point
when isMainModule:
  main()
